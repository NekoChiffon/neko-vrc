import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets/motion.dart';

/// 深色 / 浅色两套主题共用的调色板。
///
/// 页面里不要直接写 `Colors.white.withValues(...)`：浅色模式下会很刺眼。
/// 用 `context.appColors.ink(0.5)` 这类写法，颜色会跟着当前主题走。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.canvas,
    required this.surface,
    required this.surfaceHigh,
    required this.inkBase,
    required this.accent,
    required this.accentAlt,
    required this.isDark,
  });

  /// 页面底色。
  final Color canvas;

  /// 卡片 / 弹层底色。
  final Color surface;

  /// 输入框、次级卡片底色。
  final Color surfaceHigh;

  /// 文字和图标的基础色（深色模式是白，浅色模式是近黑）。
  final Color inkBase;

  final Color accent;
  final Color accentAlt;
  final bool isDark;

  /// 文字 / 图标 / 分隔线用的颜色，[alpha] 越大越显眼。
  Color ink(double alpha) => inkBase.withValues(alpha: alpha);

  static const dark = AppColors(
    canvas: Color(0xFF0B0F14),
    surface: Color(0xFF151B23),
    surfaceHigh: Color(0xFF1E2630),
    inkBase: Colors.white,
    accent: Color(0xFF7DD3FC),
    accentAlt: Color(0xFFA78BFA),
    isDark: true,
  );

  /// 白 + 淡蓝 + 淡粉。底色偏一点点冷调的白，避免纯白扎眼。
  static const light = AppColors(
    canvas: Color(0xFFF4F6FA),
    surface: Colors.white,
    surfaceHigh: Color(0xFFE9EEF6),
    inkBase: Color(0xFF141A22),
    accent: Color(0xFF3D8FCF),
    accentAlt: Color(0xFFE488B3),
    isDark: false,
  );

  @override
  AppColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceHigh,
    Color? inkBase,
    Color? accent,
    Color? accentAlt,
    bool? isDark,
  }) {
    return AppColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      inkBase: inkBase ?? this.inkBase,
      accent: accent ?? this.accent,
      accentAlt: accentAlt ?? this.accentAlt,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      inkBase: Color.lerp(inkBase, other.inkBase, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentAlt: Color.lerp(accentAlt, other.accentAlt, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.dark;
}

/// 深色为主的配色，接近 VRChat 官方界面那种「深底 + 青紫高光」的味道。
class AppTheme {
  const AppTheme._();

  static const Color accent = Color(0xFF7DD3FC);
  static const Color accentAlt = Color(0xFFA78BFA);
  static const Color canvas = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF151B23);
  static const Color surfaceHigh = Color(0xFF1E2630);

  static ThemeData dark() => _build(AppColors.dark);

  static ThemeData light() => _build(AppColors.light);

  static ThemeData _build(AppColors colors) {
    final isDark = colors.isDark;
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      surface: colors.surface,
      primary: colors.accent,
      secondary: colors.accentAlt,
    );

    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

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
      scaffoldBackgroundColor: colors.canvas,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlayStyle,
        iconTheme: IconThemeData(color: colors.ink(0.85)),
        titleTextStyle: TextStyle(
          color: colors.ink(1),
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.ink(0.7),
      ),
      dividerTheme: DividerThemeData(
        color: colors.ink(0.06),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceHigh,
        hintStyle: TextStyle(color: colors.ink(0.35)),
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
          borderSide: BorderSide(color: colors.accent, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          foregroundColor: isDark ? colors.canvas : Colors.white,
          backgroundColor: colors.accent,
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
