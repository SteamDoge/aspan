// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:aspan/navigation/navigation_destination.dart';
import 'package:aspan/navigation/liquid_navigation_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

List<SpanDestination> destinations() => [
  for (final (id, title, icon) in [
    ('home', '主页', Icons.home_outlined),
    ('projects', '项目', Icons.folder_outlined),
    ('profile', '我的', Icons.person_outline),
  ])
    SpanDestination(id: id, name: title, icon: icon),
];

void main() {
  late List<SpanDestination> items;
  late String selected;
  late List<String> opened;
  late StateSetter change;
  Future<void> pump(
    WidgetTester tester, {
    bool reduced = false,
    bool contrast = false,
    TextDirection direction = TextDirection.ltr,
    double scale = 1,
  }) async {
    items = destinations();
    selected = 'home';
    opened = [];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            disableAnimations: reduced,
            highContrast: contrast,
            textScaler: TextScaler.linear(scale),
          ),
          child: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 350,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      change = setState;
                      return LiquidNavigationDock(
                        items: items,
                        selected: selected,
                        onOpen: (id) {
                          opened.add(id);
                          change(() => selected = id);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder item(String id) => find.byKey(ValueKey('nav-$id'));
  Finder getLens() => find.byKey(const ValueKey('navigation-glass-lens'));

  testWidgets('press lifts and previews; release commits one destination', (
    tester,
  ) async {
    await pump(tester);
    final start = tester.getCenter(getLens());
    final gesture = await tester.startGesture(
      tester.getCenter(item('projects')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(opened, isEmpty);
    expect(tester.getCenter(getLens()).dx, greaterThan(start.dx + 20));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opened, ['projects']);
    expect(
      tester.getCenter(getLens()).dx,
      closeTo(tester.getCenter(item('projects')).dx, 2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a highlighted fallback remains an actionable destination', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(item('home'));
    await tester.pumpAndSettle();
    expect(opened, ['home']);
  });

  testWidgets('drag follows continuously and navigates only on release', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(tester.getCenter(item('home')));
    final middle = tester.getCenter(item('projects'));
    await gesture.moveTo(middle + const Offset(12, 0));
    await tester.pump();
    expect(opened, isEmpty);
    expect(tester.getCenter(getLens()).dx, closeTo(middle.dx + 12, 2));
    await gesture.moveTo(tester.getCenter(item('profile')));
    await tester.pump();
    expect(opened, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opened, ['profile']);
  });

  testWidgets('pointer cancel and release outside the bar do not navigate', (
    tester,
  ) async {
    await pump(tester);
    var gesture = await tester.startGesture(tester.getCenter(item('projects')));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(
      tester.getCenter(getLens()).dx,
      closeTo(tester.getCenter(item('home')).dx, 2),
    );
    gesture = await tester.startGesture(tester.getCenter(item('profile')));
    await gesture.moveBy(const Offset(0, -150));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
  });

  testWidgets(
    'removing a destination during a drag cannot open its replacement',
    (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(item('projects')),
      );
      change(() => items.removeAt(1));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(item('projects'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a second finger cannot commit the first finger preview', (
    tester,
  ) async {
    await pump(tester);
    final first = await tester.startGesture(
      tester.getCenter(item('projects')),
      pointer: 1,
    );
    final second = await tester.startGesture(
      tester.getCenter(item('profile')),
      pointer: 2,
    );
    await second.up();
    expect(opened, isEmpty);
    await first.cancel();
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
  });

  testWidgets('RTL maps the physical right destination to the first ID', (
    tester,
  ) async {
    await pump(tester, direction: TextDirection.rtl);
    expect(
      tester.getCenter(item('home')).dx,
      greaterThan(tester.getCenter(item('profile')).dx),
    );
    await tester.tap(item('projects'));
    await tester.pumpAndSettle();
    expect(opened, ['projects']);
  });

  testWidgets(
    'keyboard activates one focused destination with selected semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, ['projects']);
      expect(find.bySemanticsLabel('项目'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'large text, reduced motion, high contrast and one item remain usable',
    (tester) async {
      await pump(tester, reduced: true, contrast: true, scale: 2.2);
      await tester.tap(item('profile'));
      await tester.pump();
      expect(opened, ['profile']);
      expect(
        find.byKey(const ValueKey('navigation-glass-opaque')),
        findsNWidgets(2),
      );
      change(() => items = [items.last]);
      await tester.pumpAndSettle();
      expect(tester.getSize(item('profile')).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
}
