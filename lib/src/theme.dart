import 'package:flutter/material.dart';

import 'widgets/motion.dart';

/// 深色为主的配色，接近 VRChat 官方界面那种「深底 + 青紫高光」的味道。
class AppTheme {
  const AppTheme._();

  static const Color accent = Color(0xFF7DD3FC);
  static const Color accentAlt = Color(0xFFA78BFA);
  static const Color canvas = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF151B23);
  static const Color surfaceHigh = Color(0xFF1E2630);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      surface: surface,
      primary: accent,
      secondary: accentAlt,
    );

    return ThemeData(
      // 页面转场统一成「淡入 + 轻微上移」，比默认左右滑更轻。
      // iOS 保留 Cupertino 那种，侧滑返回手势才在。
      // iOS / macOS 不覆盖，留给系统默认（保住侧滑返回手势）。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeUpPageTransitionsBuilder(),
        },
      ),
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Colors.white70,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.06),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 设计 token
//
// 之前圆角和字号都是各页面手写的，收敛出 8 种圆角、10 种字号，同类元素在
// 不同页面看起来还不一样。这里定义成常量，新代码一律用这些值。
// ---------------------------------------------------------------------------

/// 圆角：卡片 14 / 输入框·小控件 12 / 面板 20 / 胶囊用 [AppRadius.pill]
class AppRadius {
  const AppRadius._();

  static const double card = 14;
  static const double field = 12;
  static const double sheet = 20;
  static const double pill = 999;
}

/// 字号：标题 17 / 正文 15 / 次要 13 / 说明 12 / 标签 10.5
class AppText {
  const AppText._();

  static const double title = 17;
  static const double body = 15;
  static const double secondary = 13;
  static const double caption = 12;
  static const double label = 10.5;
}

/// 间距：4 的倍数
class AppSpace {
  const AppSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}
