// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'data.dart';

const backupType = XTypeGroup(
  label: 'ASpan 备份',
  extensions: ['json'],
  mimeTypes: ['application/json'],
);

Future<bool> exportBackup(SpanStore store) async {
  final name = 'ASpan-${store.snapshot['today']}-${operationKey()}.json';
  if (!Platform.isAndroid) {
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [backupType],
    );
    if (location == null) return false;
    await store.read('export', {'path': location.path, 'overwrite': true});
    return true;
  }
  // Match Android's Context.cacheDir, which the native saver permits.
  // Dart's systemTemp can instead point at the engine's code_cache directory.
  final temporary = await (await getTemporaryDirectory()).createTemp(
    'aspan-export-',
  );
  try {
    final file = File('${temporary.path}/backup.json');
    await store.read('export', {'path': file.path});
    return await const MethodChannel('cn.aquantum.aspan/backup')
            .invokeMethod<bool>('saveDocument', {
              'name': name,
              'path': file.path,
            }) ??
        false;
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<void> selectBackupFile(Future<void> Function(String) use) async {
  if (!Platform.isAndroid) {
    final file = await openFile(acceptedTypeGroups: [backupType]);
    if (file != null) await withBackupFile(file, use);
    return;
  }
  final path = await const MethodChannel('cn.aquantum.aspan/backup')
      .invokeMethod<String>('openDocument');
  if (path == null) return;
  try {
    await use(path);
  } finally {
    await File(path).delete();
  }
}

// Desktop and test XFiles are staged without changing the runtime path contract.
// Stage the selected file privately and let the existing runtime validate it.
Future<T> withBackupFile<T>(
  XFile selected,
  Future<T> Function(String) use,
) async {
  if (await selected.length() > 50 * 1024 * 1024) {
    throw StateError('备份文件超过 50 MB');
  }
  final temporary = await Directory.systemTemp.createTemp('aspan-import-');
  try {
    final path = '${temporary.path}/backup.json';
    await selected.saveTo(path);
    return await use(path);
  } finally {
    await temporary.delete(recursive: true);
  }
}
