// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';

import 'package:aspan/app.dart';
import 'package:aspan/data.dart';
import 'package:aspan/details.dart';
import 'package:aspan/editor.dart';
import 'package:aspan/entries.dart';
import 'package:aspan/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingApi extends NativeApi {
  FailingApi(super.root, {super.libraryPath});
  bool failSnapshot = false, failAfterWrite = false, failWrite = false;
  @override
  Future<dynamic> call(
    String method, {
    Json args = const {},
    int? revision,
    String? today,
  }) async {
    if (method == 'snapshot' && failSnapshot) throw const AspanError('刷新暂不可用');
    if (method != 'snapshot' && failWrite) throw const AspanError('原始业务错误');
    final result = await super.call(
      method,
      args: args,
      revision: revision,
      today: today,
    );
    if (method != 'snapshot' && failAfterWrite) failSnapshot = true;
    return result;
  }
}

void main() {
  late Directory root;
  late FailingApi api;
  late SpanStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aspan-review-regression-');
    api = FailingApi(
      root.path,
      libraryPath:
          Platform.environment['ASPAN_RUST_LIB'] ??
          File('../../target/debug/aspan_bridge.dll').absolute.path,
    );
    store = SpanStore(api);
    await store.refresh();
  });
  tearDown(() async {
    store.dispose();
    await root.delete(recursive: true);
  });

  test(
    'committed create stays successful when refresh fails and retry is blocked',
    () async {
      api.failAfterWrite = true;
      final response = await store.mutate('save_rule', {'name': '只创建一次'});
      expect(response['result'], isA<String>());
      expect(store.lastRefreshError, isNotNull);
      await expectLater(
        store.mutate('save_rule', {'name': '不应重试'}),
        throwsA(isA<AspanError>()),
      );
      api.failSnapshot = false;
      await store.refresh();
      expect(store.rules.length, 1);
    },
  );

  test(
    'failed recovery refresh preserves original write error and queue recovers',
    () async {
      api.failWrite = true;
      api.failSnapshot = true;
      await expectLater(
        store.mutate('save_rule', {'name': '失败'}),
        throwsA(
          isA<AspanError>().having((e) => e.message, 'message', '原始业务错误'),
        ),
      );
      api.failWrite = false;
      api.failSnapshot = false;
      await store.refresh();
      await store.mutate('save_rule', {'name': '队列恢复'});
      expect(store.rules.length, 1);
    },
  );

  testWidgets('stale editor cannot overwrite an external edit after refresh', (
    tester,
  ) async {
    final created = await tester.runAsync(
      () => store.mutate('save_rule', {'name': '原规则'}),
    );
    final id = created['result'] as String;
    await tester.pumpWidget(
      MaterialApp(
        home: RuleEditor(
          store: store,
          initial: object(store.state['rules'][id]),
          editing: true,
        ),
      ),
    );
    await tester.runAsync(() async {
      await api.call(
        'save_rule',
        args: {'id': id, 'name': '另一个实例'},
        revision: store.revision,
      );
      await store.refresh();
      final dynamic editor = tester.state(find.byType(RuleEditor));
      await editor.save();
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('数据已变化'), findsOneWidget);
    expect(store.state['rules'][id]['name'], '另一个实例');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refresh failures are visible and Material widgets are Chinese', (
    tester,
  ) async {
    await tester.pumpWidget(ASpanApp(store: store));
    api.failSnapshot = true;
    await tester.runAsync(() async {
      try {
        await store.refresh();
      } catch (_) {}
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('数据未刷新'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    final context = tester.element(find.byType(SpanShell));
    expect(MaterialLocalizations.of(context).okButtonLabel, '确定');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('future anchor cannot open an invalid event date picker', (
    tester,
  ) async {
    final today = DateTime.now();
    final tomorrow = dateOnly(DateTime(today.year, today.month, today.day + 1));
    final created = await tester.runAsync(
      () => store.mutate('save_rule', {
        'name': '未来',
        'schedule': {
          'anchor': tomorrow,
          'next': tomorrow,
          'cycle': {'kind': 'once'},
        },
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RuleDetail(store: store, id: created['result'] as String),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('complete-event')));
    await tester.pumpAndSettle();
    expect(find.textContaining('周期尚未开始'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'blank editor enables dates and validates integers next to input',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RuleEditor(store: store, initial: const {'project': null}),
        ),
      );
      final dynamic editor = tester.state(find.byType(RuleEditor));
      expect(editor.draft()['schedule'], isNotNull);
      expect(formatUnits(-9223372036854775808, 2), '-92233720368547758.08');
      await tester.enterText(find.byKey(const ValueKey('field-name')), '输入校验');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('field-grace')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byKey(const ValueKey('field-grace')), 'abc');
      await tester.runAsync(() => editor.save() as Future<void>);
      await tester.pumpAndSettle();
      expect(find.text('请输入 0—36500 之间的整数'), findsOneWidget);
      expect(store.rules, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('merge conflict requires an explicit balance selection', (
    tester,
  ) async {
    final ids = <String>[];
    await tester.runAsync(() async {
      for (final balance in ['100', '50']) {
        final created = await store.mutate('save_rule', {
          'name': '余额 $balance',
          'new_account': {
            'name': '账户 $balance',
            'unit': {'kind': 'money', 'code': 'CNY', 'precision': 2},
            'initial': balance,
          },
        });
        ids.add(created['result'] as String);
      }
    });
    Future<void>? operation;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                operation = mergeDialog(context, store, ids);
              },
              child: const Text('合并测试'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('合并测试'));
    for (
      var i = 0;
      i < 100 && find.byType(AlertDialog).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认合并'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('账户 50'));

    await tester.pumpAndSettle();
    await tester.tap(find.text('确认合并'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 100 && store.groups.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(store.groups.length, 1);
    await tester.runAsync(() => operation!);
    expect(store.groups.length, 1);
    final authority =
        (store.groups.single['accounts'] as List).single as String;
    expect(store.accountView(authority)['formatted'], '50.00');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'large histories construct one bounded page and retain access to later records',
    (tester) async {
      final items = List.generate(5000, (i) => <String, dynamic>{'id': '$i'});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PagedItems(
                items: items,
                itemBuilder: (item) => Text('记录 ${item['id']}'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('记录 49'), findsOneWidget);
      expect(find.text('记录 50'), findsNothing);
      await tester.ensureVisible(find.byTooltip('下一页'));
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('记录 50'), findsOneWidget);
      expect(find.text('记录 0'), findsNothing);
    },
  );
}
