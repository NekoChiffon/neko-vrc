import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/app_info.dart';
import 'friend_notifier.dart';

/// 盯着 VRChat 的官方状态页，异常 / 恢复时弹一条本地通知。
///
/// 用的是 statuspage 的公开接口，不需要登录。只有 App 进程活着时才轮询。
class ServiceStatusWatcher {
  ServiceStatusWatcher._();

  static final ServiceStatusWatcher instance = ServiceStatusWatcher._();

  static const _endpoint = 'https://vrchat.statuspage.io/api/v2/status.json';

  Timer? _timer;
  bool _started = false;
  String? _lastIndicator;
  File? _file;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _load();
    // 启动时先等一会儿，别和登录、好友列表抢网络。
    Timer(const Duration(seconds: 20), () => unawaited(_poll()));
    _timer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => unawaited(_poll()),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<File?> _ensureFile() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}service_status.json');
      return _file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final file = await _ensureFile();
      if (file == null || !file.existsSync()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data['indicator'] is String) {
        _lastIndicator = data['indicator'] as String;
      }
    } catch (e) {
      debugPrint('读取服务状态缓存失败（忽略）: $e');
    }
  }

  Future<void> _save(String indicator) async {
    try {
      final file = await _ensureFile();
      await file?.writeAsString(
        jsonEncode({'indicator': indicator}),
        flush: true,
      );
    } catch (_) {
      // 写失败不影响提醒
    }
  }

  Future<void> _poll() async {
    if (!FriendNotifier.instance.settings.value.serviceStatus) return;
    try {
      final resp = await http.get(
        Uri.parse(_endpoint),
        headers: {'User-Agent': AppInfo.applicationName, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body);
      final status = data is Map ? data['status'] : null;
      if (status is! Map) return;

      final indicator = status['indicator']?.toString() ?? 'none';
      final description = status['description']?.toString() ?? '';

      final previous = _lastIndicator;
      _lastIndicator = indicator;
      await _save(indicator);

      // 首次运行只记基线，不补弹。
      if (previous == null || previous == indicator) return;

      if (indicator == 'none') {
        await FriendNotifier.instance.notifyServiceStatus(
          title: 'VRChat 服务已恢复',
          body: description.isEmpty ? '服务状态恢复正常' : description,
        );
      } else {
        await FriendNotifier.instance.notifyServiceStatus(
          title: 'VRChat 服务异常',
          body: description.isEmpty ? '官方状态页报告了服务异常' : description,
        );
      }
    } catch (e) {
      debugPrint('查询 VRChat 服务状态失败（忽略）: $e');
    }
  }
}
