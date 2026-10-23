import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

/// 提醒范围：全部好友 / 只提醒指定收藏分组 / 只提醒指定好友。
enum NotifyScope { all, groups, selected }

/// 本地提醒的全部开关，持久化在 `friend_notify.json`。
@immutable
class NotifySettings {
  const NotifySettings({
    this.online = false,
    this.offline = false,
    this.friendRequest = false,
    this.serviceStatus = false,
    this.scope = NotifyScope.all,
    this.groupNames = const [],
    this.userIds = const [],
    this.seenRequests = const [],
  });

  final bool online;
  final bool offline;

  /// 收到好友申请时提醒。
  final bool friendRequest;

  /// VRChat 服务异常 / 恢复时提醒。
  final bool serviceStatus;

  final NotifyScope scope;

  /// [NotifyScope.groups] 时生效，存收藏夹内部名。
  final List<String> groupNames;

  /// [NotifyScope.selected] 时生效。
  final List<String> userIds;

  /// 已经提醒过的好友申请 ID，避免重复弹。
  final List<String> seenRequests;

  bool get anyFriend => online || offline;

  NotifySettings copyWith({
    bool? online,
    bool? offline,
    bool? friendRequest,
    bool? serviceStatus,
    NotifyScope? scope,
    List<String>? groupNames,
    List<String>? userIds,
    List<String>? seenRequests,
  }) {
    return NotifySettings(
      online: online ?? this.online,
      offline: offline ?? this.offline,
      friendRequest: friendRequest ?? this.friendRequest,
      serviceStatus: serviceStatus ?? this.serviceStatus,
      scope: scope ?? this.scope,
      groupNames: groupNames ?? this.groupNames,
      userIds: userIds ?? this.userIds,
      seenRequests: seenRequests ?? this.seenRequests,
    );
  }

  Map<String, dynamic> toJson() => {
        'online': online,
        'offline': offline,
        'friendRequest': friendRequest,
        'serviceStatus': serviceStatus,
        'scope': scope.name,
        'groupNames': groupNames,
        'userIds': userIds,
        'seenRequests': seenRequests,
      };

  static NotifySettings fromJson(Map<String, dynamic> json) {
    // 旧版本只有一个 enabled 开关，迁移成「上线提醒」。
    final legacyEnabled = json['online'] is bool
        ? json['online'] as bool
        : (json['enabled'] is bool ? json['enabled'] as bool : false);

    return NotifySettings(
      online: legacyEnabled,
      offline: json['offline'] is bool ? json['offline'] as bool : false,
      friendRequest:
          json['friendRequest'] is bool ? json['friendRequest'] as bool : false,
      serviceStatus:
          json['serviceStatus'] is bool ? json['serviceStatus'] as bool : false,
      scope: switch (json['scope']?.toString()) {
        'groups' => NotifyScope.groups,
        'selected' => NotifyScope.selected,
        _ => NotifyScope.all,
      },
      groupNames: _strings(json['groupNames']),
      userIds: _strings(json['userIds']),
      seenRequests: _strings(json['seenRequests']),
    );
  }

  static List<String> _strings(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
}

/// 本地通知。
///
/// 只在 App 进程活着的时候工作（实时通道或轮询发现变化就弹一条）；
/// 没有后台常驻服务，杀掉 App 后不会提醒。
class FriendNotifier {
  FriendNotifier._();

  static final FriendNotifier instance = FriendNotifier._();

  static const _onlineChannel = 'friend_online';
  static const _offlineChannel = 'friend_offline';
  static const _requestChannel = 'friend_request';
  static const _statusChannel = 'service_status';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<NotifySettings> _settings =
      ValueNotifier(const NotifySettings());

  ValueListenable<NotifySettings> get settings => _settings;

