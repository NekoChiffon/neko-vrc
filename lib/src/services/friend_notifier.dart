import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

/// 好友上线的本地通知。
///
/// 只在 App 进程活着的时候工作（实时通道或轮询发现好友进游戏就弹一条）；
/// 没有后台常驻服务，杀掉 App 后不会提醒。
class FriendNotifier {
  FriendNotifier._();

  static final FriendNotifier instance = FriendNotifier._();

  static const _channelId = 'friend_online';
  static const _channelName = '好友上线';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final ValueNotifier<bool> _enabled = ValueNotifier(false);

  ValueListenable<bool> get enabled => _enabled;

  bool _ready = false;
  File? _file;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings: settings);
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
      if (data is Map && data['enabled'] is bool) {
        _enabled.value = data['enabled'] as bool;
      }
    } catch (e) {
      debugPrint('读取通知设置失败（忽略）: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled.value = value;
    try {
      final file = await _ensureFile();
      await file?.writeAsString(jsonEncode({'enabled': value}), flush: true);
    } catch (e) {
      debugPrint('写入通知设置失败（忽略）: $e');
    }
  }

  /// Android 13+ 需要运行时通知权限。返回 false 表示被拒绝。
  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (e) {
      debugPrint('申请通知权限失败: $e');
      return false;
    }
  }

  /// 好友进游戏（非 Web）时调用。
  Future<void> notifyOnline(String displayName) async {
    if (!_ready || !_enabled.value || displayName.isEmpty) return;
    try {
      await _plugin.show(
        id: displayName.hashCode & 0x7fffffff,
        title: '$displayName 上线了',
        body: '打开 Neko VRC 看看在哪个世界',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: '好友进入 VRChat 时提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('发送好友上线通知失败: $e');
    }
  }
}
