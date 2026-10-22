import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/album_file.dart';
import '../models/app_notification.dart';
import 'friends_provider.dart';

/// 搜人。空关键词直接返回空列表，避免打无效请求。
final userSearchProvider =
    FutureProvider.family<List<LimitedUserSearch>, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final client = ref.watch(vrcClientProvider);
  final resp = await client.api.rawApi.getUsersApi().searchUsers(search: q, n: 40);
  return resp.data ?? const [];
});

/// 搜世界。
final worldSearchProvider =
    FutureProvider.family<List<LimitedWorld>, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final client = ref.watch(vrcClientProvider);
  final resp = await client.api
      .rawApi
      .getWorldsApi()
      .searchWorlds(search: q, n: 40, sort: SortOption.relevance, order: OrderOption.descending);
  return resp.data ?? const [];
});

/// 我创建的世界，包含未公开的（`/worlds?user=me`）。
final myCreatedWorldsProvider = FutureProvider<List<LimitedWorld>>((ref) async {
  final client = ref.watch(vrcClientProvider);
  final resp = await client.api.rawApi.getWorldsApi().searchWorlds(
    user: 'me',
    n: 100,
    sort: SortOption.updated,
    order: OrderOption.descending,
  );
  return resp.data ?? const [];
});

/// 世界详情（`/worlds/{id}`，比 LimitedWorld 多出简介等字段）。
final worldDetailProvider = FutureProvider.family<World, String>((ref, worldId) async {
  final client = ref.watch(vrcClientProvider);
  final resp = await client.api.rawApi.getWorldsApi().getWorld(worldId: worldId);
  final data = resp.data;
  if (data == null) throw Exception('世界不存在或已被删除');
  return data;
});

/// 某个世界当前的公开实例（按人数从多到少）。
final activeInstancesProvider =
    FutureProvider.family<List<Instance>, String>((ref, worldId) {
  return ref.read(vrcClientProvider).fetchActiveInstancesFor(worldId);
});

/// 用户的简要信息（名字 + 头像），用于只拿到 usr id 的场景（比如实例房主）。
final userBriefProvider = FutureProvider.family<
    ({String name, String icon})?, String>((ref, userId) async {
  if (userId.isEmpty) return null;
  try {
    final resp = await ref
        .read(vrcClientProvider)
        .api
        .rawApi
        .dio
        .get<dynamic>('/users/$userId');
    final d = resp.data;
    if (d is Map) {
      final m = Map<String, dynamic>.from(d);
      final icon = (m['iconUrl'] ?? '').toString();
      return (
        name: (m['displayName'] ?? '').toString(),
        icon: icon.isNotEmpty
            ? icon
            : (m['currentAvatarThumbnailImageUrl'] ?? '').toString(),
      );
    }
  } catch (_) {
    // 忽略
  }
  return null;
});

/// 拍立得接口的临时诊断信息（空状态时显示在界面上）。
final printDiagProvider = StateProvider<String>((ref) => '');

/// 相册文件列表。tag: gallery（相册）/ icon（头像）/ print（拍立得）。
final albumFilesProvider =
    FutureProvider.family<List<AlbumFile>, String>((ref, tag) async {
  final client = ref.read(vrcClientProvider);
  // 拍立得是独立实体（含删除过滤），其余走 files 接口。
  // 用户 id 从登录状态拿 —— client.currentUser 在恢复会话时可能没填充。
  final auth = ref.read(authProvider);
  final userId = auth is AuthSignedIn ? auth.user.id : '';
  var raw = <Map<String, dynamic>>[];
  if (tag == 'print') {
    if (userId.isEmpty) {
      ref.read(printDiagProvider.notifier).state = 'userId 为空（未登录？）';
    } else {
      final r = await client.fetchPrints(userId);
      raw = r.files;
      ref.read(printDiagProvider.notifier).state = r.diag;
    }
  } else {
    raw = await client.fetchFilesByTag(tag);
  }
  final out = <AlbumFile>[];
  final seen = <String>{};
  for (final j in raw) {
    // 严格过滤：接口偶尔会把 tags 里不含当前分类的文件也带回来
    final tags = (j['tags'] as List?)?.map((e) => e.toString()).toList();
    if (tags != null && tags.isNotEmpty && !tags.contains(tag)) continue;
    final f = tag == 'print'
        ? AlbumFile.fromPrintJson(j)
        : AlbumFile.fromJson(j, tag);
    if (f == null || !seen.add(f.id)) continue; // 同 id 只留一条
    out.add(f);
  }
  out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return out;
});

