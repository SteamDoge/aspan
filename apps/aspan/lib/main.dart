// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data.dart';
import 'design.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind system bars on every Android version (15+ enforces it); the
  // shell and each scrollable consume the reported insets themselves.
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  try {
    final root =
        (!kReleaseMode ? Platform.environment['ASPAN_DATA'] : null) ??
        '${(await getApplicationSupportDirectory()).path}/ASpan/v1';
    final store = SpanStore(NativeApi(root));
    await store.refresh();
    runApp(ASpanApp(store: store));
  } catch (error) {
    // The stored preference is unreadable here, so follow the device.
    initLanguage(AppLanguage.system);
    runApp(
      MaterialApp(
        locale: uiLanguage.locale,
        supportedLocales: supportedUiLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: spanTheme(Brightness.light),
        darkTheme: spanTheme(Brightness.dark),
        home: Scaffold(
          body: SafeArea(
            child: EmptyState(
              tr('ASpan 无法打开'),
              message: tr('原数据保留，未做任何修改。\n{error}', {
                'error': errorMessage(error),
              }),
              icon: Icons.error_outline,
            ),
          ),
        ),
      ),
    );
  }
}
