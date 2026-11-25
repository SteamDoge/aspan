// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';

import 'package:aspan/app.dart';
import 'package:aspan/data.dart';
import 'package:aspan/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Interface language: the setting is stored by the Rust core, applied to
/// every mounted page and restored on the next start.
void main() {
  late Directory root;
  late SpanStore store;
  const pinned = [Locale('zh', 'CN')];

  SpanStore open() => SpanStore(
    NativeApi(
      root.path,
      libraryPath:
          Platform.environment['ASPAN_RUST_LIB'] ??
          File('../../target/debug/aspan_bridge.dll').absolute.path,
    ),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aspan-language-');
    store = open();
    await store.refresh();
  });
  tearDown(() async {
    store.dispose();
    debugSystemLocales = pinned;
    initLanguage(AppLanguage.system);
    await root.delete(recursive: true);
  });

  void phone(WidgetTester tester, {double scale = 1}) {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Lets real native writes finish while pumping frames.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 150 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String code) async {
    await tester.ensureVisible(find.byKey(const ValueKey('open-language')));
    await tester.tap(find.byKey(const ValueKey('open-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('language-$code')));
    await until(tester, () => store.setting('language', 'system') == code);
  }

  testWidgets('settings switch the language everywhere and it persists', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('主页'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('nav-profile')));
    await tester.pumpAndSettle();
    expect(find.text('跟随系统'), findsWidgets);
    await choose(tester, 'en');
    expect(uiLanguage, UiLanguage.en);
    // The dock, the open tab and Material's own strings follow.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Projects'), findsWidgets);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('主页'), findsNothing);
    expect(find.text('外观'), findsNothing);
    expect(
      Localizations.localeOf(tester.element(find.byType(Scaffold).first)),
      UiLanguage.en.locale,
    );

    // A pushed page follows a change made while it is open.
    await tester.tap(find.byKey(const ValueKey('open-tags')));
    await tester.pumpAndSettle();
    expect(find.text('No tags yet'), findsOneWidget);
    await tester.runAsync(
      () => store.mutate('setting', {'key': 'language', 'value': 'zh-Hant'}),
    );
    await tester.pumpAndSettle();
    expect(uiLanguage, UiLanguage.zhHant);
    expect(find.text('還沒有標籤'), findsOneWidget);
    expect(find.text('標籤'), findsWidgets);
    expect(find.text('No tags yet'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('首頁'), findsWidgets);
    expect(find.text('繁體中文'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Stored by the core and applied before the first frame of a new start.
    await tester.pumpWidget(const SizedBox.shrink());
    initLanguage(AppLanguage.system);
    expect(uiLanguage, UiLanguage.zhHans);
    store.dispose();
    store = open();
    await tester.runAsync(store.refresh);
    expect(store.setting('language', 'system'), 'zh-Hant');
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('首頁'), findsWidgets);

    // Back to following the system, which is pinned to Simplified Chinese.
    await tester.tap(find.byKey(const ValueKey('nav-profile')));
    await tester.pumpAndSettle();
    await choose(tester, 'system');
    expect(find.text('主页'), findsWidgets);
    expect(find.text('跟随系统'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('following the system uses the device language order', (
    tester,
  ) async {
    phone(tester);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    debugSystemLocales = const [Locale('ja'), Locale('zh', 'TW')];
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    expect(uiLanguage, UiLanguage.zhHant);
    expect(find.text('首頁'), findsWidgets);

    // The device language changes while the app runs.
    debugSystemLocales = const [Locale('en', 'US')];
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    await tester.pumpAndSettle();
    expect(uiLanguage, UiLanguage.en);
    expect(find.text('Home'), findsWidgets);

    // An explicit choice ignores later device changes.
    await tester.runAsync(
      () => store.mutate('setting', {'key': 'language', 'value': 'zh-Hans'}),
    );
    await tester.pumpAndSettle();
    debugSystemLocales = const [Locale('zh', 'HK')];
    tester.platformDispatcher.localesTestValue = const [Locale('zh', 'HK')];
    await tester.pumpAndSettle();
    expect(uiLanguage, UiLanguage.zhHans);
    expect(find.text('主页'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restoring a backup applies its language', (tester) async {
    phone(tester);
    final backup = File('${root.path}/language-backup.json');
    await tester.runAsync(() async {
      await store.mutate('setting', {'key': 'language', 'value': 'en'});
      await store.read('export', {'path': backup.path});
      await store.mutate('setting', {'key': 'language', 'value': 'zh-Hans'});
    });
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('主页'), findsWidgets);
    await tester.runAsync(() => store.mutate('restore', {'path': backup.path}));
    await tester.pumpAndSettle();
    expect(store.setting('language', 'system'), 'en');
    expect(find.text('Home'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('dates, periods and counts read naturally in each language', () {
    final reminder = {
      'before': [1],
      'on_day': true,
      'grace_days': 3,
      'repeat_days': 2,
    };
    initLanguage(AppLanguage.en);
    expect(friendlyDate('2030-01-07'), 'Mon, Jan 7, 2030');
    expect(friendlyDate('2030-01-07', weekday: false), 'Jan 7, 2030');
    expect(relativeDays(1), 'Tomorrow');
    expect(relativeDays(3), 'In 3 days');
    expect(relativeDays(-1), 'Yesterday');
    expect(relativeDays(-2), '2 days overdue');
    expect(cycleLabel({'kind': 'interval', 'days': 14}), 'Every 14 days');
    expect(cycleLabel({'kind': 'interval', 'days': 1}), 'Every 1 day');
    expect(
      reminderSummary(reminder),
      '1 day before · On the day · 3-day grace period · Repeats every 2 days',
    );
    expect(
      reminderSummary({
        'before': [7, 1],
      }),
      '7, 1 days before',
    );
    expect(tr('{n} 条规则', {'n': 1}), '1 rule');
    expect(tr('{n} 条规则', {'n': 2}), '2 rules');
    expect(unitLabel('次'), 'uses');
    expect(phaseLabel('grace'), 'Grace period');

    initLanguage(AppLanguage.zhHant);
    expect(friendlyDate('2030-01-07'), '2030年1月7日 週一');
    expect(relativeDays(3), '3 天後');
    expect(cycleLabel({'kind': 'weekly'}), '每週');
    expect(unitLabel('次'), '次');

    initLanguage(AppLanguage.zhHans);
    expect(friendlyDate('2030-01-07'), '2030年1月7日 周一');
    expect(reminderSummary(reminder), '提前 1 天 · 当天 · 处理窗口 3 天 · 每 2 天重复');
  });

  testWidgets('English text fits the main screens with large text', (
    tester,
  ) async {
    phone(tester, scale: 1.4);
    final today = DateTime.now();
    await tester.runAsync(() async {
      await store.mutate('setting', {'key': 'language', 'value': 'en'});
      await store.mutate('save_project', {'name': 'Subscriptions'});
      await store.mutate('save_tag', {'name': 'Family'});
      await store.mutate('save_rule', {
        'name': 'A fairly long rule name for a phone plan and its balance',
        'tags': [store.tags.single['id']],
        'schedule': {
          'anchor': dateOnly(today.subtract(const Duration(days: 20))),
          'next': dateOnly(today.subtract(const Duration(days: 2))),
          'cycle': {'kind': 'monthly'},
        },
        'reminder': {
          'before': [7, 1],
          'on_day': true,
          'grace_days': 5,
          'repeat_days': null,
        },
        'new_account': {
          'name': 'Phone balance',
          'unit': {'kind': 'count', 'code': '次', 'precision': 0},
          'initial': '10',
          'reference': '20',
          'low': '15',
        },
        'change': '-1',
      });
    });
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    expect(find.textContaining(' · 1 item needs attention'), findsOneWidget);
    expect(find.text('Running low'), findsOneWidget);
    expect(
      find.textContaining('Grace period · 2 days overdue'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Rule detail with its period card, schedule and resource card.
    final rule = store.rules.single['id'] as String;
    await tester.tap(find.byKey(ValueKey('home-All rules-$rule')));
    await tester.pumpAndSettle();
    expect(find.text('Complete and record'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Monthly'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('1 day before · On the day · 5-day grace period'),
      findsNothing,
    );
    expect(
      find.text('7, 1 days before · On the day · 5-day grace period'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('complete-event')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('period-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Mark in progress'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complete-event')));
    await tester.pumpAndSettle();
    expect(find.text('Actual date'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The editor with every section open.
    await tester.tap(find.byKey(const ValueKey('edit-rule')));
    await tester.pumpAndSettle();
    for (final key in ['cycle-menu', 'field-grace', 'change-consume']) {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: key);
    }
    await tester.tap(find.byKey(const ValueKey('cancel-rule')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Projects, the template picker and the profile tab.
    await tester.tap(find.byKey(const ValueKey('nav-projects')));
    await tester.pumpAndSettle();
    expect(find.text('All rules'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('create-rule')).last);
    await tester.pumpAndSettle();
    expect(find.text('Subscriptions and bills'), findsOneWidget);
    expect(find.text('Software subscription'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-profile')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-language')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('open-language')));
    await tester.pumpAndSettle();
    expect(find.text('System default'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('open-language')));
    await tester.pumpAndSettle();
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('繁體中文'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