/// 世界资产体积（MB），按 assetUrl 查。
final assetSizeProvider = FutureProvider.family<double?, String>(
  (ref, url) => ref.read(vrcClientProvider).fetchAssetSizeMb(url),
);

/// 某个具体实例的详情（成员、人数、容量）。
final instanceDetailProvider = FutureProvider.family<Map<String, dynamic>?,
    ({String worldId, String instanceId})>((ref, key) async {
  if (key.worldId.isEmpty || key.instanceId.isEmpty) return null;
  return ref
      .read(vrcClientProvider)
      .fetchInstance(key.worldId, key.instanceId);
});

/// 按模型 id 查名字。
///
/// profile 里有时候只给 `currentAvatar` 的 id 而不给名字，
/// 这时补一次 `/avatars/{id}` 把名字拿回来。
final avatarNameProvider = FutureProvider.family<String?, String>((ref, avatarId) async {
  final client = ref.read(vrcClientProvider);
  final resp = await client.api.rawApi.getAvatarsApi().getAvatar(avatarId: avatarId);
  return resp.data?.name;
});

/// 世界收藏夹（VRChat 的 favorite worlds）。
final worldFavoriteGroupsProvider = FutureProvider<List<FavoriteGroup>>((ref) async {
  final resp = await ref
      .read(vrcClientProvider)
      .api
      .rawApi
      .getFavoritesApi()
      .getFavoriteGroups(type: FavoriteType.world);
  return resp.data ?? const [];
});

/// 世界收藏记录（`id` 是 worldId，`tags` 是夹子名；分页拉全）。
final worldFavoritesProvider = FutureProvider<List<Favorite>>((ref) async {
  final api = ref.read(vrcClientProvider).api.rawApi.getFavoritesApi();
  final out = <Favorite>[];
  var offset = 0;
  for (var page = 0; page < 5; page++) {
    final resp = await api.getFavorites(type: 'world', n: 100, offset: offset);
    final batch = resp.data ?? const <Favorite>[];
    out.addAll(batch);
    if (batch.length < 100) break;
    offset += 100;
  }
  return out;
});

/// 好友收藏夹（VRChat 的 favorite friends，每个夹子上限 150 人）。
final friendFavoriteGroupsProvider = FutureProvider<List<FavoriteGroup>>((ref) async {
  final resp = await ref
      .read(vrcClientProvider)
      .api
      .rawApi
      .getFavoritesApi()
      .getFavoriteGroups(type: FavoriteType.friend);
  return resp.data ?? const [];
});

