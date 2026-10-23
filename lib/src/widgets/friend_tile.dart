import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend_presence.dart';
import '../providers/cosmetics_provider.dart';
import '../theme.dart';
import '../providers/friends_provider.dart';

/// 好友列表里的一行。
///
/// 世界名由外层分组标题负责，这里只展示「这个人现在什么状态」。
class FriendTile extends ConsumerWidget {
  const FriendTile({
    super.key,
    required this.friend,
    this.onTap,
  });

  final FriendPresence friend;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtitle = _subtitle();

    // 名字牌：用官方 nameplateEffect 的图当底，没有就保持透明。
    final nameplateUrl =
        ref.watch(cosmeticsProvider).valueOrNull?.nameplateUrl(friend.nameplateEffect);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            _Avatar(friend: friend),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 名字牌背景交给 Container 的 decoration 画：
                  // 尺寸完全跟容器走，不会像 Stack + Positioned.fill 那样被算成零尺寸。
                  // 名字和下面的状态行都包在里面，底条铺满两行的高度。
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(8, 5, 10, 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      image: nameplateUrl == null
                          ? null
                          : DecorationImage(
                              // 列表里用静态首帧：每行都跑 APNG 太耗电，
                              // 动图留给资料页。
                              image: CachedNetworkImageProvider(
                                nameplateUrl,
                                headers: ref.watch(imageHeadersProvider),
                              ),
                              fit: BoxFit.cover,
                              alignment: Alignment.centerLeft,
                            ),
                      gradient: nameplateUrl != null
                          ? null
                          : LinearGradient(
                              colors: [
                                friend.trustColor.withValues(alpha: 0.20),
                                friend.trustColor.withValues(alpha: 0.03),
                              ],
                            ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friend.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            // 名字颜色跟着信任等级走，和 VRChat 里一致。
                            color: friend.trustColor.withValues(
                              alpha: friend.isOnline ? 1 : 0.55,
                            ),
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context.appColors.ink(0.62),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    final desc = friend.statusDescription.trim();
    if (desc.isNotEmpty) parts.add(desc);

    if (friend.isOnline) {
      final since = friend.locationSince;
      if (since != null && friend.parsedLocation.hasWorld) {
        final d = DateTime.now().difference(since);
        if (d.inMinutes >= 1) parts.add('在此 ${_duration(d)}');
      }
      if (parts.isEmpty) {
        if (friend.parsedLocation.isPrivate) return '私密世界';
        if (friend.isInPrivateInstance) return '不可见实例';
        return friend.platform.isEmpty ? '' : _platformLabel(friend.platform);
      }
      return parts.join(' · ');
    }

    if (parts.isNotEmpty) return parts.join(' · ');
    return friend.lastActivity != null ? '最后活动 ${_relative(friend.lastActivity!)}' : '';
  }

  /// 「6小时23分钟」这种口语化的时长，天数多了就只保留天数+小时。
  static String _duration(Duration d) {
    if (d.inHours >= 24) return '${d.inDays}天${d.inHours % 24}小时';
    if (d.inHours >= 1) return '${d.inHours}小时${d.inMinutes % 60}分钟';
    return '${d.inMinutes}分钟';
  }

  static String _platformLabel(String p) {
    final v = p.toLowerCase();
    // VRChat 的 platform 取值：standalonewindows / android / ios / web，
    // 其中 android 就是 Quest（没有单独的 quest 值）。
    if (v.contains('standalonewindows') || v.contains('windows')) return 'PC';
    if (v.contains('android')) return 'Quest';
    if (v.contains('ios')) return 'iOS';
    if (v.contains('web')) return 'Web 在线';
    return p;
  }

  static String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return '${(d.inDays / 30).floor()} 个月前';
  }
}

class _Avatar extends ConsumerWidget {
  const _Avatar({required this.friend});

  final FriendPresence friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const size = 46.0;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      alignment: Alignment.center,
      child: Text(
        friend.displayName.isEmpty ? '?' : friend.displayName.substring(0, 1).toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w600, color: context.appColors.ink(0.7)),
      ),
    );

    final frameAssets =
        ref.watch(cosmeticsProvider).valueOrNull?.iconFrameAssets(friend.iconFrame);
    final frameUrl = frameAssets?.main ?? frameAssets?.base;

    final url = friend.avatarUrl;
    final image = url == null || url.isEmpty
        ? fallback
        : ClipOval(
            child: CachedNetworkImage(
              imageUrl: url,
              httpHeaders: ref.watch(imageHeadersProvider),
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
          );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Opacity(opacity: friend.isOnline ? 1 : 0.55, child: image),
          if (frameUrl != null)
            // 头像框按 130% 放大叠上去，和资料页保持一致。
            Positioned(
              left: -size * 0.15,
              top: -size * 0.15,
              width: size * 1.3,
              height: size * 1.3,
              child: IgnorePointer(
                // 头像框同理，列表里只看静态首帧。
                child: CachedNetworkImage(
                  imageUrl: frameUrl,
                  httpHeaders: ref.watch(imageHeadersProvider),
                  fit: BoxFit.fill,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: friend.statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: context.appColors.canvas, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
