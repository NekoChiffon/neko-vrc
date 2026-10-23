import 'dart:convert';
import 'dart:ui' as ui;
import 'package:http_parser/http_parser.dart';
import 'dart:io' as io;

import 'dart:ui' show Color;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import 'profile_backgrounds.dart';

import 'app_info.dart';

/// 登录阶段的三种结果。
enum LoginStatus { success, needTwoFactor, failed }

class LoginResult {
  const LoginResult._(this.status, {this.twoFactorTypes = const [], this.message});

  const LoginResult.success() : this._(LoginStatus.success);

  const LoginResult.needTwoFactor(List<TwoFactorAuthType> types)
    : this._(LoginStatus.needTwoFactor, twoFactorTypes: types);

  const LoginResult.failed(String message) : this._(LoginStatus.failed, message: message);

  final LoginStatus status;
  final List<TwoFactorAuthType> twoFactorTypes;
  final String? message;

  bool get isSuccess => status == LoginStatus.success;
}

/// 对 vrchat_dart 的一层薄封装：
///
/// * 统一 User-Agent（VRChat 要求，不规范会被 moderation）
/// * 把 authCookie 落到应用私有目录，冷启动可以直接复用会话
/// * 把 `(success, failure)` 这种记录式返回翻译成更顺手的结果类型
class VrcClient {
  VrcClient._(this.api);

  final VrchatDart api;

  /// 修补通知数据里可为 null 但 spec 标了必填的字段。
  static void _patchNotificationPayload(dynamic data) {
    void fixOne(dynamic item) {
      if (item is! Map) return;
      final details = item['details'];
      if (details is Map) {
        // boop 通知偶尔不带表情，但模型要求这个字段是 String。
        if (details['inventoryItemId'] == null) {
          details['inventoryItemId'] = '';
        }
      }
    }

    if (data is List) {
      for (final item in data) {
        fixOne(item);
      }
    } else {
      fixOne(data);
    }
  }

  /// 修补通知里 details 为 Map 的情况（spec 声明是 String）。
  static void _patchNotificationDetails(dynamic data) {
    void fixOne(dynamic item) {
      if (item is! Map) return;
      final details = item['details'];
      if (details is Map) item['details'] = jsonEncode(details);
    }

    if (data is List) {
      for (final item in data) {
        fixOne(item);
      }
    } else {
      fixOne(data);
    }
  }

  /// 修补模型数据里可为 null 但 spec 标了必填的图片字段。
  static void _patchAvatarPayload(dynamic data) {
    void fixOne(dynamic item) {
      if (item is! Map) return;
      for (final key in const ['imageUrl', 'thumbnailImageUrl']) {
        if (item[key] == null) item[key] = '';
      }
    }

    if (data is List) {
      for (final item in data) {
        fixOne(item);
      }
    } else {
      fixOne(data);
    }
  }

  static VrcClient? _instance;

