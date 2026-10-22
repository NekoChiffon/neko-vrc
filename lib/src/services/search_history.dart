import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 最近搜索关键词，存在本机的 JSON 里。
///
/// 只保留最近 10 条，重复的会被提到最前；不涉及任何账号信息。
class SearchHistory {
  const SearchHistory._();

  static const int maxItems = 10;
  static File? _file;

  static Future<File?> _ensureFile() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}search_history.json');
      return _file;
    } catch (e) {
      debugPrint('定位搜索历史文件失败: $e');
      return null;
    }
  }

  static Future<List<String>> load() async {
    try {
      final file = await _ensureFile();
      if (file == null || !file.existsSync()) return const [];
      final data = jsonDecode(await file.readAsString());
      if (data is! List) return const [];
      return data.whereType<String>().take(maxItems).toList();
    } catch (e) {
      debugPrint('读取搜索历史失败（忽略）: $e');
      return const [];
    }
  }

  static Future<void> save(List<String> items) async {
    try {
      final file = await _ensureFile();
      await file?.writeAsString(jsonEncode(items.take(maxItems).toList()));
    } catch (e) {
      debugPrint('写入搜索历史失败（忽略）: $e');
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _ensureFile();
      if (file != null && file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('清除搜索历史失败（忽略）: $e');
    }
  }
}
