// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:convert';
import 'dart:io';

import 'package:aspan/backup.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'document-provider bytes are staged and cleaned after use or failure',
    () async {
      final bytes = utf8.encode('{"format":"aspan-backup"}');
      final selected = XFile.fromData(bytes, name: 'backup.json');
      late String staged;
      await withBackupFile(selected, (path) async {
        staged = path;
        expect(await File(path).readAsBytes(), bytes);
      });
      expect(File(staged).existsSync(), isFalse);
      await expectLater(
        withBackupFile(selected, (path) async {
          staged = path;
          throw StateError('invalid backup');
        }),
        throwsStateError,
      );
      expect(File(staged).existsSync(), isFalse);
    },
  );
}
