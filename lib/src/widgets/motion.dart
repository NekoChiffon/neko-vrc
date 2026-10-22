import 'package:flutter/material.dart';

/// 内容变化时「弹一下」的缩放包装。
///
/// 用于未读角标这类数字会突变的地方：数值一变，从 1.0 弹到 1.25 再落回 1.0，
/// 比直接跳字更有存在感。
class PopOnChange extends StatefulWidget {
  const PopOnChange({
    super.key,
    required this.trigger,
    required this.child,
    this.maxScale = 1.25,
  });

  /// 变化时触发动画的值（比如未读数）。
  final Object? trigger;
  final Widget child;
  final double maxScale;

  @override
  State<PopOnChange> createState() => _PopOnChangeState();
}

class _PopOnChangeState extends State<PopOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: widget.maxScale)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(begin: widget.maxScale, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 60,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant PopOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// 页面转场：淡入 + 轻微上移。
///
/// 比默认的左右滑更「轻」，适合详情页这种从列表点进去的场景。
class FadeUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
