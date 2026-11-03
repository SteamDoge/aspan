// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';

/// ASpan's fixed destinations; only these fields are consumed by the AQ dock.
class SpanDestination {
  final String id, name;
  final IconData icon, selectedIcon;
  const SpanDestination({
    required this.id,
    required this.name,
    required this.icon,
    IconData? selectedIcon,
  }) : selectedIcon = selectedIcon ?? icon;
}

const spanDestinations = [
  SpanDestination(
    id: 'home',
    name: '主页',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  SpanDestination(
    id: 'projects',
    name: '项目',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder_rounded,
  ),
  SpanDestination(
    id: 'profile',
    name: '我的',
    icon: Icons.person_outline,
    selectedIcon: Icons.person_rounded,
  ),
];