/// 某个好友收藏夹里的成员 ID。
///
/// 这里不做「哪个字段才是 userId」的猜测：VRChat 的 spec 里
/// `favoriteId` 和 `id` 的注释是打架的（注释说 favoriteId 是目标 ID，
/// 实际返回里 favoriteId 是 `fvrt_` 开头的收藏记录，`id` 才是 userId）。
/// 所以两个都塞进集合，匹配时自然能命中。
///
/// 两个数据源也一起用：夹子内容接口可能因为夹子名带中文/符号而失败，
/// 那就退回「全部收藏记录按 tags 过滤」。
final favoriteGroupMembersProvider =
    FutureProvider.family<Set<String>, String>((ref, groupName) async {
  final out = <String>{};

  void addAll(String? a, String? b) {
    if (a != null && a.isNotEmpty) out.add(a);
    if (b != null && b.isNotEmpty) out.add(b);
  }

  // 来源一：直接查这个夹子的内容
  try {
    final resp = await ref
        .read(vrcClientProvider)
        .api
        .rawApi
        .getFavoritesApi()
        .getFavoriteGroupContents(
          favoriteGroupType: FavoriteType.friend,
          favoriteGroupName: groupName,
        );
    for (final e in resp.data?.favorites ?? const <FavoriteGroupContentsEntry>[]) {
      addAll(e.id, e.favoriteId);
    }
  } catch (e) {
    debugPrint('查收藏夹 $groupName 内容失败，改用收藏记录过滤: $e');
  }

  // 来源二：全部收藏记录里按 tags 挑
  try {
    final all = await ref.watch(friendFavoritesProvider.future);
    for (final f in all) {
      if (f.tags.contains(groupName)) addAll(f.id, f.favoriteId);
    }
  } catch (_) {
    // 上面已经尽力了，失败就是空
  }

  return out;
});

/// 收藏的好友记录（只用来数数量）。
final friendFavoritesProvider = FutureProvider<List<Favorite>>((ref) async {
  final api = ref.read(vrcClientProvider).api.rawApi.getFavoritesApi();
  final out = <Favorite>[];
  var offset = 0;
  for (var page = 0; page < 5; page++) {
    final resp = await api.getFavorites(type: 'friend', n: 100, offset: offset);
    final batch = resp.data ?? const <Favorite>[];
    out.addAll(batch);
    if (batch.length < 100) break;
    offset += 100;
  }
  return out;
});

/// 某个用户加入的全部群组。
///
/// profile 里的 `groups.list` 通常只给前几个（配合「查看全部」），
/// 想看完整列表得单独打这个接口。
final userGroupsProvider =
    FutureProvider.family<List<LimitedUserGroups>, String>((ref, userId) async {
  final resp = await ref
      .read(vrcClientProvider)
      .api
      .rawApi
      .getUsersApi()
      .getUserGroups(userId: userId);
  return resp.data ?? const [];
});

/// 群组详情。
final groupDetailProvider = FutureProvider.family<Group, String>((ref, groupId) async {  final client = ref.read(vrcClientProvider);
  final resp = await client.api.rawApi.getGroupsApi().getGroup(groupId: groupId);
  final data = resp.data;
  if (data == null) throw Exception('群组不存在或没有权限查看');
  return data;
});

/// 群组当前公告。没公告或没权限时返回 null，不当作错误。
final groupAnnouncementProvider =
    FutureProvider.family<GroupAnnouncement?, String>((ref, groupId) async {
  try {
    final resp = await ref
        .read(vrcClientProvider)
        .api
        .rawApi
        .getGroupsApi()
        .getGroupAnnouncements(groupId: groupId);
    return resp.data;
  } catch (_) {
    return null;
  }
});

/// 通知（V2 接口，比老接口信息全）。
/// pipeline 实时推来的通知 details 缓存（id → details）。
///
/// VRChat 的 REST 通知列表会把 details 精简（常只剩 worldId/worldName），
/// 而 pipeline 的 `notification` 事件里是完整数据（含 instanceId / location）。
/// VRCX 能显示 `#41796` 就是这么来的：常驻缓存，渲染时用缓存补全。
final notificationDetailCacheProvider = NotifierProvider<
    NotificationDetailCache, Map<String, Map<String, dynamic>>>(
  NotificationDetailCache.new,
);

class NotificationDetailCache
    extends Notifier<Map<String, Map<String, dynamic>>> {
  @override
  Map<String, Map<String, dynamic>> build() => {};

  void put(String id, Map<String, dynamic> details) {
    state = {...state, id: details};
  }
}

