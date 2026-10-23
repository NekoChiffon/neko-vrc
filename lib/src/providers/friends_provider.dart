import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../core/location_parser.dart';
import '../core/vrc_client.dart';
import '../models/friend_presence.dart';
import '../services/friend_notifier.dart';
import '../services/presence_tracker.dart';
import 'discovery_provider.dart';
import 'saved_account.dart';

/// 在 main() 里用 overrideWithValue 注入真实实例。
final vrcClientProvider = Provider<VrcClient>(
  (ref) => throw StateError('vrcClientProvider 必须在 ProviderScope 里被覆盖'),
);

/// 请求 VRChat 图片 CDN 时必须带上的请求头。
///
/// 裸的 `CachedNetworkImage` 发的是 `Dart/3.x (dart:io)`，
/// VRChat 会直接拒掉；必须换成自己的 User-Agent。
final imageHeadersProvider = Provider<Map<String, String>>((ref) {
  final client = ref.watch(vrcClientProvider);
  return {'User-Agent': client.api.userAgent.toString()};
});

// ---------------------------------------------------------------------------
// 登录状态
// ---------------------------------------------------------------------------

sealed class AuthState {
  const AuthState();
}

/// 启动中，还没判断出登录没登录。
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut([this.message]);
  final String? message;
}

class AuthAwaitingTwoFactor extends AuthState {
  const AuthAwaitingTwoFactor(this.types);
  final List<TwoFactorAuthType> types;

  String get hint => switch (types) {
    [TwoFactorAuthType.totp, ...] => '打开你的验证器 App，输入 6 位动态码',
    [TwoFactorAuthType.emailOtp, ...] => '验证码已发到你的邮箱',
    [TwoFactorAuthType.otp, ...] => '输入你的恢复码',
    _ => '输入两步验证码',
  };
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);
  final CurrentUser user;
}

class AuthController extends Notifier<AuthState> {
  /// 登录过程中临时记住凭据，2FA 通过后要再登录一次落到 cookie 里。
  String? _pendingUsername;
  String? _pendingPassword;

  @override
  AuthState build() => const AuthUnknown();

  Future<void> bootstrap() async {
    final client = ref.read(vrcClientProvider);
    final restored = await client.restoreSession();
    final user = client.currentUser;
    state = restored && user != null ? AuthSignedIn(user) : const AuthSignedOut();
  }

  /// 返回 null 表示成功，否则是给用户看的错误文案。
  Future<String?> signIn(String username, String password) async {
    final client = ref.read(vrcClientProvider);
    final result = await client.login(username: username, password: password);

    switch (result.status) {
      case LoginStatus.success:
        _pendingUsername = null;
        _pendingPassword = null;
        final user = client.currentUser;
        if (user == null) return '登录成功但取不到账号信息';
        state = AuthSignedIn(user);
        ref.read(welcomePendingProvider.notifier).state = true;
        final avatar = _avatarOf(user);
        ref.read(savedAccountProvider.notifier).save(
              userId: user.id,
              displayName: user.displayName,
              avatarUrl: avatar,
              username: username,
            );
        ref.read(savedAccountsProvider.notifier).upsert(
              SavedAccount(
                userId: user.id,
                displayName: user.displayName,
                avatarUrl: avatar,
                savedAt: DateTime.now().toIso8601String(),
                username: username,
              ),
            );
        return null;
      case LoginStatus.needTwoFactor:
        _pendingUsername = username;
        _pendingPassword = password;
        state = AuthAwaitingTwoFactor(result.twoFactorTypes);
        return null;
      case LoginStatus.failed:
        return result.message ?? '登录失败';
    }
  }

