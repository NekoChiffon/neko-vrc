import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/friends_provider.dart';
import '../theme.dart';

/// 登录成功后的欢迎过渡页：头像 + 打招呼，1.6 秒后进入主页。
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key, required this.user});

  final CurrentUser user;

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.72, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.55, curve: Curves.easeOut),
    );
    _controller.forward();

    // 停一下再走，别一闪而过。
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) ref.read(welcomePendingProvider.notifier).state = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    final name = user.displayName;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.28),
            radius: 0.95,
            colors: [Color(0xFF1A2A33), Color(0xFF0B0F14)],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _scale,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 光晕
                      Container(
                        width: 168,
                        height: 168,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppTheme.accent.withValues(alpha: 0.28),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.55),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.28),
                              blurRadius: 26,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: avatar.isEmpty
                              ? ColoredBox(
                                  color: AppTheme.surfaceHigh,
                                  child: Icon(
                                    Icons.person,
                                    size: 42,
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                )
                              : CachedNetworkImage(
                                  imageUrl: avatar,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => const ColoredBox(
                                    color: AppTheme.surfaceHigh,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  '欢迎！',
                  style: TextStyle(
                    fontSize: AppText.body,
                    letterSpacing: 2,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent.withValues(alpha: 0.6),
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
