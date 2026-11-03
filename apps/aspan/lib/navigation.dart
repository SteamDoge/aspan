// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';

import 'design.dart';
import 'navigation/liquid_navigation_dock.dart';
import 'navigation/navigation_destination.dart';

/// Fixed ASpan destinations; the two layouts share labels and activation.
class SpanNavigation extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  final bool rail;
  const SpanNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
    this.rail = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final height = LiquidNavigationDock.heightOf(context);
    final radius = BorderRadius.circular(rail ? 28 : 100);
    final buttons = [
      for (var i = 0; i < spanDestinations.length; i++)
        MergeSemantics(
          key: ValueKey('nav-${spanDestinations[i].id}'),
          child: Semantics(
            selected: i == selected,
            child: TextButton(
              onPressed: () => onSelected(i),
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
                foregroundColor: WidgetStatePropertyAll(
                  i == selected ? theme.colorScheme.primary : colors.muted,
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.focused)
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    i == selected
                        ? spanDestinations[i].selectedIcon
                        : spanDestinations[i].icon,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    spanDestinations[i].name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
    if (rail) {
      return Padding(
        key: const ValueKey('desktop-navigation'),
        padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
        child: SizedBox(
          width: 96,
          child: Material(
            color: colors.panel,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: colors.line),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.all_inclusive,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(height: 24),
                  for (var i = 0; i < buttons.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AnimatedContainer(
                        duration: reduced
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        decoration: BoxDecoration(
                          color: i == selected
                              ? colors.soft
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: height,
                          child: buttons[i],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          heightFactor: 1,
          child: LiquidNavigationDock(
            items: spanDestinations,
            selected: spanDestinations[selected].id,
            onOpen: (id) => onSelected(
              spanDestinations.indexWhere(
                (destination) => destination.id == id,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
