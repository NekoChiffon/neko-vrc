import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// 上次登录过的账号，用来在登录页显示「一键登录」卡片。
class SavedAccount {
  const SavedAccount({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.savedAt,
    this.username = '',
  });

  final String userId;
  final String displayName;
  final String avatarUrl;
  final String savedAt;

  /// 登录用的用户名/邮箱（只用于预填输入框，不存密码）。
  final String username;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'savedAt': savedAt,
        'username': username,
      };

  static SavedAccount? fromJson(Map<String, dynamic> json) {
    final id = json['userId']?.toString() ?? '';
    if (id.isEmpty) return null;
    return SavedAccount(
      userId: id,
      displayName: json['displayName']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      savedAt: json['savedAt']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
    );
  }
}

class SavedAccountController extends Notifier<SavedAccount?> {
  File? _file;
  bool _loaded = false;

  @override
  SavedAccount? build() {
    _load();
    return null;
  }

  Future<File?> _ensureFile() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}saved_account.json');
      return _file;
    } catch (e) {
      debugPrint('定位保存账号文件失败: $e');
      return null;
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _ensureFile();
      if (file == null || !file.existsSync()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is Map) {
        state = SavedAccount.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('读取保存账号失败（忽略）: $e');
    }
  }

  Future<void> save({
    required String userId,
    required String displayName,
    required String avatarUrl,
    String username = '',
  }) async {
    // 老记录里可能没有 username，这次没传就沿用上次的。
    final keepUsername =
        username.isNotEmpty ? username : (state?.username ?? '');
    final account = SavedAccount(
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      savedAt: DateTime.now().toIso8601String(),
      username: keepUsername,
    );
    state = account;
    try {
      final file = await _ensureFile();
      await file?.writeAsString(jsonEncode(account.toJson()), flush: true);
    } catch (e) {
      debugPrint('写入保存账号失败（忽略）: $e');
    }
  }

  Future<void> clear() async {
    state = null;
    try {
      final file = await _ensureFile();
      if (file != null && file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('清除保存账号失败（忽略）: $e');
    }
  }
}

final savedAccountProvider =
    NotifierProvider<SavedAccountController, SavedAccount?>(
  SavedAccountController.new,
);

// ---------------------------------------------------------------------------
// 记住的密码（可选）
// ---------------------------------------------------------------------------

/// 密码存在系统的加密存储里（Android Keystore），不进明文文件。
class SavedPassword {
  static const _storage = FlutterSecureStorage();

  static String _key(String userId) => 'vrc_pwd_$userId';

  static Future<void> save(String userId, String password) async {
    try {
      await _storage.write(key: _key(userId), value: password);
    } catch (e) {
      debugPrint('保存密码失败（忽略）: $e');
    }
  }

  static Future<String?> read(String userId) async {
    try {
      return await _storage.read(key: _key(userId));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String userId) async {
    try {
      await _storage.delete(key: _key(userId));
    } catch (_) {
      // 忽略
    }
  }
}
