import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/report_export.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'products save editable reorder levels and reject invalid levels',
    () async {
      final store = await PosStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(store.db.close);

      await store.addProduct(
        'Water',
        'W01',
        200,
        4,
        'shop',
        cost: 100,
        reorderLevel: 10,
      );
      expect((await store.products()).single['reorder_level'], 10);

      await store.updateProduct(1, 'Water', 'W01', 200, 100, reorderLevel: 3);
      expect((await store.products()).single['reorder_level'], 3);
      await expectLater(
        store.updateProduct(1, 'Water', 'W01', 200, 100, reorderLevel: -1),
        throwsFormatException,
      );
    },
  );

  test(
    'schema 6 products migrate with the previous warning threshold',
    () async {
      final directory = await Directory.systemTemp.createTemp('rihla_reorder_');
      final path = '${directory.path}/schema6.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (db, version) async {
            await db.execute('''CREATE TABLE products (
            id INTEGER PRIMARY KEY, name TEXT NOT NULL,
            sku TEXT NOT NULL UNIQUE, price INTEGER NOT NULL,
            cost INTEGER NOT NULL DEFAULT 0,
            shop INTEGER NOT NULL DEFAULT 0, van INTEGER NOT NULL DEFAULT 0,
            barcode TEXT NOT NULL DEFAULT '')''');
            await db.insert('products', {
              'name': 'Legacy item',
              'sku': 'OLD01',
              'price': 500,
              'cost': 200,
              'shop': 5,
              'van': 1,
            });
          },
        ),
      );
      await legacy.close();

      final upgraded = await PosStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      try {
        expect((await upgraded.products()).single['reorder_level'], 6);
      } finally {
        await upgraded.db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('replenishment CSV contains quantities, costs and safe text', () {
    final bytes = reorderListCsv(
      [
        {
          'name': '=Water',
          'sku': 'W01',
          'shop': 4,
          'reorder_level': 10,
          'cost': 125,
        },
      ],
      location: 'shop',
      translate: (value) => value,
    );
    final csv = utf8.decode(bytes);
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    expect(csv, contains('"Current stock","Reorder level","Suggested order"'));
    expect(csv, contains('"\'=Water","W01","4","10","6","1.25","7.50"'));
  });
}
