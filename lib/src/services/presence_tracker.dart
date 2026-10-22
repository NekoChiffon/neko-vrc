import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 记录的动态类型。
enum PresenceKind {
  online,
  offline,
  moved,
  status,

  /// 好友和我处在同一个实例里。
  met,
}

/// 一条好友动态。
@immutable
class PresenceEvent {
  const PresenceEvent({
    required this.at,
    required this.userId,
    required this.displayName,
    required this.kind,
    this.worldId,
    this.instanceId,
    this.note,
    this.statusDescription,
    this.avatarUrl,
  });

  final DateTime at;
  final String userId;
  final String displayName;
  final PresenceKind kind;

  /// 只在位置 / 相遇事件里有值。
  final String? worldId;

  /// 完整实例 ID（`12345~region(jp)~friends(usr_x)`），用来显示 #实例号 和点进实例页。
  final String? instanceId;

  /// 附加说明：状态事件里是状态名（在线/忙碌…），位置事件里是实例类型和签名。
  final String? note;

  /// 只在 [PresenceKind.status] 时有值：改状态时的状态签名。
  final String? statusDescription;

  /// 记这条动态时的头像地址。好友之后删掉好友也还能显示头像。
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'userId': userId,
    'displayName': displayName,
    'kind': kind.name,
    if (worldId != null) 'worldId': worldId,
    if (instanceId != null) 'instanceId': instanceId,
    if (note != null) 'note': note,
    if (statusDescription != null) 'statusDescription': statusDescription,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
  };

  static PresenceEvent? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    final userId = json['userId'] as String?;
    final name = json['displayName'] as String?;
    final kindName = json['kind'] as String?;
    if (at == null || userId == null || name == null || kindName == null) {
      return null;
    }
    PresenceKind? kind;
    for (final k in PresenceKind.values) {
      if (k.name == kindName) {
        kind = k;
        break;
      }
    }
    if (kind == null) return null;
    return PresenceEvent(
      at: at,
      userId: userId,
      displayName: name,
      kind: kind,
      worldId: json['worldId'] as String?,
      instanceId: json['instanceId'] as String?,
      note: json['note'] as String?,
      statusDescription: json['statusDescription'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

/// 一段停留记录：某人在某个位置从什么时候开始待着。
class _Stint {
  _Stint(this.key, this.since);
  final String key;
  final DateTime since;

  Map<String, dynamic> toJson() => {'key': key, 'since': since.toIso8601String()};
}

/// 好友状态的本地追踪器。
///
/// 两件事：
/// 1. 记住每个人当前停留在哪个实例、从几点开始 —— 用来显示「在这个房间待了多久」
/// 2. 顺带把变化记成流水账 —— 就是「好友动态」页的数据来源
///
/// 全部落在本地文件里，不上传任何地方。VRChat 的接口本身不提供「进入实例的时间」，
/// 这个时长只能靠自己从 Pipeline 事件里推算，首次装上时从当前时刻开始算。
class PresenceTracker {
  final Map<String, _Stint> _stints = {};
  final List<PresenceEvent> _events = [];

  /// 已经「相遇」过的人：好友 id → 当时的实例键。
  ///
  /// 用来保证一次相遇只记一条：刷新和 Pipeline 会反复看到同一批人，
  /// 有这张表才知道谁是新进来的。
  final Map<String, String> _metSeen = {};

  File? _file;
  bool _loaded = false;
  Timer? _saveTimer;

  /// 最多留这么多条动态，多了滚掉最老的。
  static const int _maxEvents = 600;

  List<PresenceEvent> get events => List.unmodifiable(_events);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}presence.json');
      if (!_file!.existsSync()) return;

      final data = jsonDecode(await _file!.readAsString());
      if (data is! Map<String, dynamic>) return;

      final stints = data['stints'];
      if (stints is Map) {
        stints.forEach((k, v) {
          if (v is! Map) return;
          final key = v['key'] as String?;
          final since = DateTime.tryParse(v['since'] as String? ?? '');
          if (key != null && since != null) {
            _stints[k as String] = _Stint(key, since);
          }
        });
      }

      final events = data['events'];
      if (events is List) {
        for (final raw in events) {
          if (raw is! Map) continue;
          final e = PresenceEvent.fromJson(Map<String, dynamic>.from(raw));
          if (e != null) _events.add(e);
        }
      }

      final met = data['met'];
      if (met is Map) {
        met.forEach((k, v) {
          if (k is String && v is String) _metSeen[k] = v;
        });
      }
    } catch (e) {
      debugPrint('读取本地动态失败（忽略）: $e');
    }
  }

  /// 某人停留在 [key] 这个位置的起始时间。
  ///
  /// 位置没变就沿用旧时间；变了（或第一次见）就从现在开始算。
  DateTime sinceFor(String userId, String key) {
    final current = _stints[userId];
    if (current != null && current.key == key) return current.since;
    final now = DateTime.now();
    _stints[userId] = _Stint(key, now);
    _scheduleSave();
    return now;
  }

  /// 位置没变但需要保证有记录（比如刚冷启动，REST 快照里就这一个人）。
  DateTime ensureSince(String userId, String key) => sinceFor(userId, key);

  void record(PresenceEvent event) {
    // Pipeline 和轮询可能在同一分钟内各发现一次同样的变化，短期内同人同类型
    // 只记一条，避免时间线上出现成对重复。
    for (final e in _events.take(15)) {
      if (e.userId != event.userId || e.kind != event.kind) continue;
      if (e.worldId != event.worldId ||
          e.instanceId != event.instanceId ||
          e.note != event.note) {
        continue;
      }
      if (event.at.difference(e.at).inSeconds.abs() < 45) return;
    }

    _events.insert(0, event);
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
    _scheduleSave();
  }

  void clearEvents() {
    _events.clear();
    _scheduleSave();
  }

  /// 只清掉某一天（按本地日期）的动态。
  void clearEventsOfDay(DateTime day) {
    _events.removeWhere(
      (e) =>
          e.at.year == day.year &&
          e.at.month == day.month &&
          e.at.day == day.day,
    );
    _scheduleSave();
  }

  /// 标记「和 [userId] 在同一个实例里」。
  ///
  /// 返回 true 表示这是刚进来（或换了实例）的第一次，应该记一条「相遇」；
  /// 之后同样的实例键再看到就返回 false，避免每 60 秒刷一条。
  bool markMet(String userId, String instanceKey) {
    if (_metSeen[userId] == instanceKey) return false;
    _metSeen[userId] = instanceKey;
    _scheduleSave();
    return true;
  }

  /// 已经不在同一实例（或自己不在世界里）——清掉标记，下次遇到能重新记。
  void clearMet(String userId) {
    if (_metSeen.remove(userId) != null) _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    // 事件密集时别每来一条都写盘。
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      final payload = {
        'stints': {
          for (final e in _stints.entries) e.key: e.value.toJson(),
        },
        'events': _events.map((e) => e.toJson()).toList(),
        'met': _metSeen,
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (e) {
      debugPrint('写本地动态失败（忽略）: $e');
    }
  }

  Future<void> flush() => _save();
}
