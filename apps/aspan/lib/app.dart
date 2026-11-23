// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data.dart';
import 'design.dart';
import 'entries.dart';
import 'navigation.dart';
import 'profile.dart';

class ASpanApp extends StatefulWidget {
  final SpanStore store;
  const ASpanApp({super.key, required this.store});
  @override
  State<ASpanApp> createState() => _ASpanAppState();
}

class _ASpanAppState extends State<ASpanApp> with WidgetsBindingObserver {
  Timer? timer;
  late final ValueNotifier<(String, String)> appearance;
  (String, String) get currentAppearance => (
    widget.store.setting('theme', 'system'),
    widget.store.setting('palette', 'lucent'),
  );
  void appearanceChanged() => appearance.value = currentAppearance;
  void startTimer() {
    timer?.cancel();
    timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => backgroundRefresh(),
    );
  }

  void backgroundRefresh() {
    widget.store.refresh().catchError((Object _) {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appearance = ValueNotifier(currentAppearance);
    widget.store.addListener(appearanceChanged);
    startTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      backgroundRefresh();
      startTimer();
    } else {
      timer?.cancel();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.store.removeListener(appearanceChanged);
    appearance.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) {
      final palette = SpanPalette.parse(
        widget.store.setting('palette', 'lucent'),
      );
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ASpan',
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: spanTheme(Brightness.light, palette: palette),
        darkTheme: spanTheme(Brightness.dark, palette: palette),
        themeMode: switch (widget.store.setting('theme', 'system')) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: SpanShell(store: widget.store),
      );
    },
  );
}

/// Top-level frame shared with AQ: a floating liquid-glass dock on narrow
/// screens and a rail from 840dp. One Scaffold owns the system insets: it
/// extends the body under the dock and reports the dock height as bottom
/// padding, so every tab scrolls beneath the translucent dock and stops
/// above it. Folders, details and settings sub-pages push above the dock.
class SpanShell extends StatefulWidget {
  final SpanStore store;
  const SpanShell({super.key, required this.store});
  @override
  State<SpanShell> createState() => _SpanShellState();
}

class _SpanShellState extends State<SpanShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final store = widget.store;
        final rail = constraints.maxWidth >= 840;
        final theme = Theme.of(context);
        final colors = SpanColors.of(context);
        final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
        final systemBottom = MediaQuery.paddingOf(context).bottom;
        final gestures = MediaQuery.systemGestureInsetsOf(context);
        final buttonScrim =
            !rail &&
            theme.platform == TargetPlatform.android &&
            systemBottom > 0 &&
            gestures.left == 0 &&
            gestures.right == 0;
        // Match AQ: Android button navigation follows the system theme even
        // when the app theme differs; gesture navigation stays transparent.
        final system = MediaQuery.platformBrightnessOf(context);
        final scrimColor = theme.brightness == system
            ? theme.scaffoldBackgroundColor.withValues(alpha: 0.9)
            : system == Brightness.dark
            ? const Color(0xCC000000)
            : const Color(0xE6FFFFFF);
        Widget tabs = IndexedStack(
          index: index,
          children: [
            FolderView(store: store, folder: Folder.home),
            ProjectsPage(store: store),
            SettingsPage(store: store),
          ],
        );
        if (store.lastRefreshError != null) {
          tabs = Column(
            children: [
              RefreshBanner(store: store),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: tabs,
                ),
              ),
            ],
          );
        }
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: spanOverlayStyle(theme.brightness == Brightness.dark).copyWith(
            systemNavigationBarIconBrightness: buttonScrim
                ? system == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark
                : null,
          ),
          child: Scaffold(
            backgroundColor: colors.background,
            extendBody: true,
            body: Stack(
              children: [
                Row(
                  children: [
                    // Preserve the content's element address across the
                    // breakpoint.
                    if (rail)
                      SafeArea(
                        right: false,
                        child: SpanNavigation(
                          rail: true,
                          selected: index,
                          onSelected: select,
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    Expanded(child: tabs),
                  ],
                ),
                if (buttonScrim)
                  Positioned(
                    key: const ValueKey('navigation-bar-scrim'),
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: systemBottom,
                    child: IgnorePointer(child: ColoredBox(color: scrimColor)),
                  ),
              ],
            ),
            bottomNavigationBar: rail || keyboard
                ? null
                : SpanNavigation(selected: index, onSelected: select),
          ),
        );
      },
    ),
  );

  void select(int value) => setState(() => index = value);
}

class RefreshBanner extends StatelessWidget {
  final SpanStore store;
  const RefreshBanner({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: scheme.errorContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Icon(
                  Icons.sync_problem,
                  size: 20,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '数据未刷新：${errorMessage(store.lastRefreshError!)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
                TextButton(
                  onPressed: () => perform(context, store.refresh),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