  static VrcClient get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('VrcClient 尚未初始化，请先 await VrcClient.create()');
    }
    return i;
  }

  static Future<VrcClient> create() async {
    if (_instance != null) return _instance!;

    final supportDir = await getApplicationSupportDirectory();
    final cookieDir = io.Directory('${supportDir.path}${io.Platform.pathSeparator}cookies');
    if (!cookieDir.existsSync()) {
      cookieDir.createSync(recursive: true);
    }

    final api = VrchatDart(
      // contactInfo 必须是真实可联系到你的地址，别留占位符。
      userAgent: const VrchatUserAgent(
        applicationName: AppInfo.applicationName,
        version: AppInfo.version,
        contactInfo: AppInfo.contactInfo,
      ),
      // PersistCookieJar 需要一个目录，authCookie 就存在这里。
      cookiePath: cookieDir.path,
    );

    // 超时放宽：默认 5 秒对国内直连 VRChat 太短了，登录必挂。
    api.rawApi.dio.options.connectTimeout = const Duration(seconds: 20);
    api.rawApi.dio.options.sendTimeout = const Duration(seconds: 20);
    api.rawApi.dio.options.receiveTimeout = const Duration(seconds: 30);

    // SDK 的 `NotificationV2DetailsBoop.inventoryItemId` 在 spec 里标了必填，
    // 但 VRChat 实际会返回 null，导致整条通知列表反序列化失败（通知页直接崩）。
    // 在 JSON 进入模型层之前把 null 补成空串，绕开这个问题。
    api.rawApi.dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          final path = response.requestOptions.path;
          if (path.contains('/notifications')) {
            _patchNotificationPayload(response.data);
          }
          // 「请求加入」类通知的 details spec 说 String，实际是 Map —— 转成
          // JSON 字符串，不然反序列化直接崩。
          if (path.contains('/requestInvite') || path.contains('/invite')) {
            _patchNotificationDetails(response.data);
          }
          // Avatar 的 imageUrl / thumbnailImageUrl 同样是「spec 必填、实际可为 null」
          // （自己上传但没设置图片的模型），补成空串让反序列化通过。
          if (path.contains('/avatars')) {
            _patchAvatarPayload(response.data);
          }
          handler.next(response);
        },
      ),
    );

    _instance = VrcClient._(api);
    return _instance!;
  }

  /// 自己持有的用户缓存。
  ///
  /// SDK 的 `api.auth.currentUser` 只有走它的 `login()` 才会被填充，
  /// 而那个方法在「无参恢复」时会带 `Basic base64("null:null")` 的坏头，
  /// 恢复会话永远失败。所以这里自己存一份，冷启动用 cookie 直读 `/auth/user`。
  CurrentUser? _cachedUser;

  CurrentUser? get currentUser => _cachedUser ?? api.auth.currentUser;

  /// 用本地已保存的 authCookie 恢复会话（直接读 `/auth/user`，绕开 SDK 的 login）。
  Future<bool> restoreSession() async {
    try {
      final resp = await api.rawApi.dio.get<dynamic>('/auth/user');
      final json = resp.data;
      if (json is Map && json['id'] != null) {
        _cachedUser = CurrentUser.fromJson(Map<String, dynamic>.from(json));
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('恢复会话失败: $e');
      return false;
    }
  }

  Future<LoginResult> login({required String username, required String password}) async {
    try {
      final (success, failure) = await api.auth.login(
        username: username,
        password: password,
      );
      if (failure != null) {
        return LoginResult.failed(_describeFailure(failure));
      }
      final data = success!.data;
      if (data.requiresTwoFactorAuth) {
        return LoginResult.needTwoFactor(data.twoFactorAuthTypes);
      }
      return const LoginResult.success();
    } catch (e) {
      return LoginResult.failed(_describeException(e));
    }
  }

  Future<LoginResult> verifyTwoFactor(String code) async {
    try {
      final (success, failure) = await api.auth.verify2fa(code.trim());
      if (failure != null) {
        return LoginResult.failed(_describeFailure(failure));
      }
      if (success == null || api.auth.currentUser == null) {
        return const LoginResult.failed('验证通过但未能取回账号信息，请重试');
      }
      _cachedUser = api.auth.currentUser;
      return const LoginResult.success();
    } catch (e) {
      return LoginResult.failed(_describeException(e));
    }
  }

  /// 清掉内存里的用户缓存（退出登录 / 切换账号时用）。
  void clearCachedUser() {
    _cachedUser = null;
  }

  Future<void> logout() async {
    try {
      await api.auth.logout();
    } catch (e) {
      debugPrint('登出时出错（忽略）: $e');
    }
  }

  void startPipeline() {
    try {
      api.streaming.start();
    } catch (e) {
      debugPrint('Pipeline 启动失败: $e');
    }
  }

  void stopPipeline() {
    try {
      api.streaming.stop();
    } catch (e) {
      debugPrint('Pipeline 停止失败: $e');
    }
  }

  String _describeFailure(Object failure) {
    final text = failure.toString();
    if (text.contains('401')) {
      return '用户名或密码不正确';
    }
    if (text.contains('429')) {
      return '请求太频繁，被 VRChat 限流了，等一分钟再试';
    }
    return text;
  }

  String _describeException(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '连接超时了，检查一下网络或代理，再试一次';
        case DioExceptionType.connectionError:
          return '连不上 VRChat，可能需要开代理';
        case DioExceptionType.badResponse:
          final code = e.response?.statusCode ?? 0;
          if (code == 401) return '账号或密码不对，或者登录已过期';
          if (code == 403) return '被 VRChat 拒绝了（403），稍后再试';
          if (code == 429) return '操作太频繁了，等一分钟再试';
          return '服务器返回错误（HTTP $code）';
        case DioExceptionType.cancel:
          return '请求被取消了';
        default:
          return '网络请求失败，稍后再试';
      }
    }

    final text = e.toString();
    final lower = text.toLowerCase();
    if (lower.contains('socketexception') || lower.contains('timeout')) {
      return '连不上 VRChat，检查一下网络（可能需要代理）';
    }
    // 兜底：只取第一行，别把整段堆栈甩给用户
    final firstLine = text.split('\n').first;
    return firstLine.length > 100
        ? '${firstLine.substring(0, 100)}…'
        : firstLine;
  }

  // -------------------------------------------------------------------------
  // 世界与用户详情
  // -------------------------------------------------------------------------

  final Map<String, String?> _worldNameCache = {};

  /// 世界名。带内存缓存 —— 好友列表里同一个世界会被反复问到，
  /// 不缓存的话很容易踩到 60 秒一次的频率红线。
  Future<String?> fetchWorldName(String worldId) async {
    if (_worldNameCache.containsKey(worldId)) return _worldNameCache[worldId];
    try {
      final resp = await api.rawApi.getWorldsApi().getWorld(worldId: worldId);
      final name = resp.data?.name;
      _worldNameCache[worldId] = name;
      return name;
    } catch (e) {
      debugPrint('取世界名失败 $worldId: $e');
      return null;
    }
  }

  /// 某实例当前人数（`n_users`）。只在详情页按需调用。
  Future<int?> fetchInstanceOccupants({
    required String worldId,
    required String instanceId,
  }) async {
    try {
      final resp = await api.rawApi
          .getInstancesApi()
          .getInstance(worldId: worldId, instanceId: instanceId);
      return resp.data?.nUsers;
    } catch (e) {
      debugPrint('取实例人数失败: $e');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // 自己的资料
  // -------------------------------------------------------------------------

  /// 改资料：简介 + 三种装饰都走这个接口。
  ///
  /// 注意状态语、代词、状态本身不在这里，`/profile` 只管资料页的内容。
  Future<String?> updateProfile({
    required String userId,
    String? bio,
    List<String>? bioLinks,
    String? profileEffect,
    String? nameplateEffect,
    String? iconFrame,
  }) async {
    try {
      final resp = await api.rawApi.getUsersApi().updateProfile(
        userId: userId,
        updateProfileRequest: UpdateProfileRequest(
          bio: bio,
          bioLinks: bioLinks,
          profileEffect: profileEffect,
          nameplateEffect: nameplateEffect,
          iconFrame: iconFrame,
        ),
      );
      if (resp.statusCode == 200) return null;
      return '保存失败（HTTP ${resp.statusCode}）';
    } on DioException catch (e) {
      return '保存失败：${_dioMessage(e)}';
    } catch (e) {
      return '保存失败：$e';
    }
  }

  /// 改状态语 / 代词。这两个走 `updateUser` 而不是 `/profile`。
  Future<String?> updateAbout({
    required String userId,
    String? statusDescription,
    String? pronouns,
    UserStatus? status,
  }) async {
    try {
      final resp = await api.rawApi.getUsersApi().updateUser(
        userId: userId,
        updateUserRequest: UpdateUserRequest(
          statusDescription: statusDescription,
          pronouns: pronouns,
          status: status,
        ),
      );
      if (resp.statusCode == 200) return null;
      return '保存失败（HTTP ${resp.statusCode}）';
    } on DioException catch (e) {
      return '保存失败：${_dioMessage(e)}';
    } catch (e) {
      return '保存失败：$e';
    }
  }

  /// 把某个世界设为家（进游戏的默认出生点）。
  Future<String?> setHomeWorld({
    required String userId,
    required String worldId,
  }) async {
    try {
      final resp = await api.rawApi.getUsersApi().updateUser(
        userId: userId,
        updateUserRequest: UpdateUserRequest(homeLocation: worldId),
      );
      if (resp.statusCode == 200) return null;
      return '设置失败（HTTP ${resp.statusCode}）';
    } catch (e) {
      return '设置失败：$e';
    }
  }

  /// 邀请自己进某个房间（电脑端在线时会收到邀请并生成房间）。
  Future<String?> inviteMyself({
    required String worldId,
    required String instanceId,
  }) async {
    try {
      // 用 dio 直发：SDK 的 SentNotification 模型解析会崩
      // （details spec 说对象，服务端实际返回 String）。
      final resp = await api.rawApi.dio.post<dynamic>(
        '/invite/myself/to/$worldId:$instanceId',
      );
      final code = resp.statusCode ?? 0;
      if (code >= 200 && code < 300) return null;
      return '邀请自己失败（HTTP $code）';
    } catch (e) {
      return '邀请自己失败：$e';
    }
  }

  /// 邀请好友进某个房间。
  Future<String?> inviteFriendToInstance({
    required String userId,
    required String instanceId,
  }) async {
    try {
      final resp = await api.rawApi.getInviteApi().inviteUser(
            userId: userId,
            inviteRequest: InviteRequest(instanceId: instanceId),
          );
      if (resp.statusCode == 200) return null;
      return '邀请失败（HTTP ${resp.statusCode}）';
    } catch (e) {
      return '邀请失败：$e';
    }
  }

  /// 切换当前模型。下次进房生效。
  Future<String?> selectAvatar(String avatarId) async {
    try {
      final resp =
          await api.rawApi.getAvatarsApi().selectAvatar(avatarId: avatarId);
      if (resp.statusCode == 200) return null;
      return '切换失败（HTTP ${resp.statusCode}）';
    } catch (e) {
      return '切换失败：$e';
    }
  }

  // -------------------------------------------------------------------------
  // 好友操作
  // -------------------------------------------------------------------------

  /// 戳一戳。不带 emoji 参数就用默认表情。
  Future<String?> boopUser(String userId) async {
    if (userId.isEmpty) return '不知道要戳谁（通知里没有发送者 ID）';
    try {
      // 直接发：SDK 的 boop 响应结构不标准（不是 Success），强转容易崩。
      final resp = await api.rawApi.dio.post<dynamic>(
        '/users/$userId/boop',
        data: <String, dynamic>{},
      );
      final code = resp.statusCode ?? 0;
      if (code >= 200 && code < 300) return null;
      if (code == 429) return '戳太频繁了，缓一下';
      if (code == 403) return '对方设置了不接收戳一戳';
      return '戳失败了（HTTP $code）';
    } catch (e) {
      return '戳失败：${_describeException(e)}';
    }
  }

  /// 给自己看的备注（`note`），只有本账号能看到。
  Future<String?> setUserNote(String userId, String note) async {
    try {
      final resp = await api.rawApi.getUsersApi().updateUserNote(
        updateUserNoteRequest: UpdateUserNoteRequest(
          note: note.trim(),
          targetUserId: userId,
        ),
      );
      if (resp.statusCode == 200) return null;
      return '备注没保存（HTTP ${resp.statusCode}）';
    } catch (e) {
      return '备注没保存：$e';
    }
  }

  /// 删好友。不可逆，调用前一定要二次确认。
  Future<String?> removeFriend(String userId) async {
    try {
      final resp = await api.rawApi.getFriendsApi().unfriend(userId: userId);
      if (resp.statusCode == 200) return null;
      return '删除失败（HTTP ${resp.statusCode}）';
    } catch (e) {
      return '删除失败：$e';
    }
  }

  /// 回戳（回复一条 boop 通知）。
  Future<String?> replyNotification(String notificationId) async {
    try {
      final resp = await api.rawApi.getNotificationsApi().replyNotificationV2(
        notificationId: notificationId,
        body: const <String, dynamic>{},
      );
      if (resp.statusCode == 200) return null;
      return '回戳失败（HTTP ${resp.statusCode}）';
    } catch (e) {
      final text = e.toString();
      if (text.contains('429')) return '太频繁了，缓一下';
      return '回戳失败：$text';
    }
  }

  // -------------------------------------------------------------------------
  // 收藏世界
  // -------------------------------------------------------------------------

  /// 收藏夹分组。VRChat 每种类型（世界/好友/模型）各有 4 个夹子，
  /// 名字可以自定义，默认叫 Group 1~4，内部名是 worlds1~worlds4。
  Future<List<FavoriteGroup>> fetchFavoriteGroups({FavoriteType type = FavoriteType.world}) async {
    final resp = await api.rawApi.getFavoritesApi().getFavoriteGroups(type: type);
    return resp.data ?? const [];
  }

  /// 已收藏的世界。
  ///
  /// 按收藏夹逐个拉，再合并去重。不传 tag 一次拉全的做法在多个夹子时
  /// 可能漏内容，所以这里宁可多打几次请求 —— 收藏夹最多 4 个。
  Future<List<FavoritedWorld>> fetchFavoritedWorlds() async {
    final out = <FavoritedWorld>[];
    final seen = <String>{};

    Future<void> pull({String? tag}) async {
      var offset = 0;
      const pageSize = 100;
      for (var page = 0; page < 4; page++) {
        final resp = await api.rawApi
            .getWorldsApi()
            .getFavoritedWorlds(n: pageSize, offset: offset, tag: tag);
        final batch = resp.data ?? const <FavoritedWorld>[];
        for (final w in batch) {
          // 同一个世界可以被收进多个夹子，id + favoriteId 一起判重。
          if (seen.add('${w.id}|${w.favoriteId}')) out.add(w);
        }
        if (batch.length < pageSize) break;
        offset += pageSize;
      }
    }

    List<String> groupNames;
    try {
      groupNames = (await fetchFavoriteGroups()).map((g) => g.name).toList();
    } catch (_) {
      groupNames = const [];
    }

    if (groupNames.isEmpty) {
      await pull();
      return out;
    }

    for (final name in groupNames) {
      try {
        await pull(tag: name);
      } catch (e) {
        // 某个夹子拉失败不该让整个列表空掉。
        debugPrint('拉收藏夹 $name 失败: $e');
      }
    }
    return out;
  }

  /// 收藏一个世界到指定收藏夹。返回 null 表示成功。
  Future<String?> addWorldFavorite(String worldId, {required String groupName}) async {
    try {
      final resp = await api.rawApi.getFavoritesApi().addFavorite(
        addFavoriteRequest: AddFavoriteRequest(
          favoriteId: worldId,
          tags: [groupName],
          type: FavoriteType.world,
        ),
      );
      if (resp.statusCode == 200) return null;
      return '收藏失败（HTTP ${resp.statusCode}）';
    } catch (e) {
      return _describeFavoriteError(e);
    }
  }

  /// 取消收藏。注意这里要传收藏记录的 id（`fvrt_xxx`），不是世界 id。
  Future<String?> removeWorldFavorite(String favoriteId) async {
    try {
      final resp = await api.rawApi.getFavoritesApi().removeFavorite(favoriteId: favoriteId);
      if (resp.statusCode == 200) return null;
      return '取消收藏失败（HTTP ${resp.statusCode}）';
    } catch (e) {
      return _describeFavoriteError(e);
    }
  }

  String _describeFavoriteError(Object e) {
    final text = e.toString();
    if (text.contains('403')) return '没有权限，或者收藏夹已满';
    if (text.contains('429')) return '操作太频繁，缓一下';
    return '操作失败：$text';
  }

  // -------------------------------------------------------------------------
  // 处理通知（好友请求等）
  // -------------------------------------------------------------------------

  /// 回应一条 V2 通知。
  ///
  /// 好友请求的「接受 / 拒绝」就是走这里：通知对象里带着 `responses`，
  /// 每个选项有 type 和 data，原样回传即可 —— 不要在本地硬编码 accept/reject。
  /// 拉相册文件（tag: gallery / icon / print）。
  /// 拉拍立得列表（独立实体，删除的不会回来）。
  /// diag 是给界面上临时诊断用的（状态码 / 返回类型 / 条数）。
  Future<({List<Map<String, dynamic>> files, String diag})> fetchPrints(
    String userId,
  ) async {
    try {
      final resp = await api.rawApi.dio.get<dynamic>(
        '/prints/user/$userId',
        queryParameters: {'n': 100},
      );
      final code = resp.statusCode ?? 0;
      final data = resp.data;
      var diag = 'HTTP $code · type=${data.runtimeType}';

      var files = <Map<String, dynamic>>[];
      if (data is List) {
        diag += ' · n=${data.length}';
        files = [
          for (final e in data)
            if (e is Map) Map<String, dynamic>.from(e),
        ];
      } else if (data is Map) {
        diag += ' · keys=${data.keys.take(6).toList()}';
        final list = data['prints'];
        if (list is List) {
          diag += ' · prints=${list.length}';
          files = [
            for (final e in list)
              if (e is Map) Map<String, dynamic>.from(e),
          ];
        }
      } else if (data is String) {
        diag += ' · body=${data.length > 100 ? data.substring(0, 100) : data}';
      }
      return (files: files, diag: diag);
    } catch (e) {
      return (
        files: const <Map<String, dynamic>>[],
        diag: 'EXC: ${_describeException(e)}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchFilesByTag(String tag) async {
    try {
      final resp = await api.rawApi.dio.get<dynamic>(
        '/files',
        queryParameters: {'tag': tag, 'n': 100},
      );
      final data = resp.data;
      if (data is List) {
        return [
          for (final e in data)
            if (e is Map) Map<String, dynamic>.from(e),
        ];
      }
    } catch (e) {
      debugPrint('拉相册失败($tag): $e');
    }
    return const [];
  }

  /// 删除一个图库条目。
  /// 相册/头像/表情/贴纸走 `DELETE /files/{id}`，拍立得走 `DELETE /prints/{id}`。
  /// 返回 null 表示成功。
  Future<String?> deleteAlbumEntry({required String tag, required String id}) async {
    try {
      final path = tag == 'print' ? '/prints/$id' : '/files/$id';
      final resp = await api.rawApi.dio.delete<dynamic>(path);
      final code = resp.statusCode ?? 0;
      if (code >= 200 && code < 300) return null;
      return '删除失败（HTTP $code）';
    } catch (e) {
      return '删除失败：${_describeException(e)}';
    }
  }

  /// 上传一张图到 VRC+ 图库（tag: gallery / print / icon / emoji / sticker）。
  ///
  /// VRCX 的做法（`Dotnet/WebApi.cs` 的 BuildImageUploadRequest）：
  /// **一次** `POST /file/image` 的 multipart 表单 —— `file` 字段放 PNG 字节，
  /// `tag` 等放在文本字段。服务端一步生成所有尺寸。
  /// icon / emoji / sticker 必须是方形图，上传前居中裁切。
  /// 返回 null 表示成功。
  Future<String?> uploadAlbumImage({
    required String path,
    required String tag,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    try {
      final bytes = await io.File(path).readAsBytes();
      var payload = bytes;

      // VRChat 要求图片 ≥64x64，不满足直接拦下（省得吃 400）
      final probe = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
      );
      final probeFrame = await probe.getNextFrame();
      final w = probeFrame.image.width;
      final h = probeFrame.image.height;
      probeFrame.image.dispose();
      if (w < 64 || h < 64) {
        return '图片太小（${w}x$h），VRChat 要求至少 64x64';
      }

      // icon / emoji / sticker 要方形（服务端只收方图）
      if (tag == 'icon' || tag == 'emoji' || tag == 'sticker') {
        payload = await _centerCropSquare(bytes);
      }

      final form = FormData();
      form.fields.add(MapEntry('tag', tag));
      if (tag == 'emoji') {
        // 表情需要动画参数（默认：静止图、线性播放）
        form.fields
          ..add(const MapEntry('animationStyle', 'stop'))
          ..add(const MapEntry('loopStyle', 'linear'));
      }
      form.files.add(
        MapEntry(
          'file',
          MultipartFile.fromBytes(
            payload,
            filename: 'blob',
            contentType: MediaType('image', 'png'),
          ),
        ),
      );

      final resp = await api.rawApi.dio.post<dynamic>(
        '/file/image',
        data: form,
        onSendProgress: onSendProgress,
      );
      final code = resp.statusCode ?? 0;
      if (code >= 200 && code < 300) return null;
      // TODO(白花花, 明天): 实测仍有 HTTP 400。排查方向：
      // 1. emoji 的 animationStyle/loopStyle 合法枚举值（当前 stop/linear 是猜的）
      // 2. sticker 可能需要 stickerId（VRCX 是对已有贴纸替换）
      // 3. 某些分类对尺寸/大小的限制
      // 排查手法：把 400 的响应体读出来（error message 会写原因），别只看状态码
      return '上传失败（HTTP $code）';
    } catch (e) {
      return '上传失败：${_describeException(e)}';
    }
  }

  /// 居中裁成方形并转 PNG（dart:ui 画布实现，不引第三方图像库）。
  Future<Uint8List> _centerCropSquare(List<int> rawBytes) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(rawBytes));
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final side = image.width < image.height ? image.width : image.height;
    final ox = (image.width - side) / 2;
    final oy = (image.height - side) / 2;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(ox, oy, side.toDouble(), side.toDouble()),
      ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(side, side);
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// 取世界资产的体积（对 assetUrl 发 HEAD，读 Content-Length）。
  ///
  /// VRChat 的 API 不直接给世界大小，网站上的 Size 就是这么算的。
  Future<double?> fetchAssetSizeMb(String url) async {
    if (url.isEmpty) return null;
    try {
      final resp = await api.rawApi.dio.head<dynamic>(
        url,
        options: Options(followRedirects: true, validateStatus: (_) => true),
      );
      final raw = resp.headers.value('content-length');
      final bytes = int.tryParse(raw ?? '');
      if (bytes == null || bytes <= 0) return null;
      return bytes / (1024 * 1024);
    } catch (e) {
      debugPrint('取世界大小失败: $e');
      return null;
    }
  }

  /// 查某个具体实例（含成员列表）。
  ///
  /// 公开实例能从 `/worlds/{id}` 的 instances 里读，但邀请指向的私有实例读不到，
  /// 只能按 location 单独查：`GET /instances/{worldId}:{instanceId}`。
  Future<Map<String, dynamic>?> fetchInstance(
    String worldId,
    String instanceId,
  ) async {
    try {
      final resp = await api.rawApi.dio.get<dynamic>(
        '/instances/$worldId:$instanceId',
      );
      final d = resp.data;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (e) {
      debugPrint('取实例失败: $e');
    }
    return null;
  }

  /// 回复邀请（官方接口 `POST /invite/{id}/response`）。
  ///
  /// VRChat 的快捷回复是**客户端内置的 12 条固定文案**，API 只传槽位索引
  /// （0~11），自由文本是不行的。`rsvp: true` 表示「不加入，只回复」。
  Future<String?> replyInvite(String inviteId, int responseSlot) async {
    try {
      final resp = await api.rawApi.dio.post<dynamic>(
        '/invite/$inviteId/response',
        data: {
          'responseSlot': responseSlot,
          'rsvp': true,
        },
      );
      final code = resp.statusCode ?? 0;
      if (code >= 200 && code < 300) return null;
      return '回复失败（HTTP $code）';
    } catch (e) {
      return '回复失败：${_describeException(e)}';
    }
  }

  /// 隐藏（忽略）一条通知。
  ///
  /// VRChat 有两套通知端点，隐藏接口也不一样，两个都试一遍：
  /// - 新版：`DELETE /notifications/{id}`
  /// - 旧版：`PUT /auth/user/notifications/{id}/hide`
  Future<String?> hideNotification(String notificationId) async {
    final attempts = <(String, String)>[
      ('DELETE', '/notifications/$notificationId'),
      ('PUT', '/auth/user/notifications/$notificationId/hide'),
    ];
    String? lastErr;
    for (final (method, path) in attempts) {
      try {
        final resp = method == 'DELETE'
            ? await api.rawApi.dio.delete<dynamic>(path)
            : await api.rawApi.dio.put<dynamic>(path);
        final code = resp.statusCode ?? 0;
        if (code >= 200 && code < 300) return null;
        lastErr = 'HTTP $code';
      } catch (e) {
        lastErr = _describeException(e);
      }
    }
    return '忽略失败：$lastErr';
  }

  /// 接受好友申请。专用接口 `/auth/user/notifications/{id}/accept`，
  /// 比通用的 respond 更可靠（好友申请在 VRChat 里是独立的动作）。
  Future<String?> acceptFriendRequest(String notificationId) async {
    try {
      final resp = await api.rawApi.dio.put<dynamic>(
        '/auth/user/notifications/$notificationId/accept',
      );
      final code = resp.statusCode ?? 0;
      if (code >= 200 && code < 300) return null;
      return '接受失败（HTTP $code）';
    } catch (e) {
      return '接受失败：${_describeException(e)}';
    }
  }

  Future<String?> respondNotification({
    required String notificationId,
    required String responseType,
    String responseData = '',
  }) async {
    try {
      final resp = await api.rawApi.getNotificationsApi().respondNotificationV2(
        notificationId: notificationId,
        respondNotificationV2Request: RespondNotificationV2Request(
          responseType: responseType,
          responseData: responseData,
        ),
      );
      if (resp.statusCode == 200) return null;
      return '处理失败（HTTP ${resp.statusCode}）';
    } catch (e) {
      final text = e.toString();
      if (text.contains('429')) return '操作太频繁，缓一下';
      return '处理失败：$text';
    }
  }

  // -------------------------------------------------------------------------
  // 邀请
  // -------------------------------------------------------------------------

  /// 我当前所在的实例（`wrld_xxx:12345~region(us)`），不在世界里时为 null。
  ///
  /// **不要用 `restoreSession()` 刷新**：它的无参 `login()` 会带上
  /// `Basic base64("null:null")` 的坏认证头，请求失败被吞，数据永远不更新。
  /// 直接调 `getCurrentUser`（走 cookie 认证）拿最新值。
  Future<String?> myCurrentInstance() async {
    try {
      final resp = await api.rawApi.dio.get<dynamic>('/auth/user');
      final json = resp.data;
      if (json is Map) {
        final loc = json['location']?.toString();
        if (loc != null && loc.startsWith('wrld_')) return loc;
      }
    } catch (_) {
      // 拉新失败就用旧快照兜底
    }
    final loc = api.auth.currentUser?.location;
    if (loc == null || !loc.startsWith('wrld_')) return null;
    return loc;
  }

  /// 邀请好友来我所在的房间。
  ///
  /// 房间位置优先从 `presence` 拿（账号级：`presence.world` + `presence.instance`），
  /// 拿不到再退回会话级 location。
  Future<String?> inviteFriendToMe(String userId) async {
    String? instance;
    try {
      final resp = await api.rawApi.dio.get<dynamic>('/auth/user');
      final json = resp.data;
      if (json is Map) {
        final presence = json['presence'];
        if (presence is Map) {
          final world = (presence['world'] ?? '').toString();
          final inst = (presence['instance'] ?? '').toString();
          if (world.startsWith('wrld_') && inst.isNotEmpty) {
            // instance 可能已经带 worldId 前缀，也可能只有 `12345~region(jp)`
            instance = inst.contains(':') ? inst : '$world:$inst';
          }
        }
      }
    } catch (_) {
      // 忽略，走下面的兜底
    }
    instance ??= await myCurrentInstance();
    if (instance == null) {
      // API 会话拿不到电脑端游戏里的位置，这是 VRChat 的限制。
      return '读不到你电脑端的房间位置，请用世界页「新建房间」发邀请';
    }
    try {
      // 同样绕开 SDK 的 SentNotification 解析。
      final resp = await api.rawApi.dio.post<dynamic>(
        '/invite/$userId',
        data: {'instanceId': instance},
      );
      final code = resp.statusCode ?? 0;
      if (code >= 200 && code < 300) return null;
      return '邀请没发出去（HTTP $code）';
    } catch (e) {
      return _describeInviteError(e);
    }
  }

  /// 请求对方邀请我进他的房间。
  Future<String?> requestInviteFrom(String userId) async {
    try {
      final resp = await api.rawApi.getInviteApi().requestInvite(
        userId: userId,
        requestInviteRequest: RequestInviteRequest(),
      );
      if (resp.statusCode == 200) return null;
      return '请求没发出去（HTTP ${resp.statusCode}）';
    } catch (e) {
      return _describeInviteError(e);
    }
  }

  String _describeInviteError(Object e) {
    final text = e.toString();
    if (text.contains('403')) return '对方设置了不接收邀请，或者你们不是好友';
    if (text.contains('404')) return '找不到这个人';
    if (text.contains('429')) return '操作太频繁，缓一下再试';
    return '操作失败：$text';
  }

  /// 某个世界当前的公开实例。
  ///
  /// VRChat 没有「按世界查实例」的接口，只提供全局活跃实例列表
  /// （`/instances/active`），所以只能拉回来再筛。
  /// 热门世界通常能查到几个，冷门世界可能一个都没有 —— 那是接口的锅。
  Future<List<Instance>> fetchActiveInstancesFor(String worldId) async {
    final out = <Instance>[];
    var offset = 0;
    const pageSize = 100;
    for (var page = 0; page < 5; page++) {
      final resp = await api.rawApi
          .getInstancesApi()
          .getActiveInstances(n: pageSize, offset: offset);
      final batch = resp.data ?? const <Instance>[];
      out.addAll(batch.where((i) => i.worldId == worldId));
      if (batch.length < pageSize) break;
      offset += pageSize;
    }
    out.sort((a, b) => b.nUsers.compareTo(a.nUsers));
    return out;
  }

  /// 用户详情：`/users/{id}` + `/profile/{id}` 两路合起来用。
  /// 前者给加入时间、最后活动、所在位置；后者给 bio、徽章、代表模型。
  Future<UserDetail> fetchUserDetail(String userId) async {    final users = api.rawApi.getUsersApi();

    UserResponse? profileBase;
    PublicProfile? profile;
    Object? firstError;

    try {
      final resp = await users.getUser(userId: userId);
      profileBase = resp.data;
    } catch (e) {
      firstError = e;
    }

    try {
      final resp = await users.getPublicProfile(userId: userId);
      profile = resp.data;
    } catch (e) {
      firstError ??= e;
    }

    if (profileBase == null && profile == null) {
      throw Exception(firstError?.toString() ?? '取用户资料失败');
    }
    return UserDetail(base: profileBase, profile: profile);
  }

  /// 资料背景（`/profile/{id}` 的 background* 字段，SDK 还没生成模型）。
  Future<ProfileBackground> fetchProfileBackground(String userId) async {
    try {
      final resp = await api.rawApi.dio.get<dynamic>('/profile/$userId');
      final data = resp.data;
      if (data is Map) {
        return ProfileBackground.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {
      // 拿不到就当默认背景，不影响资料页其它内容。
    }
    return const ProfileBackground();
  }

  /// 改资料背景。
  ///
  /// [type] 取 `default` / `gradient` / `texture` / `inventory`。
  /// 渐变颜色是 6 位十六进制、不带 `#`。
  Future<String?> updateProfileBackground({
    required String userId,
    required String type,
    String gradientTop = '',
    String gradientBottom = '',
    String textureId = '',
  }) async {
    try {
      // 只发需要的字段：空字符串会被接口当成非法值（400）。
      final payload = <String, dynamic>{
        'backgroundType': type,
        if (textureId.isNotEmpty) 'backgroundTextureId': textureId,
        if (gradientTop.isNotEmpty) 'backgroundGradientTop': gradientTop,
        if (gradientBottom.isNotEmpty) 'backgroundGradientBottom': gradientBottom,
      };
      final resp = await api.rawApi.dio.put<dynamic>(
        '/profile/$userId',
        data: payload,
      );
      if (resp.statusCode == 200) return null;
      return '保存失败（HTTP ${resp.statusCode}）';
    } on DioException catch (e) {
      return '保存失败：${_dioMessage(e)}';
    } catch (e) {
      return '保存失败：$e';
    }
  }

  /// 库存（`/inventory`）。
  Future<InventoryResult> fetchInventory({
    int n = 60,
    int offset = 0,
    String? type,
    bool? archived,
    String order = 'newest',
  }) async {
    final resp = await api.rawApi.dio.get<dynamic>(
      '/inventory',
      queryParameters: {
        'n': n,
        'offset': offset,
        'order': order,
        'types': ?type,
        'archived': ?archived,
      },
    );
    final data = resp.data;
    if (data is! Map) return const InventoryResult(items: [], totalCount: null);
    final raw = data['data'];
    final items = <InventoryItem>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          items.add(InventoryItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final total = data['totalCount'];
    return InventoryResult(
      items: items,
      totalCount: total is num ? total.toInt() : null,
    );
  }

  /// VRChat Credits 余额。
  Future<int?> fetchCreditsBalance(String userId) async {
    try {
      final resp = await api.rawApi.dio.get<dynamic>(
        '/user/$userId/economy/balance',
      );
      final data = resp.data;
      if (data is Map && data['balance'] is num) {
        return (data['balance'] as num).toInt();
      }
    } catch (_) {
      // 余额拿不到就不显示
    }
    return null;
  }

  /// 屏蔽 / 禁言记录（`/auth/user/playermoderations`）。
  Future<List<PlayerModerationRecord>> fetchPlayerModerations() async {
    try {
      final resp = await api.rawApi.dio.get<dynamic>(
        '/auth/user/playermoderations',
      );
      final data = resp.data;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map(
            (e) => PlayerModerationRecord.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .where((e) => e.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 解除一条屏蔽 / 禁言（删除那条 moderation 记录）。
  Future<String?> deletePlayerModeration(String id) async {
    try {
      final resp = await api.rawApi.dio.delete<dynamic>(
        '/auth/user/playermoderations/$id',
      );
      if (resp.statusCode == 200 || resp.statusCode == 204) return null;
      return '解除失败（HTTP ${resp.statusCode}）';
    } on DioException catch (e) {
      return '解除失败：${_dioMessage(e)}';
    } catch (e) {
      return '解除失败：$e';
    }
  }

  /// 从 VRChat 的错误响应里挖出真正的原因，别把整段 DioException 丢给用户。
  String _dioMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      if (data['message'] != null) return data['message'].toString();
    }
    final status = e.response?.statusCode;
    if (data is String && data.trim().isNotEmpty) return data.trim();
    return status == null ? (e.message ?? '网络异常') : 'HTTP $status';
  }
}

/// 一页库存。
class InventoryResult {
  const InventoryResult({required this.items, required this.totalCount});

  final List<InventoryItem> items;
  final int? totalCount;
}

/// 库存里的一件物品（表情、贴纸、道具、皮肤……）。
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.itemType,
    required this.itemTypeLabel,
    required this.isArchived,
    required this.expiryDate,
  });

  final String id;
  final String name;
  final String description;
  final String? imageUrl;
  final String itemType;
  final String itemTypeLabel;
  final bool isArchived;
  final String? expiryDate;

  static InventoryItem fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    final metaImage = metadata is Map ? metadata['imageUrl']?.toString() : null;
    final image = json['imageUrl']?.toString();
    final expiry = json['expiryDate']?.toString();

    return InventoryItem(
      id: json['id']?.toString() ?? '',
      name: (json['name']?.toString() ?? '').trim(),
      description: (json['description']?.toString() ?? '').trim(),
      imageUrl: (image != null && image.isNotEmpty) ? image : metaImage,
      itemType: json['itemType']?.toString() ?? '',
      itemTypeLabel: json['itemTypeLabel']?.toString() ?? '',
      isArchived: json['isArchived'] == true,
      expiryDate: (expiry == null || expiry.isEmpty) ? null : expiry,
    );
  }

  String get typeLabel {
    if (itemTypeLabel.isNotEmpty) return itemTypeLabel;
    return switch (itemType) {
      'bundle' => '礼包',
      'droneskin' => '无人机皮肤',
      'emoji' => '表情',
      'portalskin' => '传送门皮肤',
      'prop' => '道具',
      'sticker' => '贴纸',
      'warpeffect' => '传送特效',
      _ => itemType,
    };
  }
}

/// 一条屏蔽 / 禁言记录。
///
/// 名字和 SDK 里的 `PlayerModeration` 区分开，避免 import 冲突。
class PlayerModerationRecord {
  const PlayerModerationRecord({
    required this.id,
    required this.type,
    required this.sourceDisplayName,
    required this.targetDisplayName,
    required this.created,
  });

  final String id;

  /// block / mute / muteChat / unmute / unmuteChat / hideAvatar …
  final String type;
  final String sourceDisplayName;
  final String targetDisplayName;
  final DateTime? created;

  bool get isBlock => type == 'block';

  String get label => switch (type) {
    'block' => '屏蔽',
    'unblock' => '解除屏蔽',
    'mute' => '禁言',
    'unmute' => '解除禁言',
    'muteChat' => '禁言',
    'unmuteChat' => '解除禁言',
    'hideAvatar' => '隐藏模型',
    'showAvatar' => '显示模型',
    'interactOff' => '关闭交互',
    'interactOn' => '开启交互',
    _ => type,
  };

  static PlayerModerationRecord fromJson(Map<String, dynamic> json) {
    return PlayerModerationRecord(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      sourceDisplayName: json['sourceDisplayName']?.toString() ?? '',
      targetDisplayName: json['targetDisplayName']?.toString() ?? '',
      created: DateTime.tryParse(json['created']?.toString() ?? ''),
    );
  }
}

/// 资料页背景。
///
/// VRChat 2026 年给资料页加了背景装饰：渐变（两个色值）、自定义贴图，
/// 或者 VRC+ 的预设模板。预设的模板 ID 是对外不公开的，App 里只能原样展示
/// 渐变和贴图，遇到预设就退回页面底色。
class ProfileBackground {
  const ProfileBackground({
    this.type = 'default',
    this.templateId = '',
    this.textureId = '',
    this.gradientTop = '',
    this.gradientBottom = '',
  });

  final String type;
  final String templateId;
  final String textureId;
  final String gradientTop;
  final String gradientBottom;

  bool get isGradient =>
      type == 'gradient' && topColor != null && bottomColor != null;

  bool get isTexture => type == 'texture' && textureUrl != null;

  /// 预设模板背景（VRC+ 那些）。
  bool get isPreset => type != 'default' && !isGradient && !isTexture;

  /// 当前背景对应的预设（`backgroundTextureId` 就是预设 ID）。
  ProfileBackgroundPreset? get preset => profileBackgroundPreset(textureId);

  Color? get topColor => _parseHex(gradientTop);
  Color? get bottomColor => _parseHex(gradientBottom);

  /// 预设背景直接拿官方素材；自传贴图才走文件接口。
  String? get textureUrl {
    if (type != 'texture' || textureId.isEmpty) return null;
    final found = profileBackgroundPreset(textureId);
    if (found != null) return found.imageUrl;
    if (textureId.startsWith('file_')) {
      return 'https://api.vrchat.cloud/api/1/file/$textureId/1/file';
    }
    return null;
  }

  static Color? _parseHex(String value) {
    final hex = value.replaceAll('#', '').trim();
    if (hex.length != 6) return null;
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  static ProfileBackground fromJson(Map<String, dynamic> json) {
    return ProfileBackground(
      type: json['backgroundType']?.toString() ?? 'default',
      templateId: json['backgroundTemplateId']?.toString() ?? '',
      textureId: json['backgroundTextureId']?.toString() ?? '',
      gradientTop: json['backgroundGradientTop']?.toString() ?? '',
      gradientBottom: json['backgroundGradientBottom']?.toString() ?? '',
    );
  }
}

/// 用户详情聚合。
///
/// `/profile/{id}` 的信息比想象中全：VRC+、18+、语言、徽章、公开世界、群组都在里面，
/// 所以个人资料页基本一次请求就够。
class UserDetail {
  const UserDetail({this.base, this.profile});

  final UserResponse? base;
  final PublicProfile? profile;

  String get displayName => profile?.displayName ?? base?.displayName ?? '';

  String? get bio => profile?.bio;
  List<String> get bioLinks => profile?.bioLinks ?? const [];

  String? get bannerUrl => profile?.bannerUrl;
  String? get bannerColor => profile?.bannerColor;

  bool get hasVrcPlus => profile?.hasVrcPlus ?? false;
  bool get ageVerified => profile?.ageVerified ?? base?.ageVerified ?? false;

  String get pronouns => profile?.pronouns ?? base?.pronouns ?? '';
  List<String> get languages => profile?.languages ?? const [];

  List<Badge> get badges => profile?.badges ?? const [];

  List<LimitedWorld> get publicWorlds => profile?.publicWorlds ?? const [];
  int get publicWorldCount =>
      profile?.totalPublicWorldsCount ?? publicWorlds.length;

  List<ProfileGroup> get groups => profile?.groups?.list ?? const [];
  int get groupCount => profile?.groups?.count ?? groups.length;

  /// 信任等级用的原始 tag。
  List<String> get trustTags => profile?.trustTags ?? base?.tags ?? const [];

  String? get avatarName => profile?.currentAvatarName;
  String? get avatarAuthorName => profile?.currentAvatarAuthorName;
  /// **当前模型**的图。MY AVATAR 那块要用它，别混进自定义头像。
  String? get avatarImageUrl =>
      profile?.currentAvatarImageUrl ?? base?.currentAvatarImageUrl;
  String? get avatarThumbnailUrl => profile?.currentAvatarThumbnailImageUrl;

  /// 当前模型的 id（名字拿不到时用它去查）。
  String? get currentAvatarId => profile?.currentAvatar ?? base?.currentAvatar;

  /// 用户自己设的头像。
  ///
  /// VRChat 官网上头像位置的优先级是：自定义头像（VRC+）> 当前模型缩略图。
  /// 这里 data 里没有 `profilePicOverride` 字段（spec 只在注释里提到），
  /// 所以退一步用 `userIcon` / `iconUrl` —— 这两个是用户图标，
  /// 比模型缩略图更接近「用户头像」的语义。
  String? get userIcon => profile?.userIcon;
  String? get iconUrl => profile?.iconUrl ?? base?.iconUrl;

  DateTime? get dateJoined => base?.dateJoined;
  bool get isFriend => base?.isFriend ?? false;
  String? get location => base?.location;
  String? get platform => base?.platform;
  String? get statusDescription => profile?.statusDescription ?? base?.statusDescription;

  /// 当前状态（官网 profile 里也带了一份）。
  UserStatus? get status => profile?.status;

  /// 自己给这人写的备注（只有本账号可见）。
  String? get note => base?.note;

  /// 装扮 id。拿去 `cosmeticsProvider` 里回查资源。
  String? get profileEffectId => profile?.profileEffect;
  String? get nameplateEffectId => profile?.nameplateEffect;
  String? get iconFrameId => profile?.iconFrame;
}

