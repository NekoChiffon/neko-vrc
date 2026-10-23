import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 主题模式：跟随系统 / 深色 / 浅色，存在本地。
class AppearanceController extends Notifier<ThemeMode> {
  File? _file;
  bool _loading = false;

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark;
  }

  Future<File?> _ensureFile() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}appearance.json');
      return _file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final file = await _ensureFile();
      if (file == null || !file.existsSync()) return;
      final data = jsonDecode(await file.readAsString());
      final raw = data is Map ? data['themeMode']?.toString() : null;
      final mode = switch (raw) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.dark,
      };
      state = mode;
    } catch (_) {
      // 读不出来就用默认的深色
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final file = await _ensureFile();
      await file?.writeAsString(
        jsonEncode({'themeMode': mode.name}),
        flush: true,
      );
    } catch (_) {
      // 写失败不影响本次切换
    }
  }
}

final appearanceProvider = NotifierProvider<AppearanceController, ThemeMode>(
  AppearanceController.new,
);
