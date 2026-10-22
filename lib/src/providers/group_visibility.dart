import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 分组类型的 key（好友页的分组筛选）。
const groupKindRoom = 'room';
const groupKindPrivate = 'private';
const groupKindWeb = 'web';
const groupKindUnknown = 'unknown';
const groupKindOffline = 'offline';

/// 分组类型的中文名，和好友页一一对应。
const groupKindLabels = <String, String>{
  groupKindRoom: '在世界里',
  groupKindPrivate: '私密世界',
  groupKindWeb: 'Web 在线',
  groupKindUnknown: '位置不可见',
  groupKindOffline: '离线',
};

/// 哪些分组被隐藏了。存在本地文件里，重启后还记得。
class GroupVisibilityController extends Notifier<Set<String>> {
  File? _file;
  bool _loaded = false;

  @override
  Set<String> build() {
    _load();
    return const <String>{};
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}group_visibility.json');
      if (!_file!.existsSync()) return;
      final data = jsonDecode(await _file!.readAsString());
      if (data is List) {
        state = data.map((e) => e.toString()).toSet();
      }
    } catch (e) {
      debugPrint('读取分组设置失败（忽略）: $e');
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode(state.toList()), flush: true);
    } catch (e) {
      debugPrint('保存分组设置失败（忽略）: $e');
    }
  }

  bool isVisible(String kind) => !state.contains(kind);

  void toggle(String kind) {
    final next = {...state};
    if (!next.add(kind)) next.remove(kind);
    state = next;
    _save();
  }
}

final groupVisibilityProvider =
    NotifierProvider<GroupVisibilityController, Set<String>>(
  GroupVisibilityController.new,
);
