// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// ASpan's fixed destinations; only these fields are consumed by the AQ dock.
class SpanDestination {
  final String id;
  final String? fixedName;
  final IconData icon, selectedIcon;
  const SpanDestination({
    required this.id,
    String? name,
    required this.icon,
    IconData? selectedIcon,
  }) : fixedName = name,
       selectedIcon = selectedIcon ?? icon;

  /// A given name is used as is; ASpan's destinations read their label on
  /// every build so it follows the interface language.
  String get name =>
      fixedName ??
      switch (id) {
        'home' => tr('主页'),
        'projects' => tr('项目'),
        _ => tr('我的'),
      };
}

const spanDestinations = [
  SpanDestination(
    id: 'home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  SpanDestination(
    id: 'projects',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder_rounded,
  ),
  SpanDestination(
    id: 'profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person_rounded,
  ),
];