  Future<String?> submitTwoFactor(String code) async {
    final client = ref.read(vrcClientProvider);
    final result = await client.verifyTwoFactor(code);
    if (result.status == LoginStatus.failed) {
      return result.message ?? '验证失败';
    }
    final user = client.currentUser;
    if (user == null) {
      // cookie 里没拿到用户，退回用密码再登一次。
      final u = _pendingUsername;
      final p = _pendingPassword;
      if (u != null && p != null) {
        return signIn(u, p);
      }
      return '验证通过但取不到账号信息';
    }
    final pendingUsername = _pendingUsername ?? '';
    _pendingUsername = null;
    _pendingPassword = null;
    state = AuthSignedIn(user);
    ref.read(welcomePendingProvider.notifier).state = true;
    ref.read(savedAccountsProvider.notifier).upsert(
          SavedAccount(
            userId: user.id,
            displayName: user.displayName,
            avatarUrl: _avatarOf(user),
            savedAt: DateTime.now().toIso8601String(),
            username: pendingUsername,
          ),
        );
    return null;
  }

  void cancelTwoFactor() {
    _pendingUsername = null;
    _pendingPassword = null;
    state = const AuthSignedOut();
  }

  /// 重新拉自己的资料。location / status 会随 PC 端变化，登录快照会过期。
  ///
  /// 走 `getCurrentUser`（cookie 认证）。**不要**走 bootstrap —— 它内部的
  /// 无参 `login()` 会带坏认证头，刷新永远失败且被静默吞掉。
  Future<void> refreshMe() async {
    try {
      // /auth/user 就是登录后同款数据源，返回结构直接喂 CurrentUser.fromJson
      final resp = await ref
          .read(vrcClientProvider)
          .api
          .rawApi
          .dio
          .get<dynamic>('/auth/user');
      final json = resp.data;
      if (json is Map && json['id'] != null) {
        final user = CurrentUser.fromJson(
          Map<String, dynamic>.from(json),
        );
        state = AuthSignedIn(user);
      }
    } catch (_) {
      // 刷新失败保持旧数据
    }
  }

  /// 改自己的状态和状态语。返回 null 表示成功。
  ///
  /// 这是手机上最常用的一步：人已经躺下了，想让好友知道「我在」或者
  /// 「别来找我」。
  Future<String?> updateStatus(UserStatus status, String description) async {
    final client = ref.read(vrcClientProvider);
    final user = client.currentUser;
    if (user == null) return '还没有登录';

    try {
      final resp = await client.api.rawApi.getUsersApi().updateUser(
        userId: user.id,
        updateUserRequest: UpdateUserRequest(
          status: status,
          statusDescription: description.trim(),
        ),
      );
      final updated = resp.data;
      if (updated != null) {
        state = AuthSignedIn(updated);
      } else {
        // 服务端没回内容时，重新拉一次会话把 currentUser 刷新掉。
        await bootstrap();
      }
      return null;
    } catch (e) {
      final text = e.toString();
      if (text.contains('429')) return '改太频繁了，等一会儿再试';
      return '改状态失败：$text';
    }
  }

  /// 头像：自定义资料头像（VRC+）优先，其次模型缩略图。
  String _avatarOf(dynamic user) {
    final icon = (user.iconUrl ?? '').toString();
    if (icon.isNotEmpty) return icon;
    final thumb = (user.currentAvatarThumbnailImageUrl ?? '').toString();
    if (thumb.isNotEmpty) return thumb;
    return (user.currentAvatarImageUrl ?? '').toString();
  }

  Future<void> signOut() async {
    ref.read(vrcClientProvider).stopPipeline();
    await ref.read(vrcClientProvider).logout();
    ref.read(vrcClientProvider).clearCachedUser();
    ref.invalidate(friendsProvider);
    state = const AuthSignedOut();
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// 刚刚「主动登录」成功（不是冷启动恢复会话）——用来播一次欢迎动画。
final welcomePendingProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// 好友
// ---------------------------------------------------------------------------

class FriendsState {
  const FriendsState({
    this.loading = false,
    this.error,
    this.friends = const [],
    this.lastSyncedAt,
    this.lastEventAt,
  });

  final bool loading;
  final String? error;
  final List<FriendPresence> friends;
  final DateTime? lastSyncedAt;

  /// 最近一次收到 Pipeline 推送的时间，用来判断实时通道还活着没有。
  final DateTime? lastEventAt;

  int get onlineCount => friends.where((f) => f.isOnline).length;

  /// 10 分钟内有过推送就认为通道正常。
  bool get pipelineAlive {
    final at = lastEventAt;
    if (at == null) return false;
    return DateTime.now().difference(at).inMinutes < 10;
  }

  FriendsState copyWith({
    bool? loading,
    String? error,
    List<FriendPresence>? friends,
    DateTime? lastSyncedAt,
    DateTime? lastEventAt,
    bool clearError = false,
  }) {
    return FriendsState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      friends: friends ?? this.friends,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastEventAt: lastEventAt ?? this.lastEventAt,
    );
  }
}

/// 一个分组 = 一个实例（同一个世界、同一个房间），或「离线」这类虚拟组。
class FriendGroup {
  const FriendGroup({
    required this.key,
    required this.members,
    this.worldId,
    this.instanceId,
  });

