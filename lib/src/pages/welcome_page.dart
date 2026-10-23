import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/friends_provider.dart';
import '../theme.dart';

/// 登录成功后的过渡页：头像 + 名字，1.6 秒后进入主页。
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key, required this.user});

  final CurrentUser user;

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  @override
  void initState() {
    super.initState();
    // 停一下再走，别一闪而过。
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) ref.read(welcomePendingProvider.notifier).state = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    // VRChat 官方优先级：自定义资料头像（iconUrl，VRC+）> 模型缩略图 > 模型大图
    final icon = user.iconUrl ?? '';
    final avatar = icon.isNotEmpty
        ? icon
        : (user.currentAvatarThumbnailImageUrl.isNotEmpty
            ? user.currentAvatarThumbnailImageUrl
            : user.currentAvatarImageUrl);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            builder: (context, value, child) =>
                Opacity(opacity: value, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 88,
                    height: 88,
                    child: avatar.isEmpty
                        ? ColoredBox(color: context.appColors.surfaceHigh)
                        : CachedNetworkImage(
                            imageUrl: avatar,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                ColoredBox(color: context.appColors.surfaceHigh),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    user.displayName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '已登录',
                  style: TextStyle(
                    fontSize: AppText.caption,
                    color: context.appColors.ink(0.35),
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  '正在进入主页',
                  style: TextStyle(
                    fontSize: AppText.label,
                    color: context.appColors.ink(0.22),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
