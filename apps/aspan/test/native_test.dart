// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:io';

import 'package:aspan/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late NativeApi api;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aspan-native-');
    api = NativeApi(
      root.path,
      libraryPath:
          Platform.environment['ASPAN_RUST_LIB'] ??
          File('../../target/debug/aspan_bridge.dll').absolute.path,
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('real FFI SQLite merge, resource, copy, reopen and backup', () async {
    var snapshot = object(await api.call('snapshot'));
    Future<dynamic> write(String method, Json args) async {
      final result = await api.call(
        method,
        args: args,
        revision: snapshot['state']['revision'] as int,
      );
      snapshot = object(await api.call('snapshot'));
      return result['result'];
    }

    final a = await write('save_rule', {
      'name': '月费',
      'new_account': {
        'name': '手机余额',
        'unit': {'kind': 'money', 'code': 'CNY', 'precision': 2},
        'initial': '100',
      },
    }) as String;
    final b = await write('save_rule', {'name': '保活'}) as String;
    final group = await write('merge', {
      'rules': [a, b],
      'name': '手机卡',
      'project': null,
    }) as String;
    final aid = snapshot['state']['rules'][a]['account'] as String;
    await write('resource', {
      'account': aid,
      'action': 'add',
      'amount': '50',
      'key': 'topup',
    });
    await write('resource', {
      'account': aid,
      'action': 'consume',
      'amount': '18',
      'key': 'charge',
    });
    await write('resource', {
      'account': aid,
      'action': 'consume',
      'amount': '18',
      'key': 'charge',
    });
    expect(snapshot['account_views'][aid]['formatted'], '132.00');
    final copy = await write('copy', {'id': group}) as String;
    expect(snapshot['state']['groups'][copy]['accounts'][0], isNot(aid));
    final reopened = object(
      await NativeApi(root.path, libraryPath: api.libraryPath).call('snapshot'),
    );
    expect(reopened['state'], snapshot['state']);
    await write('setting', {'key': 'palette', 'value': 'folio'});
    final path = '${root.path}/backup.json';
    await api.call('export', args: {'path': path});
    await write('save_project', {'name': '临时'});
    await api.call(
      'restore',
      args: {'path': path},
      revision: snapshot['state']['revision'] as int,
    );
    final restored = object(await api.call('snapshot'));
    expect(restored['state']['projects'], isEmpty);
    expect(restored['state']['settings']['palette'], 'folio');
    expect(restored['account_views'][aid]['formatted'], '132.00');
  });
  test(
    'controller serializes concurrent writes and preserves manual order',
    () async {
      final store = SpanStore(api);
      await store.refresh();
      await Future.wait([
        store.mutate('save_rule', {'name': 'A'}),
        store.mutate('save_rule', {'name': 'B'}),
      ]);
      expect(store.rules.length, 2);
      final ids = store.rules
          .map((r) => r['id'] as String)
          .toList()
          .reversed
          .toList();
      await store.mutate('reorder', {'ids': ids});
      await store.mutate('setting', {'key': 'sort', 'value': 'event'});
      await store.mutate('setting', {'key': 'sort', 'value': 'manual'});
      expect(store.ordered(store.rules).map((r) => r['id']), ids);
      await store.mutate('setting', {'key': 'theme', 'value': 'dark'});
      await store.mutate('setting', {'key': 'palette', 'value': 'nocturne'});
      final other = SpanStore(api);
      await other.refresh();
      expect(other.setting('theme', 'system'), 'dark');
      expect(other.setting('palette', 'lucent'), 'nocturne');
      store.dispose();
      other.dispose();
    },
  );
}
