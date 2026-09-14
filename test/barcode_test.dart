import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/barcode.dart';
import 'package:rihla_pos/backup.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'backup_test.dart' show editBackup;

void main() {
  sqfliteFfiInit();
  test('codes preserve leading zeroes and unify UPC-A with EAN-13', () {
    expect(normalizeBarcode(' 00123456 '), '00123456');
    expect(normalizeBarcode('0123456789012'), '123456789012');
    expect(normalizeBarcode('Case-sensitive'), 'Case-sensitive');
    expect(() => normalizeBarcode('a\nb'), throwsFormatException);
    expect(() => normalizeBarcode('a' * 129), throwsFormatException);
  });
  test(
    'lookup accepts exact barcode or SKU, and rejects ambiguous matches',
    () {
      final products = [
        {'id': 1, 'sku': 'W01', 'barcode': '123456789012'},
        {'id': 2, 'sku': '00001', 'barcode': ''},
        {'id': 3, 'sku': 'unrelated' * 20, 'barcode': ''},
      ];
      expect(productForBarcode(products, '0123456789012')['id'], 1);
      expect(productForBarcode(products, 'w01')['id'], 1);
      expect(productForBarcode(products, '00001')['id'], 2);
      expect(() => productForBarcode(products, '1'), throwsFormatException);
      expect(
        () => productForBarcode(products, 'https://example.com'),
        throwsFormatException,
      );
      products.add({'id': 4, 'sku': '123456789012', 'barcode': ''});
      expect(
        () => productForBarcode(products, '123456789012'),
        throwsFormatException,
      );
    },
  );

  late PosStore store;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rihla_barcodes_');
    store = await PosStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/db',
    );
  });
  tearDown(() async {
    await store.db.close();
    await directory.delete(recursive: true);
  });
  test('optional barcodes are unique and survive edits and backups', () async {
    await store.addProduct(
      'Water',
      'W01',
      100,
      2,
      'shop',
      barcode: '0123456789012',
    );
    await store.addProduct('Milk', 'M01', 200, 3, 'shop');
    await store.addProduct('Juice', 'J01', 300, 0, 'van');
    await expectLater(
      store.updateProduct(2, 'Milk', 'M01', 200, 0, barcode: '123456789012'),
      throwsA(isA<DatabaseException>()),
    );
    await store.updateProduct(1, 'New water', 'W01', 150, 20);
    expect(
      (await store.products()).firstWhere((p) => p['id'] == 1)['barcode'],
      '123456789012',
    );
    final bytes = await store.exportBackup();
    await store.updateProduct(1, 'New water', 'W01', 150, 20, barcode: '');
    await store.restoreBackup(PosBackup.decode(bytes));
    expect(
      productForBarcode(await store.products(), '0123456789012')['name'],
      'New water',
    );
    final broken = editBackup(bytes, (j) {
      final rows = j['payload']['tables']['products'] as List;
      for (final row in rows) {
        row['barcode'] = '123456789012';
      }
    });
    await expectLater(
      store.restoreBackup(PosBackup.decode(broken)),
      throwsFormatException,
    );
    expect((await store.products()).length, 3);
  });
  test(
    'schema 3 data and backups upgrade without losing transactions',
    () async {
      await store.addProduct('Water', 'W01', 100, 3, 'shop');
      await store.checkout({1: 1}, 'shop', null, 0, null, discount: 10);
      final report = await store.report();
      final legacy = editBackup(await store.exportBackup(), (j) {
        j['database_version'] = 3;
        j['payload']['tables'].remove('cash_sessions');
        for (final row in j['payload']['tables']['products']) {
          row.remove('barcode');
        }
      });
      await store.db.execute('DROP TABLE cash_sessions');
      await store.db.execute('DROP INDEX product_barcode_unique');
      await store.db.execute('ALTER TABLE products DROP COLUMN barcode');
      await store.db.setVersion(3);
      await store.db.close();
      store = await PosStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/db',
      );
      expect(await store.db.getVersion(), 5);
      expect(await store.report(), report);
      await store.updateProduct(1, 'Changed', 'W01', 100, 0, barcode: '123');
      await store.restoreBackup(PosBackup.decode(legacy));
      expect((await store.products()).single['barcode'], '');
      expect((await store.products()).single['name'], 'Water');
      expect(await store.report(), report);
    },
  );
}
