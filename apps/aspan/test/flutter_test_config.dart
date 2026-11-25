// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:async';
import 'dart:ui';

import 'package:aspan/l10n/l10n.dart';

/// Widget tests assert Simplified Chinese text, so "follow system" resolves to
/// Simplified Chinese here regardless of the machine's locale.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugSystemLocales = const [Locale('zh', 'CN')];
  initLanguage(AppLanguage.system);
  await testMain();
}