  final String key;
  final String? worldId;
  final String? instanceId;
  final List<FriendPresence> members;

  bool get isOfflineGroup => key == '__offline__';
  bool get isPrivateGroup => key == '__private__';

  /// 在浏览器里玩 VRChat 的那批人（没有世界位置）。
  bool get isWebGroup => key == '__web__';

  /// 真正落在某个世界某个房间里的分组。
  bool get isRoomGroup => worldId != null;

  InstancePrivacy get instanceType =>
      members.isEmpty ? InstancePrivacy.unknown : members.first.parsedLocation.instanceType;

  /// 带「邀请+」区分的完整类型文案。
  String get privacyLabel => members.isEmpty
      ? InstancePrivacy.unknown.label
      : members.first.parsedLocation.privacyLabel;
}

/// 一个分组属于哪一类，用于界面上的显示/隐藏开关。
String groupKindOf(FriendGroup group) {
  if (group.worldId != null) return 'room';
  if (group.isPrivateGroup) return 'private';
  if (group.isWebGroup) return 'web';
  if (group.isOfflineGroup) return 'offline';
  return 'unknown';
}

/// 把好友按所在房间分组。
///
/// 抽成顶层函数是因为界面上的筛选会先过滤一遍列表再分组，
/// 两边必须用同一套规则，否则筛选后的排序会跟原来不一致。
List<FriendGroup> buildFriendGroups(List<FriendPresence> friends) {
  final buckets = <String, List<FriendPresence>>{};
  for (final f in friends) {
    buckets.putIfAbsent(f.groupKey, () => []).add(f);
  }

  // groupKey 形如 `wrld_xxx:12345~region(us)`。
  ({String? worldId, String? instanceId}) splitRoom(String key) {
    if (!key.startsWith('wrld_')) return (worldId: null, instanceId: null);
    final sep = key.indexOf(':');
    if (sep < 0) return (worldId: key, instanceId: null);
    return (worldId: key.substring(0, sep), instanceId: key.substring(sep + 1));
  }

  final list = buckets.entries
      .map(
        (e) {
          final room = splitRoom(e.key);
          return FriendGroup(
            key: e.key,
            worldId: room.worldId,
            instanceId: room.instanceId,
            members: e.value
              ..sort(
                (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
              ),
          );
        },
      )
      .toList();

  // 排序：有世界的最前（人多的优先），然后私密 → Web 在线 → 位置不可见 → 离线。
  int rank(FriendGroup g) {
    if (g.worldId != null) return 0;
    if (g.isPrivateGroup) return 1;
    if (g.isWebGroup) return 2;
    if (g.isOfflineGroup) return 4;
    return 3;
  }

  list.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return b.members.length.compareTo(a.members.length);
  });
  return list;
}

class FriendsController extends Notifier<FriendsState> {
  final Map<String, FriendPresence> _byId = {};
  final PresenceTracker _tracker = PresenceTracker();
  bool _pipelineAttached = false;
  DateTime? _lastEventAt;

  /// 上次刷新通知列表的时间（节流用）。
  DateTime? _lastNotificationRefresh;

