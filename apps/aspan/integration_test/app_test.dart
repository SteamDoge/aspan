// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:aspan/app.dart';
import 'package:aspan/data.dart';
import 'package:aspan/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // These flows assert Simplified Chinese text; "follow system" resolves to
  // it regardless of the device language.
  debugSystemLocales = const [Locale('zh', 'CN')];
  final output = Platform.environment['ASPAN_TEST_OUTPUT'];

  Future<void> capture(GlobalKey boundary, String name) async {
    if (output == null) return;
    await Directory(output).create(recursive: true);
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

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
      expect(find.byKey(const ValueKey('desktop-navigation')), findsOneWidget);
      expect(find.byKey(const ValueKey('page-home')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('create-rule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('blank-rule')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('field-name')),
        '原生验收规则',
      );
      final save = find.byKey(const ValueKey('save-rule'));
      await tester.tap(save);
      await settle(tester, () => store.rules.isNotEmpty);
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
      await tester.tap(find.byKey(const ValueKey('nav-projects')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('folder-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-all')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-profile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-profile')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('open-appearance')));
      await tester.tap(find.byKey(const ValueKey('open-appearance')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('palette-folio')));
      await settle(tester, () => store.setting('palette', 'lucent') == 'folio');
      expect(store.setting('palette', 'lucent'), 'folio');
      await tester.tap(find.text('深色'));
      await settle(tester, () => store.setting('theme', 'system') == 'dark');
      expect(store.setting('theme', 'system'), 'dark');
      await capture(boundary, 'native-settings-dark');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await store.mutate('setting', {'key': 'theme', 'value': 'light'});
      await store.mutate('setting', {'key': 'palette', 'value': 'lucent'});
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();

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
      await capture(boundary, 'native-birthday-preset-list');
      await tester.tap(find.text('生日'));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂不支持农历生日与系统通知'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('field-name')),
        '生日 · 原生验收',
      );
      await tester.pumpAndSettle();
      await capture(boundary, 'native-birthday-editor');
      await tester.tap(save);
      await settle(tester, () => store.rules.length >= 3);
      expect(store.rules.length, 3);
      final birthday = store.rules.firstWhere((r) => r['name'] == '生日 · 原生验收');
      expect(birthday['schedule']['cycle']['kind'], 'yearly');
      expect(birthday['schedule']['next'], dateOnly(DateTime.now()));
      expect(birthday['reminder']['before'], [7, 1]);
      expect(birthday['account'], isNull);
      await tester.ensureVisible(find.text('生日 · 原生验收').first);
      await tester.tap(find.text('生日 · 原生验收').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('complete-event')), findsOneWidget);
      await capture(boundary, 'native-birthday-detail');
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

  testWidgets('sample data screens on phone and desktop', (tester) async {
    final root = await Directory.systemTemp.createTemp('aspan-screens-');
    addTearDown(() => root.delete(recursive: true));
    final store = SpanStore(NativeApi(root.path));
    await store.refresh();
    final now = DateTime.now();
    String day(int offset) => dateOnly(now.add(Duration(days: offset)));
    Future<String> rule(Json value) async =>
        (await store.mutate('save_rule', value))['result'] as String;
    Json money(String name, String initial, {String? low, String? ref}) => {
      'name': name,
      'unit': {'kind': 'money', 'code': 'CNY', 'precision': 2},
      'initial': initial,
      'low': low,
      'reference': ref,
    };
    final phone = (await store.mutate('save_project', {
      'name': '手机卡',
    }))['result'];
    final papers = (await store.mutate('save_project', {
      'name': '证件',
    }))['result'];
    final family = (await store.mutate('save_tag', {
      'name': '家庭',
      'color': '2E7D4F',
    }))['result'];
    final work = (await store.mutate('save_tag', {
      'name': '工作',
      'color': '6D5BD0',
    }))['result'];
    await rule({
      'name': 'VPS 续费',
      'tags': [work],
      'schedule': {
        'anchor': day(-33),
        'next': day(-3),
        'cycle': {'kind': 'monthly'},
      },
      'new_account': money('云余额', '30', low: '50'),
      'change': '-30',
    });
    await rule({
      'name': '主卡月租',
      'project': phone,
      'schedule': {
        'anchor': day(-30),
        'next': day(0),
        'cycle': {'kind': 'monthly'},
      },
      'new_account': money('主卡话费', '150'),
      'change': '-58',
    });
    await rule({
      'name': '信用卡年费',
      'tags': [family],
      'reminder': {
        'before': [30, 7],
        'on_day': true,
        'grace_days': 90,
        'repeat_days': null,
      },
      'schedule': {
        'anchor': day(-370),
        'next': day(-5),
        'cycle': {'kind': 'yearly'},
      },
    });
    await rule({
      'name': '副卡充值保活',
      'project': phone,
      'schedule': {
        'anchor': day(-360),
        'next': day(5),
        'cycle': {'kind': 'restart', 'days': 365},
      },
      'new_account': money('副卡余额', '12.5'),
    });
    await rule({
      'name': '护照有效期',
      'project': papers,
      'pinned': true,
      'reminder': {
        'before': [180, 30],
        'on_day': true,
        'grace_days': 0,
        'repeat_days': null,
      },
      'schedule': {
        'anchor': day(-2900),
        'next': day(752),
        'cycle': {'kind': 'once'},
      },
    });
    final swim = await rule({
      'name': '游泳次卡',
      'tags': [family],
      'schedule': {
        'anchor': day(-60),
        'next': day(70),
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
    await rule({
      'name': '净水器滤芯',
      'schedule': {
        'anchor': day(-120),
        'next': day(60),
        'cycle': {'kind': 'restart', 'days': 180},
      },
    });
    await rule({
      'name': '域名续费',
      'tags': [work],
      'schedule': {
        'anchor': day(-300),
        'next': day(65),
        'cycle': {'kind': 'yearly'},
      },
      'new_account': money('域名账户', '96'),
      'change': '-78',
    });
    for (final key in ['swim-1', 'swim-2', 'swim-3']) {
      await store.mutate('resource', {
        'account': store.state['rules'][swim]['account'],
        'rule': swim,
        'action': 'consume',
        'amount': '1',
        'key': key,
      });
    }
    final boundary = GlobalKey();
    Future<void> show(Size size) async {
      await binding.setSurfaceSize(size);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ASpanApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(const Size(390, 844));
    await capture(boundary, 'phone-home-light');
    await tester.tap(find.byKey(const ValueKey('nav-projects')));
    await tester.pumpAndSettle();
    await capture(boundary, 'phone-projects-light');
    await tester.tap(find.byKey(const ValueKey('folder-all')));
    await tester.pumpAndSettle();
    await capture(boundary, 'phone-all-light');
    await tester.tap(find.text('VPS 续费'));
    await tester.pumpAndSettle();
    await capture(boundary, 'phone-detail-light');
    await tester.tap(find.byKey(const ValueKey('edit-rule')));
    await tester.pumpAndSettle();
    await capture(boundary, 'phone-editor-light');
    await tester.tap(find.byKey(const ValueKey('cancel-rule')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-profile')));
    await tester.pumpAndSettle();
    await capture(boundary, 'phone-settings-light');
    await tester.tap(find.byKey(const ValueKey('nav-home')));
    await tester.pumpAndSettle();
    await store.mutate('setting', {'key': 'theme', 'value': 'dark'});
    await tester.pumpAndSettle();
    await capture(boundary, 'phone-home-dark');
    await tester.tap(find.byTooltip('完成本期').first);
    await tester.pumpAndSettle();
    await capture(boundary, 'phone-complete-sheet-dark');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await store.mutate('setting', {'key': 'palette', 'value': 'folio'});
    await store.mutate('setting', {'key': 'theme', 'value': 'light'});
    await show(const Size(1100, 760));
    await capture(boundary, 'desktop-home-folio');
    await store.mutate('setting', {'key': 'palette', 'value': 'lucent'});
    await tester.tap(find.byKey(const ValueKey('nav-projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('folder-all')));
    await tester.pumpAndSettle();
    await capture(boundary, 'desktop-all-light');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await binding.setSurfaceSize(null);
    store.dispose();
  });
}
