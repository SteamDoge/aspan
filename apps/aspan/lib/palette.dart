// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/l10n.dart';

/// Palettes change color only; shape, typography and motion remain shared.
/// The stored names are part of the settings contract and must not change.
enum SpanPalette {
  lucent,
  folio,
  edition,
  nocturne;

  String get label => switch (this) {
    lucent => tr('澄光'),
    folio => tr('纸境'),
    edition => tr('墨序'),
    nocturne => tr('曜夜'),
  };
  static SpanPalette parse(String? value) =>
      values.firstWhere((p) => p.name == value, orElse: () => lucent);
}

/// Grouped-list tokens: a quiet page background, raised cards, hairlines,
/// one tint of the accent and one neutral fill for fields.
@immutable
class SpanColors extends ThemeExtension<SpanColors> {
  final Color background, panel, muted, line, soft, fill;
  const SpanColors({
    required this.background,
    required this.panel,
    required this.muted,
    required this.line,
    required this.soft,
    required this.fill,
  });

  /// Translucent bar color for navigation and tool bars.
  Color get bar => background.withValues(alpha: .92);

  static SpanColors of(BuildContext context) =>
      Theme.of(context).extension<SpanColors>() ??
      paletteColors(SpanPalette.lucent, Theme.of(context).brightness).$1;
  @override
  SpanColors copyWith({
    Color? background,
    Color? panel,
    Color? muted,
    Color? line,
    Color? soft,
    Color? fill,
  }) => SpanColors(
    background: background ?? this.background,
    panel: panel ?? this.panel,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    soft: soft ?? this.soft,
    fill: fill ?? this.fill,
  );
  @override
  SpanColors lerp(covariant SpanColors? other, double t) => other == null
      ? this
      : SpanColors(
          background: Color.lerp(background, other.background, t)!,
          panel: Color.lerp(panel, other.panel, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          line: Color.lerp(line, other.line, t)!,
          soft: Color.lerp(soft, other.soft, t)!,
          fill: Color.lerp(fill, other.fill, t)!,
        );
}

/// Returns the tokens, the accent and the primary text color.
(SpanColors, Color, Color) paletteColors(
  SpanPalette palette,
  Brightness brightness,
) {
  // background, panel, muted, line, soft, accent, text
  final values = switch ((palette, brightness == Brightness.dark)) {
    (SpanPalette.lucent, false) => const [
      0xfff2f2f7,
      0xffffffff,
      0xff69696e,
      0xffe2e2e7,
      0xffe5eefb,
      0xff0062cc,
      0xff1c1c1e,
    ],
    (SpanPalette.folio, false) => const [
      0xfff4f1e9,
      0xfffffdf8,
      0xff6b665b,
      0xffe5dfd2,
      0xfff6ead0,
      0xff8a5a00,
      0xff27241f,
    ],
    (SpanPalette.edition, false) => const [
      0xfff3f2ef,
      0xffffffff,
      0xff696761,
      0xffe3e1dc,
      0xfff8e3e0,
      0xffb8322a,
      0xff1f1e1c,
    ],
    (SpanPalette.nocturne, false) => const [
      0xfff2f1f7,
      0xffffffff,
      0xff68677a,
      0xffe2e1eb,
      0xffece9fb,
      0xff5b4cc2,
      0xff1e1d2a,
    ],
    (SpanPalette.lucent, true) => const [
      0xff000000,
      0xff1c1c1e,
      0xff9e9ea4,
      0xff38383a,
      0xff11284a,
      0xff5ea4ff,
      0xfff2f2f7,
    ],
    (SpanPalette.folio, true) => const [
      0xff12110e,
      0xff1f1d19,
      0xffa9a496,
      0xff3a372f,
      0xff3b2e12,
      0xfff0b445,
      0xfff3efe4,
    ],
    (SpanPalette.edition, true) => const [
      0xff0f0f0f,
      0xff1d1c1b,
      0xffa7a49e,
      0xff393734,
      0xff421f1b,
      0xffff8074,
      0xfff2f1ee,
    ],
    (SpanPalette.nocturne, true) => const [
      0xff0c0c14,
      0xff1c1b26,
      0xffa4a3b9,
      0xff363546,
      0xff2b2652,
      0xffb2a7ff,
      0xffefeef8,
    ],
  };
  final background = Color(values[0]), text = Color(values[6]);
  return (
    SpanColors(
      background: background,
      panel: Color(values[1]),
      muted: Color(values[2]),
      line: Color(values[3]),
      soft: Color(values[4]),
      // Translucent neutral fill so fields and tonal buttons read on both the
      // page background and cards.
      fill: brightness == Brightness.dark
          ? const Color.fromRGBO(118, 118, 128, .24)
          : const Color.fromRGBO(118, 118, 128, .12),
    ),
    Color(values[5]),
    text,
  );
}

ThemeData spanTheme(
  Brightness brightness, {
  SpanPalette palette = SpanPalette.lucent,
}) {
  final (tokens, accent, text) = paletteColors(palette, brightness);
  final dark = brightness == Brightness.dark;
  final error = dark ? const Color(0xffff6961) : const Color(0xffd70015);
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: accent,
        onPrimary: dark ? tokens.background : Colors.white,
        primaryContainer: tokens.soft,
        onPrimaryContainer: accent,
        secondaryContainer: tokens.soft,
        onSecondaryContainer: text,
        error: error,
        surface: tokens.panel,
        onSurface: text,
        onSurfaceVariant: tokens.muted,
        surfaceContainerLowest: tokens.panel,
        surfaceContainerLow: tokens.panel,
        surfaceContainer: tokens.panel,
        surfaceContainerHigh: tokens.panel,
        surfaceContainerHighest: tokens.fill,
        outline: tokens.line,
        outlineVariant: tokens.line,
        surfaceTint: Colors.transparent,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.background,
    fontFamilyFallback: const [
      'PingFang SC',
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'Noto Sans CJK SC',
      'sans-serif',
    ],
    visualDensity: VisualDensity.standard,
    // Pressed rows tint instead of rippling, as on Apple platforms.
    splashFactory: NoSplash.splashFactory,
  );
  RoundedRectangleBorder rounded(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  final t = base.textTheme;
  final none = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide.none,
  );
  return base.copyWith(
    extensions: [tokens],
    textTheme: t.copyWith(
      // Large page title.
      headlineLarge: t.headlineLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
        height: 1.2,
        color: text,
      ),
      // Hero numbers such as "3 天后" or a balance.
      headlineMedium: t.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -.4,
        height: 1.2,
        color: text,
      ),
      // List section titles: "需要处理", "接下来".
      headlineSmall: t.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -.2,
        height: 1.3,
        color: text,
      ),
      titleLarge: t.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: text,
      ),
      titleMedium: t.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: text,
      ),
      titleSmall: t.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: tokens.muted,
      ),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 16, height: 1.4, color: text),
      bodyMedium: t.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.4,
        color: text,
      ),
      bodySmall: t.bodySmall?.copyWith(
        fontSize: 13,
        color: tokens.muted,
        height: 1.35,
      ),
      labelLarge: t.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) =>
          const Icon(Icons.arrow_back_ios_new_rounded),
    ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: spanOverlayStyle(dark),
      backgroundColor: tokens.background,
      foregroundColor: accent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: accent),
      actionsIconTheme: IconThemeData(color: accent),
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
      shape: rounded(12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.panel,
      surfaceTintColor: Colors.transparent,
      shape: rounded(16),
      titleTextStyle: t.titleLarge?.copyWith(
        color: text,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.background,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: tokens.background,
      showDragHandle: true,
      dragHandleSize: const Size(36, 5),
      dragHandleColor: tokens.muted.withValues(alpha: .4),
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: .25),
      shape: rounded(12),
      textStyle: t.bodyLarge?.copyWith(fontSize: 15, color: text),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(tokens.panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        textStyle: t.labelLarge,
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: rounded(12),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: t.labelLarge,
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        foregroundColor: accent,
        backgroundColor: tokens.fill,
        side: BorderSide.none,
        shape: rounded(12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: accent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: rounded(10),
        textStyle: t.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    // The round add button shared with AQ.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: dark ? tokens.background : Colors.white,
      elevation: 3,
      focusElevation: 3,
      hoverElevation: 4,
      highlightElevation: 2,
      shape: const CircleBorder(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: BorderSide(color: tokens.line),
        backgroundColor: tokens.panel,
        selectedBackgroundColor: tokens.soft,
        selectedForegroundColor: accent,
        shape: rounded(10),
        visualDensity: VisualDensity.compact,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: accent,
      minLeadingWidth: 24,
      minVerticalPadding: 10,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      titleTextStyle: t.bodyLarge?.copyWith(fontSize: 16, color: text),
      subtitleTextStyle: t.bodySmall?.copyWith(
        fontSize: 13,
        color: tokens.muted,
        height: 1.35,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.fill,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: none,
      enabledBorder: none,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: error),
      ),
      hintStyle: TextStyle(color: tokens.muted),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    dividerTheme: DividerThemeData(color: tokens.line, thickness: .7, space: 1),
    chipTheme: base.chipTheme.copyWith(
      color: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : tokens.fill,
      ),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      // Selected chips are filled with the accent; call sites switch the
      // label to onPrimary (see [SpanChipLabel]).
      labelStyle: t.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: text,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      showCheckmark: false,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: tokens.fill,
      linearMinHeight: 4,
      borderRadius: BorderRadius.circular(4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (dark ? const Color(0xff30d158) : const Color(0xff248a3d))
            : tokens.fill,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      shape: rounded(12),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
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