  /// 刷新通知列表（3 秒内只刷一次，避免 boop 刷屏打爆接口）。
  void _scheduleNotificationRefresh() {
    final now = DateTime.now();
    final last = _lastNotificationRefresh;
    if (last == null || now.difference(last).inSeconds >= 3) {
      _lastNotificationRefresh = now;
      ref.invalidate(notificationsProvider);
    }
  }

  @override
  FriendsState build() {
    return const FriendsState();
  }

  /// [silent] 用于后台轮询：不显示 loading，失败也不打断当前界面。
  Future<void> refresh({bool silent = false}) async {
    if (state.loading) return;
    if (!silent) state = state.copyWith(loading: true, clearError: true);

    final client = ref.read(vrcClientProvider);
    try {
      await _tracker.ensureLoaded();

      // 刷新前快照：REST 前后两份数据的差异就是一条动态。
      // 实时通道只覆盖 App 开着时的推送，这条路径补上冷启动和通道失效时的变化。
      final previous = Map<String, FriendPresence>.from(_byId);

      // 注意：offline 参数是「只返回哪一类」，不是「是否包含离线」。
      // offline:false → 只有在线好友；offline:true → 只有离线好友。
      // 只拉其中一个的话，列表里永远是 0 在线（或只有在线的人）。
      final batches = await Future.wait([
        _fetchFriendGroup(client, offline: false),
        _fetchFriendGroup(client, offline: true),
      ]);

      final merged = <String, LimitedUserFriend>{};
      for (final batch in batches) {
        for (final f in batch) {
          // 同一个 id 只留一份，在线那次先到 → 保留在线的信息。
          merged.putIfAbsent(f.id, () => f);
        }
      }

      _byId
        ..clear()
        ..addEntries(
          merged.values.map((f) {
            final base = FriendPresence.fromFriend(f);
            // 冷启动时把「在当前房间待了多久」接上：位置没变就沿用上次记的时间。
            final p = base.copyWith(
              locationSince: _tracker.sinceFor(base.userId, base.groupKey),
            );
            return MapEntry(p.userId, p);
          }),
        );

      _recordRefreshDiff(previous);
      _trackMeets(DateTime.now());

      state = FriendsState(
        friends: _sorted(),
        lastSyncedAt: DateTime.now(),
      );
      _attachPipeline();
      unawaited(_checkFriendRequests());
    } catch (e) {
      if (silent) {
        debugPrint('后台刷新好友失败（忽略）: $e');
        return;
      }
      state = state.copyWith(loading: false, error: _friendly(e));
    }
  }

  /// 对比两次 REST 快照，把变化记成动态。
  ///
  /// 首次同步（[previous] 为空）只建立基线，不补任何事件 —— 否则一装 App
  /// 就会凭空出现几百条「上线」。之后每 60 秒轮询一次，变化自然就进来了。
  void _recordRefreshDiff(Map<String, FriendPresence> previous) {
    if (previous.isEmpty) return;

    final at = DateTime.now();
    final transitions = <({FriendPresence friend, bool online})>[];
    for (final current in _byId.values) {
      final old = previous[current.userId];
      if (old == null) continue;

      if (old.isOnline != current.isOnline) {
        // Web 端上下线不记动态 —— 只有真的进/出游戏才提醒。
        if (current.isWebPlatform || old.isWebPlatform) continue;
        transitions.add((friend: current, online: current.isOnline));
        _tracker.record(
          PresenceEvent(
            at: at,
            userId: current.userId,
            displayName: current.displayName,
            kind: current.isOnline ? PresenceKind.online : PresenceKind.offline,
            worldId: current.isOnline ? current.parsedLocation.worldId : null,
            avatarUrl: current.avatarUrl,
          ),
        );
        continue;
      }
      if (!current.isOnline) continue;

      if (old.groupKey != current.groupKey) {
        _tracker.record(
          PresenceEvent(
            at: at,
            userId: current.userId,
            displayName: current.displayName,
            kind: PresenceKind.moved,
            worldId: current.parsedLocation.worldId,
            instanceId: current.parsedLocation.instanceId,
            note: _locationNote(current),
            avatarUrl: current.avatarUrl,
          ),
        );
      } else if (old.status != current.status) {
        _tracker.record(
          PresenceEvent(
            at: at,
            userId: current.userId,
            displayName: current.displayName,
            kind: PresenceKind.status,
            note: userStatusLabel(current.status),
            statusDescription: current.statusDescription,
            avatarUrl: current.avatarUrl,
          ),
        );
      }
    }

    unawaited(_dispatchPresence(transitions));
  }