/// 通知列表。
///
/// VRChat 的通知分散在两个端点，而且**两边的 SDK 模型都会崩**：
/// - `/auth/user/notifications` —— 好友申请、邀请等（SDK 接口返回类型对不上）
/// - `/notifications` —— boop 等（`NotificationV2DetailsBoop.emojiId` 常为 null，
///   SDK 强转 String 直接抛 CheckedFromJsonException）
///
/// 所以两边都用 dio 直调 + `AppNotification` 宽容解析，任何一条坏了只丢那一条。
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  final client = ref.watch(vrcClientProvider);
  final out = <AppNotification>[];
  final seen = <String>{};
  NotificationParseStats.reset();

  void absorb(dynamic data) {
    dynamic list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      if (data['notifications'] is List) {
        list = data['notifications'];
      } else if (data['data'] is List) {
        list = data['data'];
      }
    }
    if (list is! List) return;
    for (final e in list) {
      if (e is! Map) continue;
      try {
        final n = AppNotification.fromJson(Map<String, dynamic>.from(e));
        if (n != null && seen.add(n.id)) {
          out.add(n);
          NotificationParseStats.record(ok: true);
        }
      } catch (err) {
        NotificationParseStats.record(ok: false, error: err);
      }
    }
  }

  for (final path in const ['/auth/user/notifications', '/notifications']) {
    try {
      final resp = await client.api.rawApi.dio.get<dynamic>(path);
      absorb(resp.data);
    } catch (err) {
      NotificationParseStats.record(ok: false, error: err);
    }
  }

  out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return out;
});

/// 解析邀请通知里的世界：先按 worldId 查，查不到或没有 id 就用世界名搜索。
///
/// 邀请通知的 details 有时只带 worldName 不带 worldId，
/// 或者 worldId 已经失效（世界被删）—— 所以加一层名字搜索兜底。
typedef ResolvedWorld = ({String id, String name, String thumb});

final worldResolveProvider = FutureProvider.family<ResolvedWorld?,
    ({String id, String name})>((ref, key) async {
  final client = ref.watch(vrcClientProvider);

  String thumbOf(Map<String, dynamic> m) {
    final t = (m['thumbnailImageUrl'] ?? '').toString();
    if (t.isNotEmpty) return t;
    return (m['imageUrl'] ?? '').toString();
  }

  // 1) 有 id 直接查详情
  if (key.id.startsWith('wrld_')) {
    try {
      final resp = await client.api.rawApi.dio.get<dynamic>('/worlds/${key.id}');
      final data = resp.data;
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        return (
          id: (m['id'] ?? key.id).toString(),
          name: (m['name'] ?? key.name).toString(),
          thumb: thumbOf(m),
        );
      }
    } catch (_) {
      // id 失效就往下走搜索
    }
  }

  // 2) 没有 id 就只显示通知里自带的名字，**绝不用名字去搜索**——
  //    搜索是全局模糊匹配，会命中同名/相似名的陌生世界，封面和名字全对不上。
  //    没封面只是不好看，显示错房间是事故。
  if (key.name.isNotEmpty) {
    return (id: '', name: key.name, thumb: '');
  }
  return null;
});

/// 通知发送者的头像（自定义头像优先，其次模型缩略图）。
final notificationSenderAvatarProvider =
    FutureProvider.family<String?, String>((ref, userId) async {
  try {
    final resp = await ref
        .read(vrcClientProvider)
        .api
        .rawApi
        .getUsersApi()
        .getUser(userId: userId);
    final u = resp.data;
    if (u == null) return null;
    final icon = u.iconUrl ?? '';
    if (icon.isNotEmpty) return icon;
    final thumb = u.currentAvatarThumbnailImageUrl ?? '';
    if (thumb.isNotEmpty) return thumb;
    final big = u.currentAvatarImageUrl ?? '';
    return big.isNotEmpty ? big : null;
  } catch (_) {
    return null;
  }
});

/// 已收藏的世界。
final favoritedWorldsProvider = FutureProvider<List<FavoritedWorld>>((ref) {
  return ref.read(vrcClientProvider).fetchFavoritedWorlds();
});

