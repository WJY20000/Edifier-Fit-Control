import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// 颜色与尺寸的唯一来源，页面里不再散落魔法数字。
class FitColors {
  /// 品牌蓝（取自新版漫步者图标的 #0088C9）：只用于「已选中 / 主操作」。
  static const Color accent = Color(0xFF0088C9);

  /// 更深的同色相，用于渐变收口、按下态。
  static const Color accentDeep = Color(0xFF005A85);

  /// 浅一档的同色相，用于深色主题里的图标与文字（直接压 #0088C9 对比度不够）。
  static const Color accentLight = Color(0xFF45B6EE);

  /// 金标认证用的香槟金。
  static const Color gold = Color(0xFFD8B45A);
  static const Color goldDeep = Color(0xFFA8842F);

  static const Color success = Color(0xFF35C759);
  static const Color warning = Color(0xFFF5A524);
  static const Color danger = Color(0xFFE5484D);

  // 深色面也带一点点蓝色倾向，避免和蓝色强调色打架（几乎看不出，但整体更统一）。
  static const Color bgDark = Color(0xFF0C0F13);
  static const Color surfaceDark = Color(0xFF151920);
  static const Color surfaceDarkHigh = Color(0xFF1C222B);

  static const Color bgLight = Color(0xFFF3F4F7);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceLightHigh = Color(0xFFF8F9FC);
}

class FitRadius {
  static const double hero = 26;
  static const double card = 20;
  static const double tile = 15;
  static const double pill = 999;
}

class FitSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
}

/// 视觉：深色为主、漫步者蓝作为强调色、香槟金做认证标识。
class FitTheme {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// 前景用的品牌色。
  ///
  /// 深色底上直接用 #0088C9 对比度只有 4.6:1，小字和细图标偏暗，
  /// 所以深色主题下换成同色相亮一档的 #45B6EE（约 7.8:1）；
  /// 填充、描边等大面积色块仍用 [FitColors.accent]。
  static Color accentOf(BuildContext context) =>
      isDark(context) ? FitColors.accentLight : FitColors.accent;

  /// 细边框：深色用白 6%，浅色用黑 5%。
  static Color hairline(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.black.withValues(alpha: 0.05);

  /// 低强度填充（未选中的选项、信息块）。
  static Color faint(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.045)
      : Colors.black.withValues(alpha: 0.035);

  static ColorScheme _scheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(seedColor: FitColors.accent, brightness: brightness);
    return base.copyWith(
      surface: dark ? FitColors.surfaceDark : FitColors.surfaceLight,
      onSurface: dark ? const Color(0xFFE9EBF1) : const Color(0xFF14171C),
      surfaceContainerHighest: dark ? FitColors.surfaceDarkHigh : FitColors.surfaceLightHigh,
      // 主操作按钮用主色 + 白字（#0088C9 上白字约 4.6:1，达到 AA）。
      // 深色主题的「前景图标」才用亮一档的 accentLight，见 [FitTheme.accentOf]。
      primary: FitColors.accent,
      onPrimary: Colors.white,
    );
  }

  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = _scheme(brightness);
    final base = ThemeData(
      colorScheme: colors,
      brightness: brightness,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
    );
    final muted = colors.onSurface.withValues(alpha: 0.58);

    return base.copyWith(
      scaffoldBackgroundColor: dark ? FitColors.bgDark : FitColors.bgLight,
      textTheme: _textTheme(base.textTheme),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: dark ? FitColors.surfaceDark : FitColors.surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FitRadius.card),
          side: BorderSide(
            color: dark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        // 和 OptionTile 用同一套「玻璃片」：半透明 + 一圈亮边。
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.06),
        ),
        backgroundColor: dark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.78),
        selectedColor: FitColors.accent.withValues(alpha: 0.16),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: colors.onSurface.withValues(alpha: 0.82),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FitRadius.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      ),
      dividerTheme: DividerThemeData(
        color: dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05),
        space: 1,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return FitColors.accent.withValues(alpha: dark ? 0.30 : 0.18);
            }
            return dark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.62);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return dark ? Colors.white : FitColors.accentDeep;
            }
            return colors.onSurface.withValues(alpha: 0.80);
          }),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: dark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          elevation: const WidgetStatePropertyAll<double?>(0.0),
          textStyle: const WidgetStatePropertyAll<TextStyle?>(
            TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          // 主操作也当玻璃做：底边压暗、顶边提亮，外面一圈品牌色辉光。
          side: BorderSide(
            color: Colors.white.withValues(alpha: dark ? 0.22 : 0.45),
          ),
          shadowColor: FitColors.accent.withValues(alpha: 0.55),
          elevation: 3,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: dark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.66),
          side: BorderSide(
            color: dark
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.08),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        minVerticalPadding: 10,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: faintOf(base),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          borderSide: const BorderSide(color: FitColors.accent, width: 1.4),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2F3A) : const Color(0xFF2A2F3A),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
      ),
      splashColor: FitColors.accent.withValues(alpha: 0.06),
      highlightColor: FitColors.accent.withValues(alpha: 0.04),
      extensions: const [],
    ).copyWith(
      textTheme: _textTheme(base.textTheme).apply(
        bodyColor: colors.onSurface,
        displayColor: colors.onSurface,
      ),
      // 给未选中文字一个稳定的辅助色。
      iconTheme: IconThemeData(color: muted),
    );
  }

  static Color faintOf(ThemeData base) => base.brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.045)
      : Colors.black.withValues(alpha: 0.035);

  /// 数字用等宽字形：电量、dBm、字节数在变化时不会左右抖。
  static TextStyle? _fig(TextStyle? style) =>
      style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextTheme _textTheme(TextTheme base) {
    final text = base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        height: 1.12,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.15,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 13.5, height: 1.45),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12, height: 1.45),
      labelLarge: base.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
    return text.copyWith(
      displayLarge: _fig(text.displayLarge),
      displayMedium: _fig(text.displayMedium),
      displaySmall: _fig(text.displaySmall),
      headlineLarge: _fig(text.headlineLarge),
      headlineMedium: _fig(text.headlineMedium),
      headlineSmall: _fig(text.headlineSmall),
      titleLarge: _fig(text.titleLarge),
      titleMedium: _fig(text.titleMedium),
      titleSmall: _fig(text.titleSmall),
      bodyLarge: _fig(text.bodyLarge),
      bodyMedium: _fig(text.bodyMedium),
      bodySmall: _fig(text.bodySmall),
      labelLarge: _fig(text.labelLarge),
      labelMedium: _fig(text.labelMedium),
      labelSmall: _fig(text.labelSmall),
    );
  }
}