  /// 把上下线变化发成系统通知，顺便过滤掉不在提醒范围里的好友。
  Future<void> _dispatchPresence(
    List<({FriendPresence friend, bool online})> transitions,
  ) async {
    if (transitions.isEmpty) return;
    final settings = FriendNotifier.instance.settings.value;
    if (!settings.anyFriend) return;

    Map<String, Set<String>>? membership;
    if (settings.scope == NotifyScope.groups) {
      membership = await _favoriteGroupMembership();
    }

    for (final t in transitions) {
      final groups = membership?[t.friend.userId] ?? const <String>{};
      if (!FriendNotifier.instance.allows(t.friend.userId, groups)) continue;
      if (t.online) {
        await FriendNotifier.instance.notifyOnline(t.friend.displayName);
      } else {
        await FriendNotifier.instance.notifyOffline(t.friend.displayName);
      }
    }
  }

  /// 好友收藏夹成员表：用户 ID → 所属收藏夹内部名。
  ///
  /// 只在「提醒范围 = 收藏分组」时才会拉，且拉一次就一直缓存着。
  Map<String, Set<String>>? _favoriteMembershipCache;

  Future<Map<String, Set<String>>> _favoriteGroupMembership() async {
    final cached = _favoriteMembershipCache;
    if (cached != null) return cached;
    final map = <String, Set<String>>{};
    try {
      final favorites = await ref.read(friendFavoritesProvider.future);
      for (final f in favorites) {
        if (f.tags.isEmpty) continue;
        for (final id in [f.id, f.favoriteId]) {
          if (id.isEmpty) continue;
          map.putIfAbsent(id, () => <String>{}).addAll(f.tags);
        }
      }
    } catch (e) {
      debugPrint('读取好友收藏夹失败（提醒范围暂时落空）: $e');
    }
    _favoriteMembershipCache = map;
    return map;
  }

  DateTime? _lastFriendRequestCheck;

  /// 检查通知列表里有没有新的好友申请。
  ///
  /// 每 60 秒刷新好友时都顺带拉通知太费电，这里自己节流到 4 分钟一次；
  /// 实时通道收到通知事件时会单独触发，不受这个限制。
  Future<void> _checkFriendRequests() async {
    if (!FriendNotifier.instance.settings.value.friendRequest) return;
    final now = DateTime.now();
    final last = _lastFriendRequestCheck;
    if (last != null && now.difference(last).inMinutes < 4) return;
    _lastFriendRequestCheck = now;
    try {
      final list = await ref.read(notificationsProvider.future);
      final requests = list
          .where((n) => n.isFriendRequest)
          .map((n) => (id: n.id, sender: n.senderUsername));
      await FriendNotifier.instance.handleFriendRequests(requests);
    } catch (e) {
      debugPrint('检查好友申请失败（忽略）: $e');
    }
  }

  /// 「好友+ · 状态语」这种一行补充说明，跟着「切换了世界」一起显示。
  String _locationNote(FriendPresence friend) {
    final parts = <String>[];
    if (friend.parsedLocation.hasWorld) parts.add(friend.parsedLocation.privacyLabel);
    final desc = friend.statusDescription.trim();
    if (desc.isNotEmpty) parts.add(desc);
    return parts.join(' · ');
  }

  /// 我自己所在的实例键，格式和 [FriendPresence.groupKey] 一致。
  ///
  /// 手机 App 自己不会「进入房间」，这个值只能来自 `/auth/user` 的 location，
  /// 也就是你同时在 PC 端上线时才有。不在世界里就返回 null，此时不判相遇。
  String? get _myInstanceKey {
    final auth = ref.read(authProvider);
    if (auth is! AuthSignedIn) return null;
    final loc = ParsedLocation.parse(auth.user.location);
    if (!loc.hasWorld || loc.instanceId == null) return null;
    return '${loc.worldId}:${loc.instanceId}';
  }