/// 世界的收藏夹分组（最多 4 个，名字可自定义）。
final favoriteGroupsProvider = FutureProvider<List<FavoriteGroup>>((ref) {
  return ref.read(vrcClientProvider).fetchFavoriteGroups();
});

/// 收藏夹的显示名。
///
/// VRChat 的默认名是 `Group 1`~`Group 4`，用户可以改成任意名字。
/// 没改过的转成中文，改过的照原样显示。
String favoriteGroupLabel(FavoriteGroup group) {
  final display = group.displayName.trim();
  if (display.isEmpty) return group.name;
  final m = RegExp(r'^Group\s*(\d+)$').firstMatch(display);
  if (m != null) return '收藏夹 ${m.group(1)}';
  return display;
}

/// 按收藏夹分区后的结果。
class FavoriteSection {
  const FavoriteSection({
    required this.key,
    required this.title,
    required this.worlds,
  });

  final String key;
  final String title;
  final List<FavoritedWorld> worlds;
}

/// 把收藏的世界按所属夹子分组。
///
/// `FavoritedWorld.favoriteGroup` 是内部名（`worlds1`），
/// 界面要显示的是 `FavoriteGroup.displayName`（可能被用户改成中文名了）。
final favoriteSectionsProvider = Provider<List<FavoriteSection>>((ref) {
  final groups = ref.watch(favoriteGroupsProvider).valueOrNull ?? const <FavoriteGroup>[];
  final worlds = ref.watch(favoritedWorldsProvider).valueOrNull ?? const <FavoritedWorld>[];

  // 内部名 → 显示名
  final titles = <String, String>{};
  for (final g in groups) {
    titles[g.name] = favoriteGroupLabel(g);
  }

  final buckets = <String, List<FavoritedWorld>>{};
  for (final w in worlds) {
    final key = w.favoriteGroup ?? '__other__';
    buckets.putIfAbsent(key, () => []).add(w);
  }

  // 按收藏夹顺序输出（worlds1 → worlds4），空的夹子不显示。
  final ordered = <String>[];
  for (final g in groups) {
    if (buckets.containsKey(g.name)) ordered.add(g.name);
  }
  // 游离的（夹子列表里没有的）放最后。
  for (final key in buckets.keys) {
    if (!ordered.contains(key)) ordered.add(key);
  }

  return ordered
      .map(
        (key) => FavoriteSection(
          key: key,
          title: key == '__other__' ? '未分组' : (titles[key] ?? key),
          worlds: buckets[key]!,
        ),
      )
      .toList();
});

/// 好友请求：从通知里筛出 friendRequest 这一类。
final friendRequestProvider = FutureProvider<List<AppNotification>>((ref) async {
  final all = await ref.watch(notificationsProvider.future);
  return all.where((n) => n.isFriendRequest).toList();
});

/// 从通知自带的选项里挑出「接受」和「拒绝」。
///
/// VRChat 不在文档里写死这两个值，而是把可选项塞在 `responses` 里，
/// 所以只能按 type 关键字猜，猜不到就退化成删除通知。
({NotificationV2Response? accept, NotificationV2Response? reject}) pickResponses(
  NotificationV2 notification,
) {
  NotificationV2Response? find(List<String> keywords) {
    for (final r in notification.responses) {
      final t = r.type.toLowerCase();
      if (keywords.any(t.contains)) return r;
    }
    return null;
  }

  return (
    accept: find(['accept', 'approve', 'yes']),
    reject: find(['reject', 'decline', 'ignore', 'deny', 'no']),
  );
}

/// 通知类型的展示信息。
({String label, String icon}) notificationVisual(String type) {
  final t = type.toLowerCase();
  if (t.contains('friend')) return (label: '好友', icon: 'friend');
  if (t.contains('invite')) return (label: '邀请', icon: 'invite');
  if (t.contains('boop')) return (label: '戳一戳', icon: 'boop');
  if (t.contains('group')) return (label: '群组', icon: 'group');
  if (t.contains('moderat')) return (label: '管理', icon: 'moderator');
  return (label: '系统', icon: 'system');
}
