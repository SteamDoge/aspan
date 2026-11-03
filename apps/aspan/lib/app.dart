// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data.dart';
import 'design.dart';
import 'details.dart';
import 'editor.dart';
import 'entries.dart';
import 'navigation.dart';
import 'profile.dart';
import 'widgets.dart';

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

/// Top-level frame. One Scaffold owns the system insets: it extends the body
/// under the floating dock and reports the dock height as bottom padding, so
/// every page scrolls beneath the translucent dock and stops above it.
class SpanShell extends StatefulWidget {
  final SpanStore store;
  const SpanShell({super.key, required this.store});
  @override
  State<SpanShell> createState() => _SpanShellState();
}

class _SpanShellState extends State<SpanShell> {
  int index = 0;
  bool projectMode = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final rail = constraints.maxWidth >= 840;
        final theme = Theme.of(context);
        final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
        final error = widget.store.lastRefreshError;
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
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: spanOverlayStyle(theme.brightness == Brightness.dark).copyWith(
            systemNavigationBarIconBrightness: buttonScrim
                ? system == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark
                : null,
          ),
          child: Scaffold(
            backgroundColor: SpanColors.of(context).background,
            extendBody: true,
            body: Stack(
              children: [
                SafeArea(
                  bottom: rail,
                  child: Row(
                    children: [
                      // Preserve the content's element address across the breakpoint.
                      if (rail)
                        SpanNavigation(
                          rail: true,
                          selected: index,
                          onSelected: select,
                        )
                      else
                        const SizedBox.shrink(),
                      Expanded(
                        child: Column(
                          children: [
                            if (error != null)
                              RefreshBanner(store: widget.store),
                            Expanded(
                              child: IndexedStack(
                                index: index,
                                children: [
                                  Home(store: widget.store),
                                  EntryBrowser(
                                    store: widget.store,
                                    embedded: true,
                                    onModeChanged: (active) {
                                      if (active != projectMode) {
                                        setState(() => projectMode = active);
                                      }
                                    },
                                  ),
                                  Profile(store: widget.store),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
            floatingActionButton:
                index == 2 || (index == 1 && projectMode) || keyboard
                ? null
                : FloatingActionButton.extended(
                    key: const ValueKey('create-rule'),
                    onPressed: () => openCreator(context, widget.store),
                    icon: const Icon(Icons.add),
                    label: const Text('新建规则'),
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
    );
  }
}

/// Large in-page title shared by the three destinations.
class PageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 0, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.headlineMedium),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Home answers "what needs me now?" and lets the user close a period
/// without leaving the page.
class Home extends StatelessWidget {
  final SpanStore store;
  const Home({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rules = store.rules;
    String phase(Json r) => store.view(r['id'] as String)['phase'] as String;
    String planned(Json r) =>
        store.view(r['id'] as String)['planned'] as String? ?? '9999';
    int byDate(Json a, Json b) => planned(a).compareTo(planned(b));
    final attention =
        rules.where((r) => actionPhases.contains(phase(r))).toList()
          ..sort((a, b) {
            final p = actionPhases
                .indexOf(phase(a))
                .compareTo(actionPhases.indexOf(phase(b)));
            return p == 0 ? byDate(a, b) : p;
          });
    final upcoming = rules.where((r) => phase(r) == 'reminder').toList()
      ..sort(byDate);
    final shown = {...attention, ...upcoming}.map((r) => r['id']).toSet();
    final pinned =
        rules
            .where((r) => r['pinned'] == true && !shown.contains(r['id']))
            .toList()
          ..sort(byDate);
    shown.addAll(pinned.map((r) => r['id']));
    final later =
        rules
            .where(
              (r) =>
                  !shown.contains(r['id']) &&
                  store.view(r['id'] as String)['planned'] != null,
            )
            .toList()
          ..sort(byDate);
    final low = store.accounts
        .where(
          (a) =>
              a['archived'] != true &&
              store.accountView(a['id'] as String)['active'] == true &&
              store.accountView(a['id'] as String)['low'] == true,
        )
        .toList();

    Widget row(Json r, {bool quick = false}) => RuleTile(
      key: ValueKey('home-${r['id']}'),
      store: store,
      rule: r,
      onTap: () => openRule(context, store, r['id'] as String),
      trailing: quick && store.view(r['id'] as String)['planned'] != null
          ? IconButton(
              tooltip: '完成本期',
              onPressed: () => eventSheet(context, store, r, 'completed'),
              icon: const Icon(Icons.check_circle_outline),
            )
          : null,
    );

    final summary = [
      '共 ${rules.length} 条规则',
      if (upcoming.isNotEmpty) '${upcoming.length} 项即将到来',
      if (low.isNotEmpty) '${low.length} 个资源不足',
    ].join('  ·  ');
    final children = <Widget>[
      Padding(
        key: const ValueKey('page-home'),
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
        child: Row(
          children: [
            Icon(Icons.all_inclusive, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'ASpan',
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
            ),
            const Spacer(),
            IconButton(
              tooltip: '刷新本地数据',
              onPressed: () => perform(context, store.refresh),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              friendlyDate(store.snapshot['today'] as String?),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            Semantics(
              header: true,
              child: Text(
                rules.isEmpty
                    ? '欢迎使用 ASpan'
                    : attention.isEmpty
                    ? '暂无需要处理的事项'
                    : '${attention.length} 项需要处理',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: attention.isEmpty ? null : warningColor(context),
                ),
              ),
            ),
            if (rules.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(summary, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
      if (rules.isEmpty)
        EmptyState(
          '从一件小事开始',
          '订阅、保活、次卡、证件有效期……\n每条规则只开启你需要的时间、资源与提醒。',
          icon: Icons.all_inclusive,
          action: FilledButton.icon(
            onPressed: () => openCreator(context, store),
            icon: const Icon(Icons.add),
            label: const Text('新建第一条规则'),
          ),
        ),
      if (attention.isNotEmpty) ...[
        const SectionHeader('需要处理', note: '逾期 → 今天 → 处理窗口'),
        for (final r in attention.take(50)) row(r, quick: true),
      ],
      if (low.isNotEmpty) ...[
        const SectionHeader('资源不足'),
        Panel(
          children: [
            for (final a in low)
              ListTile(
                leading: IconTile(
                  Icons.account_balance_wallet_outlined,
                  color: warningColor(context),
                  size: 32,
                ),
                title: Text(a['name'] as String),
                subtitle: Text(
                  '剩余 ${store.accountView(a['id'] as String)['formatted']} ${a['unit']['code']}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openAccount(context, store, a['id'] as String),
              ),
          ],
        ),
      ],
      if (upcoming.isNotEmpty) ...[
        const SectionHeader('提前提醒', note: '已进入提醒阶段'),
        for (final r in upcoming.take(30)) row(r, quick: true),
      ],
      if (pinned.isNotEmpty) ...[
        const SectionHeader('置顶'),
        for (final r in pinned) row(r),
      ],
      if (later.isNotEmpty) ...[
        SectionHeader(
          '接下来',
          trailing: TextButton(
            onPressed: () => openOverview(context, store),
            child: Text('全部 ${rules.length} 条'),
          ),
        ),
        for (final r in later.take(6)) row(r),
      ],
    ];
    return RefreshIndicator(
      onRefresh: () => perform(context, store.refresh),
      child: ListView(
        padding: pagePadding(context, fab: true),
        children: [
          for (final c in children) Readable(maxWidth: 1000, child: c),
        ],
      ),
    );
  }
}