  /// 「相遇」：好友和我处在同一个实例。
  ///
  /// 只在新进来（或一起换了实例）时记一条，靠 tracker 里的标记去重；
  /// 已经不在同一实例的人会清掉标记，方便下次遇到再记。
  void _trackMeets(DateTime at) {
    final myKey = _myInstanceKey;
    for (final friend in _byId.values) {
      if (myKey == null || !friend.isOnline || friend.groupKey != myKey) {
        _tracker.clearMet(friend.userId);
        continue;
      }
      if (!_tracker.markMet(friend.userId, myKey)) continue;
      _tracker.record(
        PresenceEvent(
          at: at,
          userId: friend.userId,
          displayName: friend.displayName,
          kind: PresenceKind.met,
          worldId: friend.parsedLocation.worldId,
          instanceId: friend.parsedLocation.instanceId,
          avatarUrl: friend.avatarUrl,
        ),
      );
    }
  }

  Future<List<LimitedUserFriend>> _fetchFriendGroup(
    VrcClient client, {
    required bool offline,
  }) async {
    final out = <LimitedUserFriend>[];
    var offset = 0;
    const pageSize = 100;
    // 最多翻 5 页，够 500 个好友了；再多也没人看得过来。
    for (var page = 0; page < 5; page++) {
      final resp = await client.api
          .rawApi
          .getFriendsApi()
          .getFriends(n: pageSize, offset: offset, offline: offline);
      final batch = resp.data ?? const <LimitedUserFriend>[];
      out.addAll(batch);
      if (batch.length < pageSize) break;
      offset += pageSize;
    }
    return out;
  }

  void _attachPipeline() {
    if (_pipelineAttached) return;
    _pipelineAttached = true;

    final client = ref.read(vrcClientProvider);
    client.api.streaming.vrcEventStream.listen(
      _onPipelineEvent,
      onError: (Object e) => debugPrint('Pipeline 出错: $e'),
    );
    client.startPipeline();
  }

