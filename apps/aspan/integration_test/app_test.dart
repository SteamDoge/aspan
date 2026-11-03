// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:aspan/app.dart';
import 'package:aspan/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native creator, birthday, resource account, navigation and persistence',
    (tester) async {
      await binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => binding.setSurfaceSize(null));
      final root = await Directory.systemTemp.createTemp('aspan-integration-');
      addTearDown(() => root.delete(recursive: true));
      final store = SpanStore(NativeApi(root.path));
      await store.refresh();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ASpanApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      for (final id in ['home', 'projects', 'profile']) {
        expect(find.byKey(ValueKey('nav-$id')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('create-rule')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('空白创建'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('field-name')),
        '原生验收规则',
      );
      final save = find.byKey(const ValueKey('save-rule'));
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      for (var i = 0; i < 40 && store.rules.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(store.rules.length, 1);
      expect(find.text('原生验收规则'), findsWidgets);
      expect(tester.takeException(), isNull);
      await store.mutate('save_rule', {
        'name': '游泳次卡 · 到期与次数独立',
        'schedule': {
          'anchor': dateOnly(DateTime.now()),
          'next': dateOnly(DateTime.now().add(const Duration(days: 30))),
          'cycle': {'kind': 'once'},
        },
        'new_account': {
          'name': '游泳次数',
          'unit': {'kind': 'count', 'code': '次', 'precision': 0},
          'initial': '20',
          'reference': '20',
          'low': '3',
        },
      });
      final card = store.rules.firstWhere(
        (r) => r['name'].toString().startsWith('游泳'),
      );
      await store.mutate('resource', {
        'account': card['account'],
        'rule': card['id'],
        'action': 'consume',
        'amount': '1',
        'key': 'native-swim',
      });
      expect(store.accountView(card['account'] as String)['formatted'], '19');
      await tester.pumpAndSettle();
      await tester.tap(find.text('项目').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-projects')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-profile')), findsOneWidget);
      await tester.tap(find.text('主页').last);
      await tester.pumpAndSettle();
      final output = Platform.environment['ASPAN_TEST_OUTPUT'];
      Future<void> capture(String name) async {
        if (output == null) return;
        await Directory(output).create(recursive: true);
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await capture('windows-aq-home');
      await tester.tap(find.byKey(const ValueKey('nav-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('palette-folio')));
      for (
        var i = 0;
        i < 40 && store.setting('palette', 'lucent') != 'folio';
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(store.setting('palette', 'lucent'), 'folio');
      await tester.tap(find.text('深色'));
      for (
        var i = 0;
        i < 40 && store.setting('theme', 'system') != 'dark';
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(store.setting('theme', 'system'), 'dark');
      await capture('windows-aq-appearance-dark');
      await binding.setSurfaceSize(const Size(375, 812));
      await tester.pumpAndSettle();
      await capture('windows-aq-mobile-appearance');
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await store.mutate('setting', {'key': 'theme', 'value': 'light'});
      await store.mutate('setting', {'key': 'palette', 'value': 'lucent'});
      await tester.pumpAndSettle();
      await capture('windows-aq-mobile-home');
      await binding.setSurfaceSize(const Size(1100, 800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('create-rule')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('生日'),
        250,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await capture('native-birthday-preset-list');
      await tester.tap(find.text('生日'));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂不支持农历生日与系统通知'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('field-name')),
        '生日 · 原生验收',
      );
      await tester.pumpAndSettle();
      await capture('native-birthday-editor');
      await tester.scrollUntilVisible(
        save,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      for (var i = 0; i < 40 && store.rules.length < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(store.rules.length, 3);
      final birthday = store.rules.firstWhere((r) => r['name'] == '生日 · 原生验收');
      expect(birthday['schedule']['cycle']['kind'], 'yearly');
      expect(birthday['schedule']['next'], dateOnly(DateTime.now()));
      expect(birthday['reminder']['before'], [7, 1]);
      expect(birthday['account'], isNull);
      await tester.ensureVisible(find.text('生日 · 原生验收'));
      await tester.tap(find.text('生日 · 原生验收'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('complete-event')), findsOneWidget);
      await capture('native-birthday-detail');
      expect(tester.takeException(), isNull);

      final reopened = SpanStore(NativeApi(root.path));
      await reopened.refresh();
      expect(reopened.rules.length, 3);
      final reopenedBirthday = reopened.rules.firstWhere(
        (r) => r['id'] == birthday['id'],
      );
      expect(reopenedBirthday['name'], '生日 · 原生验收');
      expect(reopenedBirthday['schedule']['cycle']['kind'], 'yearly');
      expect(
        reopenedBirthday['schedule']['next'],
        birthday['schedule']['next'],
      );
      expect(reopenedBirthday['reminder']['before'], [7, 1]);
      expect(reopenedBirthday['account'], isNull);
      expect(
        reopened.accountView(card['account'] as String)['formatted'],
        '19',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      reopened.dispose();
    },
  );
}
