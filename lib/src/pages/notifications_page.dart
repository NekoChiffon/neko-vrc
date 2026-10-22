import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/app_notification.dart';
import '../models/friend_presence.dart';
import '../providers/discovery_provider.dart';
import 'world_detail_page.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('通知')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              e.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppText.caption, color: Colors.white.withValues(alpha: 0.45)),
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 40,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '暂时没有通知',
                    style: TextStyle(
                      fontSize: AppText.caption,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  // 临时诊断：接口返回条数 / 解析失败数（release 包里看不到日志）
                  if (NotificationParseStats.total > 0 ||
                      NotificationParseStats.failed > 0) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        '接口返回 ${NotificationParseStats.total} 条'
                        '${NotificationParseStats.failed > 0 ? " · 解析失败 ${NotificationParseStats.failed}" : ""}'
                        '${NotificationParseStats.lastError != null ? "\n${NotificationParseStats.lastError}" : ""}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppText.label,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }

          final sorted = [...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: sorted.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 62,
                color: Colors.white.withValues(alpha: 0.05),
              ),
              itemBuilder: (context, i) => _NotificationRow(item: sorted[i]),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationRow extends ConsumerStatefulWidget {
  const _NotificationRow({required this.item});

  final AppNotification item;

  @override
  ConsumerState<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends ConsumerState<_NotificationRow> {
  bool _busy = false;

  Future<void> _reply() async {
    if (widget.item.senderUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这条通知没有带上发送者，戳不回去')),
      );
      return;
    }
    setState(() => _busy = true);
    // 不用 replyNotificationV2：那个接口的 body 有特定结构，
    // 传空对象会拿到非 JSON 响应，SDK 强转时直接崩。
    // 回戳本质上就是给对方再发一个 boop，走 boop 接口最稳。
    final client = ref.read(vrcClientProvider);
    final err = await client.boopUser(widget.item.senderUserId);
    // 戳回去之后把这条通知处理掉，不然它一直挂在那儿。
    if (err == null) {
      await client.hideNotification(widget.item.id);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(notificationsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '戳回去了')),
    );
  }

  Future<void> _acceptFriend() async {
    setState(() => _busy = true);
    final err = await ref
        .read(vrcClientProvider)
        .acceptFriendRequest(widget.item.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      ref.invalidate(notificationsProvider);
      ref.invalidate(friendsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已接受好友请求')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  /// VRChat 内置的 12 条邀请快捷回复（API 只认槽位索引，不能自由输入）。
  static const _quickReplies = [
    '我现在有点忙… 请稍等一下',
    '我等会就来找你！',
    '我要挂机了，等下再去找你。',
    '我要下线了，回头见！',
    '我正在参加活动，来不了。',
    '来我这里吧，我拉你。',
    '我无法给你发送邀请，等我问一下房主吧。',
    '抱歉，我现在暂时没空，有事给我留言吧！',
    '不好意思，这个房间是私人房。',
    '抱歉，这里满员了！',
    '我稍后就回来，到时候拉你！',
    '抱歉，我手头正在忙…',
  ];

  Future<void> _inviteMyself() async {
    final resolved = ref
        .read(worldResolveProvider((
          id: widget.item.worldId,
          name: widget.item.worldName,
        )))
        .valueOrNull;
    final worldId = resolved?.id ?? widget.item.worldId;
    final instanceId = widget.item.instanceId;
    if (worldId.isEmpty || instanceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这条邀请没带房间信息，无法邀请自己')),
      );
      return;
    }
    setState(() => _busy = true);
    final err = await ref
        .read(vrcClientProvider)
        .inviteMyself(worldId: worldId, instanceId: instanceId);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '邀请已发给自己，去 VRChat 客户端接受吧')),
    );
  }

  Future<void> _rejectWithReply() async {
    final slot = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 460,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '回复并拒绝',
                    style: const TextStyle(
                      fontSize: AppText.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选一句发给对方，之后这条邀请会被标记为已回复',
                    style: TextStyle(
                      fontSize: AppText.label,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _quickReplies.length,
                  itemBuilder: (context, i) => ListTile(
                    onTap: () => Navigator.pop(ctx, i),
                    title: Text(
                      _quickReplies[i],
                      style: const TextStyle(fontSize: AppText.secondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (slot == null || !mounted) return;

    setState(() => _busy = true);
    final client = ref.read(vrcClientProvider);
    final replyErr = await client.replyInvite(widget.item.id, slot);
    // 不管回复成功与否，这条邀请都要从列表里去掉（用户的意图就是拒绝）。
    final hideErr = await client.hideNotification(widget.item.id);
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(notificationsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(replyErr ?? hideErr ?? '已回复并拒绝')),
    );
  }

  Future<void> _hideNotification() async {
    setState(() => _busy = true);
    final err = await ref.read(vrcClientProvider).hideNotification(widget.item.id);
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(notificationsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '已忽略')),
    );
  }

  Future<void> _respond(String type, String data, String okText) async {
    setState(() => _busy = true);
    final client = ref.read(vrcClientProvider);
    // 好友申请用专用接口，其余走通用 respond。
    final isFriendRequest =
        widget.item.lowerType.contains('friendrequest') &&
            type.toLowerCase().contains('accept');
    final err = isFriendRequest
        ? await client.acceptFriendRequest(widget.item.id)
        : await client.respondNotification(
            notificationId: widget.item.id,
            responseType: type,
            responseData: data,
          );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      ref.invalidate(notificationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okText)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final visual = notificationVisual(item.type);
    final unread = !item.seen;
    final icon = _iconFor(visual.icon);
    final typeValue = item.type.toLowerCase();
    final isFriendRequest = typeValue.contains('friendrequest');
    final isBoop = typeValue.contains('boop');
    // 邀请行所需的房间信息：必须在 build 阶段解析，不能在按钮回调里 watch。
    final inviteWorld = item.isInvite
        ? ref
            .watch(worldResolveProvider((id: item.worldId, name: item.worldName)))
            .valueOrNull
        : null;
    final responses = isFriendRequest ? item.acceptReject : (accept: null, reject: null);
    final accept = responses.accept;
    final reject = responses.reject;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NotificationLeading(
            icon: icon,
            unread: unread,
            senderUserId: item.senderUserId,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (unread)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppText.secondary,
                          fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                          color: Colors.white.withValues(alpha: unread ? 0.95 : 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relative(item.createdAt),
                      style: TextStyle(
                        fontSize: AppText.label,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
                if (item.message.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.message.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.caption,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
                if ((item.senderUsername ?? '').isNotEmpty || item.imageUrl != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (item.imageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: item.imageUrl!,
                            httpHeaders: ref.watch(imageHeadersProvider),
                            width: 90,
                            height: 52,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      if ((item.senderUsername ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '来自 ${item.senderUsername}',
                            style: TextStyle(
                              fontSize: AppText.label,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (item.isInvite) ...[
                  const SizedBox(height: 10),
                  _InviteCard(
                    item: item,
                    onTap: () {
                      final id = inviteWorld?.id ?? item.worldId;
                      if (id.isEmpty) return;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => WorldDetailPage(
                            worldId: id,
                            instanceLocation:
                                item.instanceId.isEmpty ? null : item.instanceId,
                          ),
                        ),
                      );
                    },
                  ),
                ],
                if (item.isInvite) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : _inviteMyself,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          textStyle: const TextStyle(fontSize: AppText.caption),
                        ),
                        child: const Text('邀请自己'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : _hideNotification,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          textStyle: const TextStyle(fontSize: AppText.caption),
                          foregroundColor: Colors.white60,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Text('拒绝'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : _rejectWithReply,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          textStyle: const TextStyle(fontSize: AppText.caption),
                          foregroundColor: Colors.white60,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Text('拒绝并回复'),
                      ),
                    ],
                  ),
                ],
                if (isBoop) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _reply,
                    icon: const Icon(Icons.touch_app_outlined, size: 15),
                    label: const Text('戳回去'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(fontSize: AppText.caption),
                    ),
                  ),
                ],
                if (isFriendRequest) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : _acceptFriend,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          textStyle: const TextStyle(fontSize: AppText.caption),
                        ),
                        child: const Text('接受'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _busy ? null : _hideNotification,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          textStyle: const TextStyle(fontSize: AppText.caption),
                          foregroundColor: Colors.white60,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Text('忽略'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String kind) => switch (kind) {
    'friend' => Icons.person_add_alt_1_outlined,
    'invite' => Icons.mail_outline,
    'boop' => Icons.touch_app_outlined,
    'group' => Icons.groups_outlined,
    'moderator' => Icons.gavel_outlined,
    _ => Icons.notifications_none,
  };

  static String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return '${(d.inDays / 30).floor()} 个月前';
  }
}

/// 通知左侧：能拿到发送者就显示 VRChat 头像，否则退回类型图标。
class _NotificationLeading extends ConsumerWidget {
  const _NotificationLeading({
    required this.icon,
    required this.unread,
    required this.senderUserId,
  });

  final IconData icon;
  final bool unread;
  final String senderUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        icon,
        size: 18,
        color: unread ? AppTheme.accent : Colors.white.withValues(alpha: 0.35),
      ),
    );

    if (senderUserId.isEmpty) return fallback;

    final url = ref
        .watch(notificationSenderAvatarProvider(senderUserId))
        .valueOrNull;

    if (url == null || url.isEmpty) return fallback;

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: unread
              ? AppTheme.accent.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: CachedNetworkImage(
          imageUrl: url,
          httpHeaders: ref.watch(imageHeadersProvider),
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

/// 邀请通知里的房间卡片：缩略图 + 世界名 + 类型。
class _InviteCard extends ConsumerWidget {
  const _InviteCard({required this.item, this.onTap});

  final AppNotification item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref
        .watch(worldResolveProvider((id: item.worldId, name: item.worldName)))
        .valueOrNull;
    final thumb = resolved?.thumb ?? '';
    final name = (resolved == null || resolved.name.isEmpty)
        ? (item.worldName.isNotEmpty ? item.worldName : '未知世界')
        : resolved.name;

    // 通知本身常常只带 worldId/worldName，没有实例号。
    // 但邀请人此刻就在那个实例里 —— 从好友列表里取他的位置，就能拿到完整实例信息。
    final friends = ref.watch(friendsProvider).friends;
    FriendPresence? sender;
    for (final f in friends) {
      if (f.userId == item.senderUserId) {
        sender = f;
        break;
      }
    }
    String liveInstance = '';
    if (sender != null) {
      final loc = sender.parsedLocation;
      if (loc.hasWorld &&
          (item.worldId.isEmpty || loc.worldId == item.worldId)) {
        liveInstance = loc.instanceId ?? '';
      }
    }

    // 实例类型 / 区域从 instanceId 里读
    var typeLabel = '';
    var region = '';
    final inst = liveInstance.isNotEmpty ? liveInstance : item.instanceId;
    if (inst.contains('private(')) {
      typeLabel = inst.contains('canRequestInvite') ? '邀请+' : '仅限邀请';
    } else if (inst.contains('friends(')) {
      typeLabel = '仅限好友';
    } else if (inst.contains('hidden(')) {
      typeLabel = '好友+';
    } else if (inst.contains('group(')) {
      typeLabel = '群组';
    } else if (inst.isNotEmpty) {
      typeLabel = '公开';
    }
    final regionMatch = RegExp(r'region\(([^)]+)\)').firstMatch(inst);
    if (regionMatch != null) region = regionMatch.group(1)!.toUpperCase();

    // 实例号（`wrld_xxx:12345~...` 里的 12345）
    var instanceNumber = '';
    final colon = inst.indexOf(':');
    final tail = colon >= 0 ? inst.substring(colon + 1) : inst;
    if (tail.isNotEmpty) {
      instanceNumber = tail.split('~').first;
    }

    final metaParts = <String>[
      if (typeLabel.isNotEmpty) typeLabel,
      if (region.isNotEmpty) region,
      if (instanceNumber.isNotEmpty) '#$instanceNumber',
      if (item.inviteMessage.isNotEmpty) item.inviteMessage,
    ];
    final metaText = metaParts.isNotEmpty
        ? metaParts.join(' · ')
        : '点「查看房间」查看具体实例';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.field),
            child: SizedBox(
              width: 64,
              height: 44,
              child: thumb.isEmpty
                  ? const ColoredBox(color: AppTheme.surfaceHigh)
                  : CachedNetworkImage(
                      imageUrl: thumb,
                      httpHeaders: ref.watch(imageHeadersProvider),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          const ColoredBox(color: AppTheme.surfaceHigh),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppText.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metaText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.label,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right,
              size: 16,
              color: Colors.white.withValues(alpha: 0.25),
            ),
        ],
      ),
      ),
    );
  }
}