  /// 手动掐断重连。pipeline 偶尔会因为 token 过期静默掉线，
  /// 这时候点一下这个就能恢复。
  void reconnectPipeline() {
    _lastReconnectAt = DateTime.now();
    final client = ref.read(vrcClientProvider);
    client.stopPipeline();
    // 给 socket 一点时间收尾，别跟下一次 start 抢同一份 cookie。
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      client.startPipeline();
    });
  }

  DateTime? _lastReconnectAt;

  /// 从后台切回来时调用：实时通道久无消息就顺便重连一次。
  ///
  /// Pipeline 掉线是静默的 —— 库内部只有在"连接被断开"时才会自己重连，
  /// 而 token 过期那种情况它会直接放弃，界面上看不出异常，只是好友不再更新。
  void reconnectIfStale() {
    final now = DateTime.now();
    // 刚重连过就别折腾了。
    if (_lastReconnectAt != null &&
        now.difference(_lastReconnectAt!) < const Duration(minutes: 2)) {
      return;
    }
    final last = _lastEventAt;
    if (last != null && now.difference(last) < const Duration(minutes: 8)) {
      return;
    }
    reconnectPipeline();
  }

  void _onPipelineEvent(Object event) {
    var changed = false;
    _lastEventAt = DateTime.now();

    if (event is WebsocketFriendLocation) {
      final incoming = FriendPresence.fromUser(event.user);
      final merged = _merge(
        incoming.copyWith(
          location: event.location,
          travelingToLocation: event.travelingToLocation,
        ),
      );
      final old = _byId[merged.userId];
      final key = merged.groupKey;
      final since = _tracker.sinceFor(merged.userId, key);
      _byId[merged.userId] = merged.copyWith(locationSince: since);

      // 换了房间才记一条动态；只是状态语变了不算。
      if (merged.isOnline && (old == null || old.groupKey != key)) {
        _tracker.record(
          PresenceEvent(
            at: DateTime.now(),
            userId: merged.userId,
            displayName: merged.displayName,
            kind: PresenceKind.moved,
            worldId: merged.parsedLocation.worldId,
            instanceId: merged.parsedLocation.instanceId,
            note: _locationNote(merged),
            avatarUrl: merged.avatarUrl,
          ),
        );
      }
      changed = true;
    } else if (event is WebsocketFriendOnline) {
      final old = _byId[event.userId];
      if (old != null) {
        final updated = old.copyWith(
          status: old.status == UserStatus.offline ? UserStatus.active : old.status,
          location: event.location,
          platform: event.platform,
        );
        final since = _tracker.sinceFor(updated.userId, updated.groupKey);
        _byId[event.userId] = updated.copyWith(locationSince: since);
        if (!updated.isWebPlatform) {
          unawaited(_dispatchPresence([(friend: updated, online: true)]));
          _tracker.record(
            PresenceEvent(
              at: DateTime.now(),
              userId: updated.userId,
              displayName: updated.displayName,
              kind: PresenceKind.online,
              worldId: updated.parsedLocation.worldId,
              avatarUrl: updated.avatarUrl,
            ),
          );
        }
        changed = true;
      }
    } else if (event is WebsocketNotification) {
      // 实时通知的 details 是**完整**的（REST 列表里会被精简），
      // 先缓存起来，通知列表渲染时用它补全世界名 / 实例号。
      final d = event.details;
      if (d is Map && event.id.isNotEmpty) {
        ref
            .read(notificationDetailCacheProvider.notifier)
            .put(event.id, Map<String, dynamic>.from(d));
      }
      _scheduleNotificationRefresh();
    } else if (event is WebsocketNotificationV2Update ||
        event is WebsocketNotificationV2Delete) {
      // 通知类事件（好友申请、邀请、请求加入……）
      _scheduleNotificationRefresh();
      unawaited(_checkFriendRequests());
    } else if (event is WebsocketFriendOffline) {
      final old = _byId[event.userId];
      if (old != null) {
        _byId[event.userId] = old.copyWith(
          status: UserStatus.offline,
          location: 'offline',
          travelingToLocation: '',
        );
        // Web 端下线（只是关掉网页）不记动态。
        if (!old.isWebPlatform) {
          unawaited(_dispatchPresence([(friend: old, online: false)]));
          _tracker.record(
            PresenceEvent(
              at: DateTime.now(),
              userId: old.userId,
              displayName: old.displayName,
              kind: PresenceKind.offline,
              avatarUrl: old.avatarUrl,
            ),
          );
        }
        changed = true;
      }
    } else if (event is WebsocketFriendUpdate) {
      final merged = _merge(FriendPresence.fromUser(event.user));
      final old = _byId[merged.userId];
      _byId[merged.userId] = merged;
      // 只有状态真的变了才记一条，状态语微调不算。
      if (old != null && old.status != merged.status) {
        _tracker.record(
          PresenceEvent(
            at: DateTime.now(),
            userId: merged.userId,
            displayName: merged.displayName,
            kind: PresenceKind.status,
            note: userStatusLabel(merged.status),
            statusDescription: merged.statusDescription,
            avatarUrl: merged.avatarUrl,
          ),
        );
      }
      changed = true;
    } else if (event is WebsocketFriendAdd) {
      final merged = _merge(FriendPresence.fromUser(event.user));
      _byId[merged.userId] = merged;
      changed = true;
    } else if (event is WebsocketFriendDelete) {
      _byId.remove(event.userId);
      changed = true;
    }

    if (changed) {
      _trackMeets(DateTime.now());
      state = state.copyWith(
        friends: _sorted(),
        lastSyncedAt: DateTime.now(),
        lastEventAt: _lastEventAt,
      );
    } else if (_lastEventAt != null && state.lastEventAt == null) {
      // 收到过事件但没改变任何好友状态（比如别人的头像更新），
      // 也要把「通道活着」这个信号传出去。
      state = state.copyWith(lastEventAt: _lastEventAt);
    }
  }

  /// pipeline 给的字段常常比 REST 少，缺的部分保留旧值。
  FriendPresence _merge(FriendPresence incoming) {
    final old = _byId[incoming.userId];
    if (old == null) return incoming;
    return incoming.copyWith(
      avatarUrl: incoming.avatarUrl ?? old.avatarUrl,
      statusDescription: incoming.statusDescription.isEmpty ? old.statusDescription : incoming.statusDescription,
      trustRank: incoming.trustRank ?? old.trustRank,
    );
  }

  List<FriendPresence> _sorted() {
    final list = _byId.values.toList();
    list.sort((a, b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  /// 在线好友按**所在实例**分组（同世界不同房间要分开）；
  /// 离线和私密世界各自单独一组。
  List<FriendGroup> get groups => buildFriendGroups(state.friends);

  /// 本地记录的好友动态（最新在前）。
  List<PresenceEvent> get events => _tracker.events;

  /// 清空动态。用新实例赋值，保证依赖它的 provider 会重算。
  void clearEvents() {
    _tracker.clearEvents();
    state = FriendsState(
      friends: state.friends,
      lastSyncedAt: state.lastSyncedAt,
      lastEventAt: state.lastEventAt,
      loading: state.loading,
    );
  }

  /// 清空某一天的动态。
  void clearEventsOfDay(DateTime day) {
    _tracker.clearEventsOfDay(day);
    state = FriendsState(
      friends: state.friends,
      lastSyncedAt: state.lastSyncedAt,
      lastEventAt: state.lastEventAt,
      loading: state.loading,
    );
  }

  String _friendly(Object e) {    final text = e.toString();
    if (text.contains('401')) return '登录已失效，请重新登录';
    if (text.contains('429')) return '请求太频繁，等一会儿再刷新';
    if (text.contains('SocketException') || text.contains('Timeout')) {
      return '连不上 VRChat，检查网络（可能需要代理）';
    }
    return text;
  }
}

final friendsProvider = NotifierProvider<FriendsController, FriendsState>(
  FriendsController.new,
);

// ---------------------------------------------------------------------------
// 世界名 / 实例人数
// ---------------------------------------------------------------------------

/// 世界 ID → 世界名。provider 自己带缓存，同一个 worldId 只会请求一次。
final worldNameProvider = FutureProvider.family<String?, String>((ref, worldId) {
  return ref.read(vrcClientProvider).fetchWorldName(worldId);
});

/// 某实例当前人数。只在好友详情页里按需请求，不做批量。
final instanceOccupantsProvider =
    FutureProvider.family<int?, ({String worldId, String instanceId})>((ref, key) {
      return ref
          .read(vrcClientProvider)
          .fetchInstanceOccupants(worldId: key.worldId, instanceId: key.instanceId);
    });

/// 好友备注（`/userNotes`）。只有本账号能看到，用来在好友列表里搜索。
final friendNotesProvider = FutureProvider<Map<String, String>>((ref) async {
  final client = ref.watch(vrcClientProvider);
  final resp = await client.api.rawApi.getUsersApi().getUserNotes(n: 100);
  final notes = resp.data ?? const <UserNote>[];
  return {
    for (final n in notes)
      if (n.note.trim().isNotEmpty) n.targetUserId: n.note.trim(),
  };
});

/// 用户详情（`/users/{id}` + `/profile/{id}` 合起来）。
final userDetailProvider = FutureProvider.family<UserDetail, String>((ref, userId) {
  return ref.read(vrcClientProvider).fetchUserDetail(userId);
});

/// 资料页背景（渐变 / 自定义贴图 / VRC+ 预设）。
final profileBackgroundProvider =
    FutureProvider.family<ProfileBackground, String>((ref, userId) {
  return ref.read(vrcClientProvider).fetchProfileBackground(userId);
});

/// 好友动态列表。tracker 里的数据不会自己发通知，
/// 所以这里依赖 friendsProvider 的状态变化来触发重算。
final presenceEventsProvider = Provider<List<PresenceEvent>>((ref) {
  ref.watch(friendsProvider);
  return ref.read(friendsProvider.notifier).events;
});
