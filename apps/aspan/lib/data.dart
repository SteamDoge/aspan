// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef Json = Map<String, dynamic>;
const releaseVersion = String.fromEnvironment(
  'ASPAN_VERSION',
  defaultValue: '开发工作区',
);

class AspanError implements Exception {
  final String message;
  final String code;
  const AspanError(this.message, [this.code = 'operation_failed']);
  @override
  String toString() => message;
}

String dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String operationKey() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
Json object(dynamic value) => Map<String, dynamic>.from(value as Map);
List<Json> objects(dynamic value) => (value as Map).values.map(object).toList();

class NativeApi {
  final String root;
  final String libraryPath;
  NativeApi(this.root, {String? libraryPath})
    : libraryPath =
          libraryPath ??
          (!kReleaseMode ? Platform.environment['ASPAN_RUST_LIB'] : null) ??
          (Platform.isWindows
              ? '${File(Platform.resolvedExecutable).parent.path}/aspan_bridge.dll'
              : 'libaspan_bridge.so');
  Future<dynamic> call(
    String method, {
    Json args = const {},
    int? revision,
    String? today,
  }) async {
    final request = jsonEncode({
      'root': root,
      'method': method,
      'args': args,
      'revision': revision,
      'today': today ?? dateOnly(DateTime.now()),
    });
    final path = libraryPath;
    final envelope = await Isolate.run(
      () => object(jsonDecode(invokeNative(path, request))),
    );
    if (envelope['ok'] != true) {
      throw AspanError(
        envelope['error']?.toString() ?? '操作失败',
        envelope['code']?.toString() ?? 'operation_failed',
      );
    }
    return envelope['data'];
  }
}

String invokeNative(String path, String request) {
  final library = DynamicLibrary.open(path);
  final invoke = library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('aspan_invoke_json');
  final free = library
      .lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('aspan_free_json');
  final input = request.toNativeUtf8();
  Pointer<Utf8>? output;
  try {
    output = invoke(input);
    if (output.address == 0) {
      throw StateError('原生核心未返回结果');
    }
    return output.toDartString();
  } finally {
    malloc.free(input);
    if (output != null && output.address != 0) {
      free(output);
    }
  }
}

class SpanStore extends ChangeNotifier {
  final NativeApi api;
  Json snapshot = {};
  Future<void> _pending = Future.value();
  SpanStore(this.api);
  Object? lastRefreshError;
  bool _disposed = false;
  int get revision => state['revision'] as int;
  Json get state => snapshot['state'] as Json;
  List<Json> rules = [], groups = [], projects = [], tags = [], accounts = [];
  Json view(String id) => object(snapshot['views'][id]);
  Json accountView(String id) => object(snapshot['account_views'][id]);
  String setting(String key, String fallback) =>
      state['settings'][key] as String? ?? fallback;
  Future<void> _refresh() async {
    try {
      final next = object(await api.call('snapshot'));
      if (_disposed) return;
      snapshot = next;
      rules = objects(state['rules'])
          .where((r) => r['deleted'] != true)
          .toList();
      groups = objects(state['groups'])
          .where((g) => g['deleted'] != true)
          .toList();
      projects = objects(state['projects'])
        ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
      tags = objects(state['tags']);
      accounts = objects(state['accounts']);
      lastRefreshError = null;
    } catch (error) {
      if (!_disposed) lastRefreshError = error;
      rethrow;
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> refresh() {
    final result = _pending.then((_) => _refresh());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<dynamic> read(String method, [Json args = const {}]) =>
      api.call(method, args: args);
  Future<dynamic> mutate(String method, Json args, {int? baseRevision}) {
    final result = _pending.then((_) async {
      if (lastRefreshError != null) {
        throw const AspanError('数据尚未刷新，请先刷新本地数据再操作');
      }
      dynamic response;
      try {
        response = await api.call(
          method,
          args: args,
          revision: baseRevision ?? revision,
        );
      } catch (_) {
        try {
          await _refresh();
        } catch (_) {
          /* Preserve the write error. */
        }
        rethrow;
      }
      // A committed write remains successful even if the following read fails.
      try {
        await _refresh();
      } catch (_) {
        /* The shell displays stale data. */
      }
      return response;
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  List<Json> ordered(List<Json> items) {
    final sort = setting('sort', 'manual');
    final descending = setting('descending', 'false') == 'true';
    final membersByGroup = <String, List<Json>>{};
    for (final r in rules) {
      final group = r['group'] as String?;
      if (group != null) (membersByGroup[group] ??= []).add(r);
    }
    dynamic value(Json item) {
      if (sort == 'manual') {
        return item['order'];
      }
      final members = item.containsKey('accounts')
          ? membersByGroup[item['id']] ?? <Json>[]
          : [item];
      final values =
          members
              .map(
                (r) =>
                    view(r['id'] as String)[sort == 'reminder'
                        ? 'next_reminder'
                        : sort == 'remaining'
                        ? 'remaining_days'
                        : 'planned'],
              )
              .where((v) => v != null)
              .toList()
            ..sort(
              (a, b) => a is int
                  ? a.compareTo(b as int)
                  : a.toString().compareTo(b.toString()),
            );
      return values.isEmpty ? null : values.first;
    }

    final keys = {for (final item in items) item['id']: value(item)};
    return items..sort((a, b) {
      final av = keys[a['id']], bv = keys[b['id']];
      if (av == null && bv != null) {
        return 1;
      }
      if (av != null && bv == null) {
        return -1;
      }
      var result = av == null
          ? 0
          : av is int
          ? av.compareTo(bv as int)
          : av.toString().compareTo(bv.toString());
      if (sort != 'manual' && descending) {
        result = -result;
      }
      if (result == 0) {
        result = (a['order'] as int).compareTo(b['order'] as int);
      }
      return result == 0
          ? a['id'].toString().compareTo(b['id'].toString())
          : result;
    });
  }
}
