// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';

import 'package:aspan/app.dart';
import 'package:aspan/data.dart';
import 'package:aspan/design.dart';
import 'package:aspan/editor.dart';
import 'package:aspan/navigation.dart';
import 'package:aspan/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Interaction regressions for the notes-style flows, backed by the real
/// Rust core so every assertion about balances and periods is the stored
/// result.
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

  Future<void> openFolder(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(const ValueKey('nav-projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('folder-$key')));
    await tester.pumpAndSettle();
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
    final cancel = find.byKey(const ValueKey('cancel-rule'));
    final dialogCancel = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('取消'),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    // Untouched form leaves without asking.
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditor), findsNothing);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-name')), '草稿');
    await tester.pump();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(dialogCancel);
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditor), findsOneWidget);
    expect(find.text('草稿'), findsOneWidget);

    // System back is guarded the same way.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
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

    await tester.ensureVisible(find.byKey(const ValueKey('before-30')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('before-30')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('before-1')));
    await tester.pump();
    expect(object(editor.draft())['reminder']['before'], [30, 7]);

    await tester.ensureVisible(find.byKey(const ValueKey('change-consume')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('change-consume')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('field-amount')));
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

    // The cycle is chosen from a menu row.
    await tester.ensureVisible(find.byKey(const ValueKey('cycle-menu')));
    await tester.tap(find.byKey(const ValueKey('cycle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cycle-restart')));
    await tester.pumpAndSettle();
    expect(object(editor.draft())['schedule']['cycle'], {
      'kind': 'restart',
      'days': 365,
    });
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
    expect(find.textContaining('1 项需要处理'), findsOneWidget);
    expect(find.textContaining(RegExp('^全部规则 ')), findsOneWidget);

    await tester.tap(find.byTooltip('完成本期'));
    await tester.pumpAndSettle();
    expect(find.text('完成本期'), findsWidgets);
    expect(find.textContaining('记录 -18.00 CNY'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-event')));
    await until(tester, () => store.state['occurrences'].length == 1);

    expect(store.accountView(account)['formatted'], '82.00');
    expect(store.view(id)['planned'], isNot(today));
    expect(find.textContaining('本期已结束'), findsOneWidget);
    expect(find.textContaining('暂无需要处理的事项'), findsOneWidget);
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

  testWidgets('home lists every rule by due date, grouped or one place', (
    tester,
  ) async {
    phone(tester, bottomInset: 34);
    String inDays(int days) =>
        dateOnly(DateTime.now().add(Duration(days: days)));
    Map<String, dynamic> dated(String name, int days) => {
      'name': name,
      'schedule': {
        'anchor': inDays(days),
        'next': inDays(days),
        'cycle': {'kind': 'yearly'},
      },
    };
    late String folder, tag, far, near, undated, pinned;
    await tester.runAsync(() async {
      folder = (await store.mutate('save_project', {'name': '证件'}))['result'];
      tag = (await store.mutate('save_tag', {'name': '每年'}))['result'];
      far = (await store.mutate('save_rule', {
        ...dated('远的', 200),
        'project': folder,
      }))['result'];
      near = (await store.mutate('save_rule', {
        ...dated('近的', 20),
        'tags': [tag],
      }))['result'];
      undated = (await store.mutate('save_rule', {'name': '无日期'}))['result'];
      pinned = (await store.mutate('save_rule', {
        ...dated('置顶的', 300),
        'pinned': true,
      }))['result'];
    });
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();

    // Every rule is listed; nearest due first, undated last, pinned on top.
    double top(String section, String id) =>
        tester.getTopLeft(find.byKey(ValueKey('home-$section-$id'))).dy;
    expect(find.textContaining(RegExp('^全部规则 ')), findsOneWidget);
    expect(top('置顶', pinned), lessThan(top('全部规则', near)));
    expect(top('全部规则', near), lessThan(top('全部规则', far)));
    expect(top('全部规则', far), lessThan(top('全部规则', undated)));
    expect(find.textContaining('条规则'), findsNothing);

    // The menu offers every layout and stores the choice in the Rust core.
    Future<void> menu(String label) async {
      await tester.tap(find.byKey(const ValueKey('home-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const ValueKey('home-menu')));
    await tester.pumpAndSettle();
    for (final label in ['全部规则，按到期时间', '按文件夹分组', '按标签分组', '只看一个文件夹…']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('按文件夹分组'));
    await until(tester, () => store.setting('home', 'due') == 'project');
    expect(find.byKey(ValueKey('home-证件-$far')), findsOneWidget);
    expect(find.byKey(ValueKey('home-未归类-$near')), findsOneWidget);
    expect(top('证件', far), lessThan(top('未归类', near)));

    await menu('按标签分组');
    await until(tester, () => store.setting('home', 'due') == 'tag');
    expect(find.byKey(ValueKey('home-#每年-$near')), findsOneWidget);
    expect(find.byKey(ValueKey('home-无标签-$far')), findsOneWidget);

    // One folder is picked from a sheet.
    await menu('只看一个文件夹…');
    await tester.tap(find.byKey(ValueKey('home-place-$folder')));
    await until(
      tester,
      () => store.setting('home', 'due') == 'project:$folder',
    );
    expect(find.byKey(ValueKey('home-证件-$far')), findsOneWidget);
    expect(find.text('近的'), findsNothing);
    expect(find.text('无日期'), findsNothing);
    expect(find.text('只看：证件'), findsNothing);
    await menu('只看：证件');
    expect(find.byKey(ValueKey('home-place-$folder')), findsOneWidget);
    await tester.tapAt(const Offset(20, 100));
    await tester.pumpAndSettle();

    // Rust refuses places that do not exist; a stale snapshot value would
    // still show everything rather than an empty home.
    Object? refused;
    await tester.runAsync(() async {
      try {
        await store.mutate('setting', {'key': 'home', 'value': 'tag:missing'});
      } catch (error) {
        refused = error;
      }
    });
    expect(refused, isNotNull);
    store.state['settings']['home'] = 'tag:missing';
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('home-全部规则-$undated')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelled new folder writes and reports nothing', (
    tester,
  ) async {
    phone(tester, bottomInset: 34);
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('已创建文件夹'), findsNothing);
    expect(store.projects, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dock tabs; folders and tags push above the dock and back', (
    tester,
  ) async {
    phone(tester, bottomInset: 34);
    await tester.runAsync(() async {
      await store.mutate('save_project', {'name': '证件'});
      await store.mutate('save_rule', {'name': '未归类的一条'});
    });
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-home')), findsOneWidget);
    expect(find.byType(SpanNavigation), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-projects')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-projects')), findsOneWidget);
    final project = store.projects.single['id'] as String;
    await tester.tap(find.byKey(ValueKey('folder-project-$project')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-project')), findsOneWidget);
    expect(find.text('文件夹是空的'), findsOneWidget);
    // A pushed list covers the dock and offers its own compose toolbar.
    expect(find.byType(SpanNavigation), findsNothing);
    expect(find.byType(SpanToolbar), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-projects')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-inbox')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-inbox')), findsOneWidget);
    expect(find.text('未归类的一条'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-profile')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('select mode from the menu or a long press; back leaves it', (
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
    await openFolder(tester, 'all');
    expect(find.byKey(const ValueKey('create-rule')), findsOneWidget);

    // Long press opens the context menu; "选择" starts with that row.
    await tester.longPress(find.text('甲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('select-bar')), findsOneWidget);
    expect(find.text('已选 1 条'), findsOneWidget);
    // The compose button gives way to the selection toolbar.
    expect(find.byKey(const ValueKey('create-rule')), findsNothing);
    final merge = find.byKey(const ValueKey('merge-selected'));
    expect(tester.widget<TextButton>(merge).onPressed, isNull);

    await tester.tap(find.text('乙'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(merge).onPressed, isNotNull);
    expect(find.text('合并 2'), findsOneWidget);

    // System back exits the mode instead of leaving the list.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.byKey(const ValueKey('select-bar')), findsNothing);
    expect(find.byKey(const ValueKey('page-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('create-rule')), findsOneWidget);

    // The menu offers the same mode.
    await tester.tap(find.byKey(const ValueKey('entries-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    expect(find.text('选择要合并的规则'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reorder mode moves an entry and keeps the manual order', (
    tester,
  ) async {
    phone(tester);
    await tester.runAsync(() async {
      for (final name in ['一', '二', '三']) {
        await store.mutate('save_rule', {'name': name});
      }
      await store.mutate('setting', {'key': 'sort', 'value': 'event'});
    });
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    await openFolder(tester, 'inbox');
    await tester.tap(find.byKey(const ValueKey('entries-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整顺序'));
    await until(tester, () => store.setting('sort', '') == 'manual');
    expect(find.byKey(const ValueKey('reorder-bar')), findsOneWidget);
    final before = store.ordered([...store.rules]).map((r) => r['name']);
    expect(before, ['一', '二', '三']);
    await tester.tap(find.byTooltip('下移').first);
    await until(
      tester,
      () => store.ordered([...store.rules]).first['name'] == '二',
    );
    expect(store.ordered([...store.rules]).map((r) => r['name']), [
      '二',
      '一',
      '三',
    ]);
    await tester.tap(find.byKey(const ValueKey('reorder-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reorder-bar')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rows use progress bars; last row clears the dock and toolbar', (
    tester,
  ) async {
    phone(tester, bottomInset: 34);
    final now = DateTime.now();
    await tester.runAsync(() async {
      for (var i = 0; i < 14; i++) {
        await store.mutate('save_rule', {
          'name': '规则 $i',
          'reminder': {
            'before': [7],
            'on_day': true,
            'grace_days': 5,
            'repeat_days': null,
          },
          'schedule': {
            'anchor': dateOnly(now.subtract(const Duration(days: 10))),
            'next': dateOnly(now),
            'cycle': {'kind': 'once'},
          },
        });
      }
    });
    await tester.pumpWidget(ASpanApp(store: store));
    await tester.pumpAndSettle();
    // Progress is a segmented timeline under each row (normal, reminder and
    // processing window in real proportion); no rings or round buttons.
    final timelines = tester.widgetList<TimelineBar>(find.byType(TimelineBar));
    expect(timelines, isNotEmpty);
    for (final bar in timelines) {
      expect(bar.compact, isTrue);
      expect(bar.segments!['reminder'] as num, greaterThan(0));
      expect(bar.segments!['grace'] as num, greaterThan(0));
    }
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    expect(find.byTooltip('完成本期'), findsWidgets);

    Future<void> scrollToEnd() async {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
      await tester.pumpAndSettle();
    }

    // The bottom-most row once the list rests at its end.
    double lastBottom() => tester
        .widgetList(find.byType(RuleRow))
        .map((w) => tester.getBottomLeft(find.byWidget(w)).dy)
        .reduce((a, b) => a > b ? a : b);

    await scrollToEnd();
    final dockTop = tester.getTopLeft(find.byType(SpanNavigation)).dy;
    expect(lastBottom(), lessThanOrEqualTo(dockTop));
    // The dock itself stays clear of the system home indicator.
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('nav-home'))).dy,
      lessThanOrEqualTo(844 - 34),
    );

    await openFolder(tester, 'all');
    await scrollToEnd();
    final toolbarTop = tester.getTopLeft(find.byType(SpanToolbar)).dy;
    expect(lastBottom(), lessThanOrEqualTo(toolbarTop));
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('create-rule'))).dy,
      lessThanOrEqualTo(844 - 34),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
