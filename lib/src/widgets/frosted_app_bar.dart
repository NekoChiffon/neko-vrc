import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// 顶部悬浮导航栏。
///
/// 不画 Material AppBar，也不做背景模糊：内容从栏下面滚过去，
/// 栏本身只有一层从上往下淡出的页面底色，保证标题可读又不出现硬边。
/// 右侧动作按钮统一做成圆形（参考 VRCM 的导航栏按钮）。
class FrostedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FrostedAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// 圆形按钮的直径。
  static const double buttonSize = 38;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.paddingOf(context).top;
    final totalHeight = statusBar + kToolbarHeight;
    final colors = context.appColors;

    Widget? effectiveLeading = leading;
    if (effectiveLeading == null &&
        automaticallyImplyLeading &&
        Navigator.of(context).canPop()) {
      effectiveLeading = const BackButton();
    }

    // 浅色主题下状态栏图标要换成深色，否则白字看不见。
    final overlayStyle = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    // 每个动作一颗浅色圆钮，带一点点描边和投影。
    final iconStyle = IconButton.styleFrom(
      backgroundColor: colors.surface,
      foregroundColor: colors.ink(0.85),
      disabledBackgroundColor: colors.surface.withValues(alpha: 0.6),
      disabledForegroundColor: colors.ink(0.3),
      shape: const CircleBorder(),
      fixedSize: const Size(buttonSize, buttonSize),
      iconSize: 20,
      padding: EdgeInsets.zero,
      // 默认的 padded 会把每颗按钮撑成 48 宽，和 38 宽的菜单圆钮对不齐。
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(color: colors.ink(0.06)),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: colors.isDark ? 0.4 : 0.18),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          children: [
            // 只留一层渐隐底色，没有模糊。
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.canvas.withValues(alpha: 0.92),
                      colors.canvas.withValues(alpha: 0.6),
                      colors.canvas.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.62, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: statusBar,
              left: 0,
              right: 0,
              height: kToolbarHeight,
              child: IconButtonTheme(
                data: IconButtonThemeData(style: iconStyle),
                child: DefaultTextStyle(
                  style: TextStyle(
                    color: colors.ink(1),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  child: NavigationToolbar(
                    leading: effectiveLeading == null
                        ? null
                        : Padding(
                            // 和右侧一样，给屏幕边缘留出 14 的空隙。
                            padding: const EdgeInsets.only(left: 14),
                            child: effectiveLeading,
                          ),
                    middle: title ?? const SizedBox.shrink(),
                    trailing: actions == null
                        ? null
                        : Padding(
                            // 别让最后一颗按钮贴着屏幕右边缘。
                            padding: const EdgeInsets.only(right: 14),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 8,
                              children: actions!,
                            ),
                          ),
                    middleSpacing: 12,
                    centerMiddle: false,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏在页面内容里占掉的高度：状态栏 + 工具栏。
double frostedAppBarInset(BuildContext context) =>
    MediaQuery.paddingOf(context).top + kToolbarHeight;
