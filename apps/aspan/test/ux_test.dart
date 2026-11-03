// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';

import 'package:aspan/app.dart';
import 'package:aspan/data.dart';
import 'package:aspan/editor.dart';
import 'package:aspan/navigation.dart';
import 'package:aspan/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Interaction regressions for the redesigned flows, backed by the real Rust
/// core so every assertion about balances and periods is the stored result.
void main() {
  late Directory root;
  late SpanStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aspan-ux-');
    store = SpanStore(
      NativeApi(
        root.path,
        libraryPath:
            Platform.environment['ASPAN_RUST_LIB'] ??
            File('../../target/debug/aspan_bridge.dll').absolute.path,
      ),
    );
    await store.refresh();
  });
  tearDown(() async {
    store.dispose();
    await root.delete(recursive: true);
  });

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

  void phone(WidgetTester tester, {double bottomInset = 0}) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 44, bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(top: 44, bottom: bottomInset);
    addTearDown(tester.view.reset);
  }

  testWidgets('editor guards unsaved input and keeps it after cancel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => RuleEditor(
                    store: store,
                    initial: const {'project': null},
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    // Untouched form leaves without asking.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditor), findsNothing);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-name')), '草稿');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditor), findsOneWidget);
    expect(find.text('草稿'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditor), findsNothing);
    expect(store.rules, isEmpty);
  });

  testWidgets('reminder chips and change direction produce core draft fields', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: RuleEditor(
          store: store,
          initial: presetConfig({
            'name': '手机套餐',
            'icon': 'payments',
            'cycle': 'monthly',
            'money': true,
          }),
        ),
      ),
    );
    final dynamic editor = tester.state(find.byType(RuleEditor));
    expect(object(editor.draft())['reminder']['before'], [7, 1]);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('before-30')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('before-30')));
    await tester.ensureVisible(find.byKey(const ValueKey('before-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('before-1')));
    await tester.pump();
    expect(object(editor.draft())['reminder']['before'], [30, 7]);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('change-consume')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('change-consume')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('field-amount')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const ValueKey('field-amount')), '18');
    var draft = object(editor.draft());
    expect(draft['change'], '-18');
    expect(draft['reset'], isNull);

    await tester.tap(find.byKey(const ValueKey('change-reset')));
    await tester.pump();
    draft = object(editor.draft());
    expect(draft['change'], isNull);
    expect(draft['reset'], '18');

    await tester.tap(find.byKey(const ValueKey('change-none')));
    await tester.pump();
    draft = object(editor.draft());
    expect(draft['change'], isNull);
    expect(draft['reset'], isNull);

    // A signed amount is rejected next to the field instead of double-negating.
    await tester.tap(find.byKey(const ValueKey('change-consume')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-amount')), '-18');
    await tester.runAsync(() => editor.save() as Future<void>);
    await tester.pumpAndSettle();
    expect(find.text('只填数值，方向由上方选项决定'), findsOneWidget);
    expect(store.rules, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home quick-complete records the period and the charge once', (
    tester,
  ) async {
    phone(tester, bottomInset: 34);
    final today = dateOnly(DateTime.now());
    final created = await tester.runAsync(
      () => store.mutate('save_rule', {
        'name': '月租',
        'schedule': {
          'anchor': today,
          'next': today,
          'cycle': {'kind': 'monthly'},
        },
        'new_account': {
          'name': '话费',
          'unit': {'kind': 'money', 'code': 'CNY', 'precision': 2},
          'initial': '100',
        },
        'change': '-18',
      }),
    );
    final id = created!['result'] as String;
    final account = store.state['rules'][id]['account'] as String;
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('1 项需要处理'), findsOneWidget);

    await tester.tap(find.byTooltip('完成本期'));
    await tester.pumpAndSettle();
    expect(find.text('完成本期'), findsWidgets);
    expect(find.textContaining('记录 -18.00 CNY'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-event')));
    await until(tester, () => store.state['occurrences'].length == 1);

    expect(store.accountView(account)['formatted'], '82.00');
    expect(store.view(id)['planned'], isNot(today));
    expect(find.textContaining('本期已结束'), findsOneWidget);
    expect(find.text('暂无需要处理的事项'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed period write keeps the sheet and resource choice', (
    tester,
  ) async {
    phone(tester);
    final today = dateOnly(DateTime.now());
    final created = await tester.runAsync(
      () => store.mutate('save_rule', {
        'name': '失败后保留输入',
        'schedule': {
          'anchor': today,
          'next': today,
          'cycle': {'kind': 'monthly'},
        },
        'new_account': {
          'name': '话费',
          'unit': {'kind': 'money', 'code': 'CNY', 'precision': 2},
          'initial': '100',
        },
        'change': '-18',
      }),
    );
    final id = created!['result'] as String;
    final account = store.state['rules'][id]['account'] as String;
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('完成本期'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    // A separate write makes the open decision stale; it must not be replayed.
    await tester.runAsync(
      () => store.mutate('setting', {'key': 'sort', 'value': 'event'}),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-event')));
    await until(
      tester,
      () => find.textContaining('数据已变化').evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('confirm-event')), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(store.state['occurrences'], isEmpty);
    expect(store.accountView(account)['formatted'], '100.00');
    expect(store.view(id)['planned'], today);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('confirm-event')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('projects: long press enters merge selection, back leaves it', (
    tester,
  ) async {
    phone(tester);
    await tester.runAsync(() async {
      for (final name in ['甲', '乙']) {
        await store.mutate('save_rule', {'name': name});
      }
    });
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-projects')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-rule')), findsOneWidget);

    await tester.longPress(find.text('甲'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('select-bar')), findsOneWidget);
    expect(find.text('已选 1 条'), findsOneWidget);
    // The create button gives way to the contextual bar.
    expect(find.byKey(const ValueKey('create-rule')), findsNothing);
    final merge = find.widgetWithText(FilledButton, '合并 1');
    expect(tester.widget<FilledButton>(merge).onPressed, isNull);

    await tester.tap(find.text('乙'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '合并 2'))
          .onPressed,
      isNotNull,
    );

    // System back exits the mode instead of leaving the page.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.byKey(const ValueKey('select-bar')), findsNothing);
    expect(find.byKey(const ValueKey('create-rule')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('last row scrolls fully above the floating dock and home bar', (
    tester,
  ) async {
    phone(tester, bottomInset: 34);
    await tester.runAsync(() async {
      for (var i = 0; i < 14; i++) {
        await store.mutate('save_rule', {'name': '规则 $i'});
      }
    });
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-projects')));
    await tester.pumpAndSettle();
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('规则 13'), 300, scrollable: list);
    await tester.drag(list, const Offset(0, -2000));
    await tester.pumpAndSettle();
    final lastBottom = tester
        .getBottomLeft(
          find.ancestor(
            of: find.text('规则 13'),
            matching: find.byType(RuleTile),
          ),
        )
        .dy;
    final dockTop = tester.getTopLeft(find.byType(SpanNavigation)).dy;
    final fabTop = tester
        .getTopLeft(find.byKey(const ValueKey('create-rule')))
        .dy;
    expect(lastBottom, lessThanOrEqualTo(dockTop));
    expect(lastBottom, lessThanOrEqualTo(fabTop));
    // The dock itself stays clear of the system home indicator.
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('nav-home'))).dy,
      lessThanOrEqualTo(844 - 34),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
