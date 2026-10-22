import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 自己进过的房间（本地记录）。
///
/// VRCX 能显示完整历史是因为常年挂机记录 location 变化；我们没有那个条件，
/// 只能在 app 启动和手动刷新时记一笔。记录从现在开始积累，越多越有用。
class MyRoomsHistoryController extends Notifier<List<Map<String, String>>> {
  File? _file;
  bool _loaded = false;

  @override
  List<Map<String, String>> build() {
    _load();
    return const <Map<String, String>>[];
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}my_rooms.json');
      if (!_file!.existsSync()) return;
      final data = jsonDecode(await _file!.readAsString());
      if (data is List) {
        state = [
          for (final e in data)
            if (e is Map) e.map((k, v) => MapEntry(k.toString(), v.toString())),
        ];
      }
    } catch (e) {
      debugPrint('读取房间历史失败（忽略）: $e');
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode(state), flush: true);
    } catch (e) {
      debugPrint('保存房间历史失败（忽略）: $e');
    }
  }

  /// 记一条。location 为空 / 离线 / 没变化时跳过。最新的在前，最多 200 条。
  Future<void> record(String? location) async {
    if (location == null || location.isEmpty) return;
    final lower = location.toLowerCase();
    if (lower == 'offline' ||
        lower.startsWith('offline') ||
        lower == 'private' ||
        lower.startsWith('local') ||
        lower.startsWith('traveling')) {
      return;
    }
    await _load();
    if (state.isNotEmpty && state.first['loc'] == location) return;

    final next = <Map<String, String>>[
      {
        'loc': location,
        'at': DateTime.now().toIso8601String(),
      },
      ...state,
    ];
    if (next.length > 200) next.removeRange(200, next.length);
    state = next;
    await _save();
  }
}

final myRoomsHistoryProvider =
    NotifierProvider<MyRoomsHistoryController, List<Map<String, String>>>(
  MyRoomsHistoryController.new,
);
