// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// AQ series palette values, maintained independently for ASpan.

/// Palettes change color only; shape, typography and motion remain shared.
enum SpanPalette {
  lucent('澄光', '冰蓝与清透'),
  folio('纸境', '暖纸与墨青'),
  edition('墨序', '骨白与朱红'),
  nocturne('曜夜', '石墨与冷紫');

  final String label, description;
  const SpanPalette(this.label, this.description);
  static SpanPalette parse(String? value) =>
      values.firstWhere((p) => p.name == value, orElse: () => lucent);
}

@immutable
class SpanColors extends ThemeExtension<SpanColors> {
  final Color background, backgroundEnd, panel, muted, line, soft;
  const SpanColors({
    required this.background,
    required this.backgroundEnd,
    required this.panel,
    required this.muted,
    required this.line,
    required this.soft,
  });
  static SpanColors of(BuildContext context) =>
      Theme.of(context).extension<SpanColors>() ??
      paletteColors(SpanPalette.lucent, Theme.of(context).brightness).$1;
  @override
  SpanColors copyWith({
    Color? background,
    Color? backgroundEnd,
    Color? panel,
    Color? muted,
    Color? line,
    Color? soft,
  }) => SpanColors(
    background: background ?? this.background,
    backgroundEnd: backgroundEnd ?? this.backgroundEnd,
    panel: panel ?? this.panel,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    soft: soft ?? this.soft,
  );
  @override
  SpanColors lerp(covariant SpanColors? other, double t) => other == null
      ? this
      : SpanColors(
          background: Color.lerp(background, other.background, t)!,
          backgroundEnd: Color.lerp(backgroundEnd, other.backgroundEnd, t)!,
          panel: Color.lerp(panel, other.panel, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          line: Color.lerp(line, other.line, t)!,
          soft: Color.lerp(soft, other.soft, t)!,
        );
}

(SpanColors, Color, Color) paletteColors(
  SpanPalette palette,
  Brightness brightness,
) {
  final values = switch ((palette, brightness == Brightness.dark)) {
    (SpanPalette.lucent, false) => const [
      0xfff5f8ff,
      0xffe7f1f4,
      0xffffffff,
      0xff5e6c82,
      0xffdce4ef,
      0xffe7edfc,
      0xff315ccc,
      0xff17253d,
    ],
    (SpanPalette.folio, false) => const [
      0xfffaf7ee,
      0xffe9eadd,
      0xfffcfaf3,
      0xff62665c,
      0xffdcd9cb,
      0xffe2e8de,
      0xff24554c,
      0xff292d29,
    ],
    (SpanPalette.edition, false) => const [
      0xfffaf9f4,
      0xffeae9e1,
      0xfffffdf7,
      0xff60635b,
      0xffd6d5cc,
      0xfff1e3dc,
      0xffb43d31,
      0xff202321,
    ],
    (SpanPalette.nocturne, false) => const [
      0xfff7f6fc,
      0xffe5e7f2,
      0xffffffff,
      0xff62667b,
      0xffdedeea,
      0xffeae8f6,
      0xff6760ad,
      0xff25263a,
    ],
    (SpanPalette.lucent, true) => const [
      0xff111d31,
      0xff152439,
      0xff1c2a40,
      0xffa8b7d1,
      0xff31425c,
      0xff2c4268,
      0xffa4bfff,
      0xffedf2fc,
    ],
    (SpanPalette.folio, true) => const [
      0xff222720,
      0xff292f26,
      0xff2d332a,
      0xffb8bcaa,
      0xff41483a,
      0xff3f4b37,
      0xffc8d9b6,
      0xffeeeade,
    ],
    (SpanPalette.edition, true) => const [
      0xff20221f,
      0xff2a2c25,
      0xff292c26,
      0xffb3b6aa,
      0xff45483e,
      0xff49322b,
      0xfff29983,
      0xfff0efe5,
    ],
    (SpanPalette.nocturne, true) => const [
      0xff12151e,
      0xff1d2130,
      0xff1c202d,
      0xffb0b2c7,
      0xff34394c,
      0xff37364d,
      0xffb3adf0,
      0xffeeedf7,
    ],
  };
  return (
    SpanColors(
      background: Color(values[0]),
      backgroundEnd: Color(values[1]),
      panel: Color(values[2]),
      muted: Color(values[3]),
      line: Color(values[4]),
      soft: Color(values[5]),
    ),
    Color(values[6]),
    Color(values[7]),
  );
}

ThemeData spanTheme(
  Brightness brightness, {
  SpanPalette palette = SpanPalette.lucent,
}) {
  final (tokens, accent, text) = paletteColors(palette, brightness);
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: accent,
        onPrimary: dark ? tokens.background : Colors.white,
        primaryContainer: tokens.soft,
        onPrimaryContainer: accent,
        secondaryContainer: tokens.soft,
        onSecondaryContainer: text,
        surface: tokens.panel,
        onSurface: text,
        onSurfaceVariant: tokens.muted,
        surfaceContainerLowest: tokens.panel,
        surfaceContainerLow: tokens.background,
        surfaceContainer: tokens.backgroundEnd,
        surfaceContainerHigh: tokens.soft,
        surfaceContainerHighest: tokens.soft,
        outlineVariant: tokens.line,
        surfaceTint: Colors.transparent,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.background,
    fontFamilyFallback: const [
      'Microsoft YaHei',
      'Noto Sans CJK SC',
      'sans-serif',
    ],
    visualDensity: VisualDensity.standard,
  );
  final line = BorderSide(color: tokens.line);
  // Three radii only: controls 12, surfaces 16, sheets/dialogs 24.
  RoundedRectangleBorder rounded(
    double r, [
    BorderSide side = BorderSide.none,
  ]) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(r),
    side: side,
  );
  final t = base.textTheme;
  return base.copyWith(
    extensions: [tokens],
    textTheme: t.copyWith(
      headlineLarge: t.headlineLarge?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
        height: 1.2,
      ),
      headlineMedium: t.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -.4,
        height: 1.25,
      ),
      headlineSmall: t.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleLarge: t.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: t.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: t.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: tokens.muted,
      ),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
      bodySmall: t.bodySmall?.copyWith(
        fontSize: 12.5,
        color: tokens.muted,
        height: 1.4,
      ),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: spanOverlayStyle(dark),
      backgroundColor: tokens.background,
      foregroundColor: text,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      titleTextStyle: t.titleLarge?.copyWith(
        color: text,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: tokens.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded(16, line),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.panel,
      surfaceTintColor: Colors.transparent,
      shape: rounded(24),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.panel,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: tokens.panel,
      showDragHandle: true,
      dragHandleSize: const Size(36, 4),
      dragHandleColor: tokens.line,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.panel,
      surfaceTintColor: Colors.transparent,
      shape: rounded(12, line),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(tokens.panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: rounded(12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: line,
        shape: rounded(12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: rounded(12),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: dark ? tokens.background : Colors.white,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 2,
      shape: rounded(16),
      extendedTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: line,
        selectedBackgroundColor: tokens.soft,
        selectedForegroundColor: accent,
        shape: rounded(12),
        visualDensity: VisualDensity.standard,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.muted,
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      subtitleTextStyle: t.bodySmall?.copyWith(
        fontSize: 12.5,
        color: tokens.muted,
        height: 1.4,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.background,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: line,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: line,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    dividerTheme: DividerThemeData(color: tokens.line, thickness: .6, space: 1),
    // Selected chips must read as selected without relying on a faint tint:
    // accent outline, accent label and a stronger fill.
    chipTheme: base.chipTheme.copyWith(
      color: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? accent.withValues(alpha: dark ? .22 : .12)
            : tokens.panel,
      ),
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(
          color: s.contains(WidgetState.selected) ? accent : tokens.line,
          width: s.contains(WidgetState.selected) ? 1.2 : 1,
        ),
      ),
      shape: rounded(10),
      labelStyle: TextStyle(color: text, fontSize: 13.5),
      secondaryLabelStyle: TextStyle(
        color: accent,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      showCheckmark: false,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: tokens.soft,
      linearMinHeight: 3,
      borderRadius: BorderRadius.circular(4),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? Colors.transparent : tokens.line,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      shape: rounded(12),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Edge-to-edge system bars: the app paints behind them and every scrollable
/// consumes the inset itself, so no background strip is ever needed.
SystemUiOverlayStyle spanOverlayStyle(bool dark) =>
    (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    );
