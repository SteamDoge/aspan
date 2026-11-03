// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';

import 'package:aspan/data.dart';
import 'package:aspan/editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SpanStore store;
  late Directory root;
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<void> selectPreset(WidgetTester tester, String name) async {
    await tester.runAsync(() => rootBundle.loadString('assets/templates.json'));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openCreator(context, store),
              child: const Text('新增'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('新增'));
    });
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(name), 250);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text(name));
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aspan-editor-');
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
  testWidgets('count template can switch to money without invalid currency', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RuleEditor(
          store: store,
          initial: {
            'name': '次数模板',
            'new_account': {
              'name': '次数',
              'unit': {'kind': 'count', 'code': '次', 'precision': 0},
              'initial': '20',
            },
          },
        ),
      ),
    );
    final type = find.byKey(const ValueKey('account-kind'));
    await tester.ensureVisible(type);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: type, matching: find.text('金额')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final dynamic editor = tester.state(find.byType(RuleEditor));
    final unit = object(editor.draft())['new_account']['unit'];
    expect(unit['kind'], 'money');
    expect(unit['code'], 'CNY');
    expect(unit['precision'], 2);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
  for (final name in ['吃药', '待办']) {
    testWidgets(
      '$name preset creates and completes without a resource account',
      (tester) async {
        await selectPreset(tester, name);
        if (name == '吃药') {
          expect(find.textContaining('目前不支持具体时刻与系统通知'), findsOneWidget);
        }
        final dynamic editor = tester.state(find.byType(RuleEditor));
        final draft = object(editor.draft());
        final today = dateOnly(DateTime.now());
        expect(draft['schedule']['next'], today);
        expect(
          draft['schedule']['cycle']['kind'],
          name == '吃药' ? 'daily' : 'once',
        );
        expect(draft['reminder']['before'], isEmpty);
        expect(draft['reminder']['on_day'], isTrue);
        expect(draft['new_account'], isNull);
        expect(draft['change'], isNull);
        await tester.runAsync(() async {
          await store.mutate('save_rule', draft);
          final id = store.rules.single['id'];
          await store.mutate('event', {
            'rule': id,
            'planned': today,
            'status': 'completed',
          });
        });
        expect(
          store.rules.single['schedule']['next'],
          name == '吃药'
              ? dateOnly(DateTime.now().add(const Duration(days: 1)))
              : null,
        );
        expect(store.state['accounts'], isEmpty);
        expect(store.state['occurrences'].length, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      },
    );
  }
  testWidgets(
    'birthday uses the selected Gregorian date and restores leap day',
    (tester) async {
      await selectPreset(tester, '生日');
      expect(find.textContaining('暂不支持农历生日与系统通知'), findsOneWidget);
      final dynamic editor = tester.state(find.byType(RuleEditor));
      final initial = object(editor.draft());
      expect(initial['schedule']['next'], dateOnly(DateTime.now()));
      expect(initial['schedule']['cycle']['kind'], 'yearly');
      expect(initial['reminder']['before'], [7, 1]);
      expect(initial['reminder']['on_day'], isTrue);
      expect(initial['new_account'], isNull);
      expect(initial['change'], isNull);

      await tester.ensureVisible(find.text('本期事件日期'));
      await tester.tap(find.text('本期事件日期'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byIcon(Icons.edit_outlined),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextFormField),
        ),
        '02/29/2028',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final draft = object(editor.draft());
      expect(draft['schedule']['next'], '2028-02-29');
      expect(draft['schedule'].containsKey('calendar_anchor'), isFalse);
      await tester.runAsync(() async {
        await store.mutate('save_rule', draft);
        final id = store.rules.single['id'];
        for (final next in [
          '2029-02-28',
          '2030-02-28',
          '2031-02-28',
          '2032-02-29',
        ]) {
          final planned = store.rules.single['schedule']['next'];
          await store.api.call(
            'event',
            args: {
              'rule': id,
              'planned': planned,
              'actual': planned,
              'status': 'completed',
            },
            revision: store.revision,
            today: planned as String,
          );
          await store.refresh();
          expect(store.rules.single['schedule']['next'], next);
          expect(
            store.rules.single['schedule']['calendar_anchor'],
            '2028-02-29',
          );
        }
      });
      expect(store.state['accounts'], isEmpty);
      expect(store.state['occurrences'].length, 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
  testWidgets(
    'editing completed one-shot metadata does not create another occurrence',
    (tester) async {
      final today = dateOnly(DateTime.now());
      await tester.runAsync(() async {
        await store.mutate('save_rule', {
          'name': '已完成',
          'schedule': {
            'anchor': today,
            'next': today,
            'cycle': {'kind': 'once'},
          },
        });
        await store.mutate('event', {
          'rule': store.rules.first['id'],
          'planned': today,
          'status': 'completed',
        });
      });
      final original = store.rules.first;
      await tester.pumpWidget(
        MaterialApp(
          home: RuleEditor(store: store, initial: original, editing: true),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('field-name')), '仅改名称');
      final dynamic editor = tester.state(find.byType(RuleEditor));
      final draft = object(editor.draft());
      expect(draft['schedule']['next'], isNull);
      await tester.runAsync(
        () => store.mutate('save_rule', {'id': original['id'], ...draft}),
      );
      expect(store.rules.first['schedule']['next'], isNull);
      expect(store.state['occurrences'].length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
