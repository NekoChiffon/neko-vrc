import 'package:flutter/material.dart';

import '../theme.dart';

/// 骨架屏色块（带流光动画）。
///
/// 列表加载时用灰条占位，比转圈更容易让人感到「内容马上就来」。
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius,
  });

  final double? width;
  final double height;
  final BorderRadius? radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Colors.white.withValues(alpha: 0.045);
    final highlight = Colors.white.withValues(alpha: 0.10);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 3 - 1.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.radius ?? BorderRadius.circular(AppRadius.field),
            gradient: LinearGradient(
              begin: Alignment(t, 0),
              end: Alignment(t + 1, 0),
              colors: [base, highlight, base],
            ),
          ),
        );
      },
    );
  }
}

/// 好友列表骨架：头像圆 + 两行文字条。
class FriendListSkeleton extends StatelessWidget {
  const FriendListSkeleton({super.key, this.rows = 8});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      itemCount: rows,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 9),
        child: Row(
          children: [
            const SkeletonBox(
              width: 46,
              height: 46,
              radius: BorderRadius.all(Radius.circular(23)),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 90.0 + (i % 3) * 26),
                  const SizedBox(height: 8),
                  SkeletonBox(
                    width: 150.0 + (i % 4) * 22,
                    height: 10,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 详情页骨架：大图 + 标题 + 两行正文。
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(
            height: 180,
            radius: BorderRadius.all(Radius.circular(AppRadius.card)),
          ),
          const SizedBox(height: AppSpace.lg),
          const SkeletonBox(width: 220, height: 20),
          const SizedBox(height: AppSpace.md),
          const SkeletonBox(width: 140, height: 12),
          const SizedBox(height: AppSpace.xl),
          for (var i = 0; i < 3; i++) ...[
            SkeletonBox(width: double.infinity, height: 12),
            const SizedBox(height: AppSpace.sm),
          ],
          const SkeletonBox(width: 200, height: 12),
        ],
      ),
    );
  }
}
