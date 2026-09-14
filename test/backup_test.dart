import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/backup.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Uint8List editBackup(
  Uint8List bytes,
  void Function(Map<String, dynamic>) edit,
) {
  final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  edit(json);
  json['sha256'] = sha256
      .convert(utf8.encode(jsonEncode(json['payload'])))
      .toString();
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

void main() {
  sqfliteFfiInit();
  late PosStore source;
  late PosStore target;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rihla_backup_test_');
    source = await PosStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/source.db',
    );
    target = await PosStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/target.db',
    );
    await source.saveSettings('Riyadh shop', 1500);
    await source.saveLanguage('ar');
    await source.startCashSession('shop', 500);
    await source.addProduct('Water', 'W01', 105, 12, 'shop', cost: 40);
    await source.addCustomer('Customer', '+966500000000', 'Riyadh');
    await source.addSupplier('Supplier', '', '', 'Riyadh');
    await source.addPurchase({1: (quantity: 4, cost: 45)}, 'van', 1, 100);
    await source.paySupplier(1, 25);
    final sale = await source.checkout({1: 3}, 'shop', 1, 1500, 100);
    await source.collect(sale, 50);
    final line = (await source.lines(sale)).single['id'] as int;
    await source.returnSale(sale, {line: 1});
    await source.returnSale(sale, {line: 2});
    await source.addExpense('Fuel', 'Van delivery', 1200, 'van');
    await source.closeCashSession(1, 500, 'Counted');
    await target.addProduct('Existing target item', 'OLD01', 100, 2, 'shop');
  });
  tearDown(() async {
    await source.db.close();
    await target.db.close();
    await directory.delete(recursive: true);
  });

  test(
    'backup restores every table, refunds, balances and future sales',
    () async {
      final backup = PosBackup.decode(await source.exportBackup());
      expect(backup.business, 'Riyadh shop');
      expect(backup.count('sales'), 1);
      expect(backup.count('cash_sessions'), 1);
      await target.restoreBackup(backup);
      for (final table in backupTables) {
        expect(
          await target.db.query(table),
          await source.db.query(table),
          reason: table,
        );
      }
      expect(await target.report(), await source.report());
      expect((await target.customers()).single['balance'], 0);
      expect((await target.suppliers()).single['balance'], 55);
      final id = await target.checkout({1: 1}, 'van', null, 1500, null);
      expect(id, greaterThan(1));
      expect((await target.products()).single['van'], 3);
    },
  );

  test(
    'malformed JSON, wrong format and damaged checksums are rejected',
    () async {
      expect(
        () => PosBackup.decode(Uint8List.fromList(utf8.encode('not json'))),
        throwsFormatException,
      );
      final bytes = await source.exportBackup();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      json['payload']['tables']['products'][0]['name'] = 'Altered';
      expect(
        () =>
            PosBackup.decode(Uint8List.fromList(utf8.encode(jsonEncode(json)))),
        throwsFormatException,
      );
      expect(
        () => PosBackup.decode(
          editBackup(bytes, (j) => j['format'] = 'other-app'),
        ),
        throwsFormatException,
      );
      expect(
        () => PosBackup.decode(
          editBackup(bytes, (j) => j['database_version'] = 999),
        ),
        throwsFormatException,
      );
    },
  );

  test('schema 4 backup restores with an empty cashbook', () async {
    final legacy = editBackup(await source.exportBackup(), (json) {
      json['database_version'] = 4;
      json['payload']['tables'].remove('cash_sessions');
      for (final name in ['payments', 'supplier_payments', 'expenses']) {
        for (final row in json['payload']['tables'][name]) {
          row.remove('method');
        }
      }
      for (final name in ['sale_returns', 'purchase_returns']) {
        for (final row in json['payload']['tables'][name]) {
          row.remove('refund_method');
        }
      }
    });
    await target.restoreBackup(PosBackup.decode(legacy));
    expect(await target.db.query('cash_sessions'), isEmpty);
    expect((await target.products()).single['name'], 'Water');
  });

  test(
    'missing tables and invalid settings cannot be previewed as valid',
    () async {
      final bytes = await source.exportBackup();
      expect(
        () => PosBackup.decode(
          editBackup(bytes, (j) => j['payload']['tables'].remove('payments')),
        ),
        throwsFormatException,
      );
      expect(
        () => PosBackup.decode(
          editBackup(bytes, (j) => j['payload']['tables']['settings'] = []),
        ),
        throwsFormatException,
      );
      expect(
        () => PosBackup.decode(
          editBackup(
            bytes,
            (j) => j['payload']['tables']['settings'][1]['value'] = '-1',
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'failure after replacement starts rolls back all existing records',
    () async {
      final before = await target.exportBackup();
      final bad = editBackup(await source.exportBackup(), (j) {
        j['payload']['tables']['expenses'][0]['amount'] = -100;
      });
      await expectLater(
        target.restoreBackup(PosBackup.decode(bad)),
        throwsFormatException,
      );
      final original = PosBackup.decode(before);
      for (final table in backupTables) {
        expect(
          await target.db.query(table),
          original.tables[table],
          reason: table,
        );
      }
    },
  );

  test('broken foreign keys roll back restore', () async {
    final bad = editBackup(await source.exportBackup(), (j) {
      j['payload']['tables']['sale_lines'][0]['product_id'] = 9999;
    });
    await expectLater(
      target.restoreBackup(PosBackup.decode(bad)),
      throwsFormatException,
    );
    expect((await target.products()).single['name'], 'Existing target item');
    expect(await target.sales(), isEmpty);
  });

  test(
    'wrong column types and inconsistent financial records are rejected',
    () async {
      final bytes = await source.exportBackup();
      for (final change in <void Function(Map<String, dynamic>)>[
        (j) => j['payload']['tables']['products'][0]['shop'] = '12',
        (j) => j['payload']['tables']['sale_lines'][0]['returned'] = 99,
        (j) => j['payload']['tables']['sales'][0]['total'] = 9999,
        (j) => j['payload']['tables']['supplier_payments'] = [],
        (j) => j['payload']['tables']['payments'][0]['method'] = 'crypto',
      ]) {
        await expectLater(
          target.restoreBackup(PosBackup.decode(editBackup(bytes, change))),
          throwsFormatException,
        );
        expect(
          (await target.products()).single['name'],
          'Existing target item',
        );
      }
    },
  );

  test('backup with no transactions can restore and start trading', () async {
    final empty = await PosStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/empty.db',
    );
    try {
      await target.restoreBackup(PosBackup.decode(await empty.exportBackup()));
      expect(await target.products(), isEmpty);
      expect((await target.settings())['business'], 'My business');
      await target.addProduct('New item', 'NEW', 100, 1, 'shop');
      await target.checkout({1: 1}, 'shop', null, 0, null);
      expect((await target.sales()).single['total'], 100);
    } finally {
      await empty.db.close();
    }
  });
}
