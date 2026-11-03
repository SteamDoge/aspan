// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';

import 'package:aspan/app.dart';
import 'package:aspan/data.dart';
import 'package:aspan/design.dart';
import 'package:aspan/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SpanStore store;
  late Directory root;
  tearDown(() async {
    await root.delete(recursive: true);
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aspan-layout-');
    store = SpanStore(
      NativeApi(
        root.path,
        libraryPath:
            Platform.environment['ASPAN_RUST_LIB'] ??
            File('../../target/debug/aspan_bridge.dll').absolute.path,
      ),
    );
    await store.refresh();
    await store.mutate('save_rule', {
      'name': '一个较长的规则名称：手机套餐与资源生命周期',
      'new_account': {
        'name': '手机余额',
        'unit': {'kind': 'money', 'code': 'CNY', 'precision': 2},
        'initial': '100',
      },
    });
  });
  for (final size in [
    const Size(375, 812),
    const Size(812, 375),
    const Size(840, 1000),
    const Size(1100, 800),
  ]) {
    testWidgets('three destinations and real populated lists at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(ASpanApp(store: store));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-navigation')),
        size.width >= 840 ? findsOneWidget : findsNothing,
      );
      for (final id in ['home', 'projects', 'profile']) {
        expect(find.byKey(ValueKey('nav-$id')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('项目').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-projects')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-profile')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });
  }

  testWidgets(
    'resize and theme changes retain search and selected destination',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ASpanApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-projects')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '套餐');
      tester.view.physicalSize = const Size(1100, 800);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('desktop-navigation')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text ??
            tester
                .widget<EditableText>(find.byType(EditableText))
                .controller
                .text,
        '套餐',
      );
      await tester.tap(find.byKey(const ValueKey('nav-profile')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('palette-folio')));
        // Wait for the real SQLite write and store refresh, not a fake UI value.
        await store.refresh();
      });
      await tester.pumpAndSettle();
      expect(store.setting('palette', 'lucent'), 'folio');
      await tester.runAsync(() async {
        await tester.tap(find.text('深色'));
        await store.refresh();
      });
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SpanNavigation));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(
        Theme.of(context).colorScheme.primary,
        paletteColors(SpanPalette.folio, Brightness.dark).$2,
      );
      tester.view.physicalSize = const Size(375, 812);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('desktop-navigation')), findsNothing);
      expect(find.byKey(const ValueKey('page-profile')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-projects')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '套餐',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byType(SpanNavigation), findsNothing);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-projects')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  testWidgets(
    'dock supports large text, safe area, keyboard and reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(320, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: spanTheme(Brightness.dark, palette: SpanPalette.nocturne),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 812),
                textScaler: TextScaler.linear(3.2),
                padding: EdgeInsets.only(bottom: 34),
                highContrast: true,
                disableAnimations: true,
              ),
              child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  bottomNavigationBar: SpanNavigation(
                    selected: selected,
                    onSelected: (value) => setState(() => selected = value),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byKey(const ValueKey('nav-projects'));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(selected, 1);
        final node = tester.getSemantics(button);
        expect(
          node.getSemanticsData().flagsCollection.isSelected.toBoolOrNull(),
          isTrue,
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        for (final filter in tester.widgetList<BackdropFilter>(
          find.byType(BackdropFilter),
        )) {
          expect(filter.enabled, isFalse);
        }
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(812 - 34));
        expect(tester.takeException(), isNull);
        store.dispose();
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Android button scrim follows system theme; gestures stay clear',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final gestures in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: spanTheme(Brightness.light)
                .copyWith(platform: TargetPlatform.android),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(375, 812),
                padding: const EdgeInsets.only(bottom: 24),
                platformBrightness: Brightness.dark,
                systemGestureInsets: gestures
                    ? const EdgeInsets.symmetric(horizontal: 16)
                    : EdgeInsets.zero,
              ),
              child: SpanShell(store: store),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scrim = find.byKey(const ValueKey('navigation-bar-scrim'));
        expect(scrim, gestures ? findsNothing : findsOneWidget);
        if (!gestures) {
          expect(
            tester
                .widget<ColoredBox>(
                  find.descendant(of: scrim, matching: find.byType(ColoredBox)),
                )
                .color,
            const Color(0xCC000000),
          );
        }
        final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find
              .descendant(
                of: find.byType(SpanShell),
                matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
              )
              .first,
        );
        expect(
          region.value.systemNavigationBarIconBrightness,
          gestures ? Brightness.dark : Brightness.light,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  test('all AQ series palettes keep readable primary and secondary text', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    for (final palette in SpanPalette.values) {
      for (final brightness in Brightness.values) {
        final (tokens, accent, text) = paletteColors(palette, brightness);
        for (final surface in [
          tokens.background,
          tokens.backgroundEnd,
          tokens.panel,
          tokens.soft,
        ]) {
          expect(contrast(text, surface), greaterThanOrEqualTo(4.5));
          expect(contrast(tokens.muted, surface), greaterThanOrEqualTo(4.5));
        }
        expect(contrast(accent, tokens.soft), greaterThanOrEqualTo(4.5));
      }
    }
    expect(SpanPalette.parse('unknown'), SpanPalette.lucent);
    store.dispose();
  });
}