  bool _ready = false;
  File? _file;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      const init = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings: init);
      await _load();
    } catch (e) {
      debugPrint('初始化本地通知失败: $e');
    }
  }

  Future<File?> _ensureFile() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}friend_notify.json');
      return _file;
    } catch (e) {
      debugPrint('定位通知设置文件失败: $e');
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final file = await _ensureFile();
      if (file == null || !file.existsSync()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is Map) {
        _settings.value = NotifySettings.fromJson(
          Map<String, dynamic>.from(data),
        );
      }
    } catch (e) {
      debugPrint('读取通知设置失败（忽略）: $e');
    }
  }

  Future<void> _save() async {
    try {
      final file = await _ensureFile();
      await file?.writeAsString(jsonEncode(_settings.value.toJson()),
          flush: true);
    } catch (e) {
      debugPrint('写入通知设置失败（忽略）: $e');
    }
  }

  Future<void> update(NotifySettings next) async {
    _settings.value = next;
    await _save();
  }

  Future<void> setOnline(bool value) =>
      update(_settings.value.copyWith(online: value));

  Future<void> setOffline(bool value) =>
      update(_settings.value.copyWith(offline: value));

  Future<void> setFriendRequest(bool value) =>
      update(_settings.value.copyWith(friendRequest: value));

  Future<void> setServiceStatus(bool value) =>
      update(_settings.value.copyWith(serviceStatus: value));

  Future<void> setScope(NotifyScope scope) =>
      update(_settings.value.copyWith(scope: scope));

  Future<void> setGroupNames(List<String> names) =>
      update(_settings.value.copyWith(groupNames: names));

  Future<void> setUserIds(List<String> ids) =>
      update(_settings.value.copyWith(userIds: ids));

  /// 这个好友在不在提醒范围里。[groups] 是他所属的好友收藏夹内部名。
  bool allows(String userId, Set<String> groups) {
    final s = _settings.value;
    return switch (s.scope) {
      NotifyScope.all => true,
      NotifyScope.groups =>
        s.groupNames.any(groups.contains),
      NotifyScope.selected => s.userIds.contains(userId),
    };
  }

  /// Android 13+ 需要运行时通知权限。返回 false 表示被拒绝。
  Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (e) {
      debugPrint('申请通知权限失败: $e');
      return false;
    }
  }

  Future<void> _show({
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
    int? id,
    Importance importance = Importance.high,
    Priority priority = Priority.high,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id ?? (title.hashCode & 0x7fffffff),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: importance,
            priority: priority,
          ),
        ),
      );
    } catch (e) {
      debugPrint('发送通知失败（$channelId）: $e');
    }
  }

  /// 好友进游戏（非 Web）时调用。
  Future<void> notifyOnline(String displayName) async {
    final s = _settings.value;
    if (!s.online || displayName.isEmpty) return;
    await _show(
      channelId: _onlineChannel,
      channelName: '好友上线',
      channelDescription: '好友进入 VRChat 时提醒',
      title: '$displayName 上线了',
      body: '打开 Neko VRC 看看在哪个世界',
      id: ('online:$displayName').hashCode & 0x7fffffff,
    );
  }

  Future<void> notifyOffline(String displayName) async {
    final s = _settings.value;
    if (!s.offline || displayName.isEmpty) return;
    await _show(
      channelId: _offlineChannel,
      channelName: '好友下线',
      channelDescription: '好友离开 VRChat 时提醒',
      title: '$displayName 下线了',
      body: '刚刚离开了 VRChat',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      id: ('offline:$displayName').hashCode & 0x7fffffff,
    );
  }

  /// 处理一批通知，把新出现的好友申请弹出来。
  ///
  /// 第一次运行（还没有历史记录）只建立基线，避免把已有的申请全弹一遍。
  Future<void> handleFriendRequests(
    Iterable<({String id, String sender})> requests,
  ) async {
    final s = _settings.value;
    if (!s.friendRequest) return;

    final seen = s.seenRequests.toSet();
    final firstRun = seen.isEmpty;
    final fresh = <({String id, String sender})>[];
    for (final r in requests) {
      if (seen.add(r.id)) fresh.add(r);
    }
    if (fresh.isEmpty) return;

    // 只保留最近 200 条，防止文件无限增长。
    final keep = seen.toList();
    final trimmed = keep.length > 200 ? keep.sublist(keep.length - 200) : keep;
    _settings.value = s.copyWith(seenRequests: trimmed);
    await _save();

    if (firstRun) return;
    for (final r in fresh) {
      await _show(
        channelId: _requestChannel,
        channelName: '好友申请',
        channelDescription: '收到新的好友申请时提醒',
        title: '新的好友请求',
        body: r.sender.isEmpty ? '有人想加你为好友' : '${r.sender} 想加你为好友',
        id: ('request:${r.id}').hashCode & 0x7fffffff,
      );
    }
  }

  /// VRChat 服务状态异常 / 恢复。
  Future<void> notifyServiceStatus({
    required String title,
    required String body,
  }) async {
    if (!_settings.value.serviceStatus) return;
    await _show(
      channelId: _statusChannel,
      channelName: 'VRChat 服务状态',
      channelDescription: 'VRChat 服务异常或恢复时提醒',
      title: title,
      body: body,
      id: ('status:$title').hashCode & 0x7fffffff,
    );
  }
}
