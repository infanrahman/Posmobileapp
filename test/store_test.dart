import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late PosStore store;
  setUp(() async {
    store = await PosStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() async {
    await store.db.close();
  });

  test('amounts parse exactly into halalas and reject invalid input', () {
    expect(amount('12.05'), 1205);
    expect(amount('0.1'), 10);
    for (final invalid in ['-1', 'NaN', '1.999', '1e3', '']) {
      expect(() => amount(invalid), throwsFormatException);
    }
  });

  test('cash sale atomically saves lines, tax, stock and payment', () async {
    await store.addProduct('Water', 'W01', 105, 10, 'shop');
    final id = await store.checkout({1: 3}, 'shop', null, 1500, null);
    final sale = (await store.sales()).single;
    expect(sale['subtotal'], 315);
    expect(sale['tax'], 47);
    expect(sale['total'], 362);
    expect(sale['paid'], 362);
    expect((await store.products()).single['shop'], 7);
    expect((await store.lines(id)).single['quantity'], 3);
    expect((await store.db.query('payments')).single['amount'], 362);
  });

  test('overselling rolls back the complete sale', () async {
    await store.addProduct('Water', 'W01', 100, 10, 'shop');
    await store.addProduct('Juice', 'J01', 200, 1, 'shop');
    await expectLater(
      store.checkout({1: 2, 2: 2}, 'shop', null, 0, null),
      throwsFormatException,
    );
    expect(await store.sales(), isEmpty);
    expect(await store.db.query('sale_lines'), isEmpty);
    expect(
      (await store.products()).firstWhere((p) => p['id'] == 1)['shop'],
      10,
    );
  });

  test(
    'shop and van stock transfer preserves total and prevents negatives',
    () async {
      await store.addProduct('Water', 'W01', 100, 10, 'shop');
      await store.transfer(1, 4, 'shop');
      expect((await store.products()).single['shop'], 6);
      expect((await store.products()).single['van'], 4);
      await expectLater(store.transfer(1, 5, 'van'), throwsFormatException);
      await store.checkout({1: 2}, 'van', null, 0, null);
      expect((await store.products()).single['shop'], 6);
      expect((await store.products()).single['van'], 2);
    },
  );

  test(
    'credit requires a customer, collections cannot exceed balance',
    () async {
      await store.addProduct('Water', 'W01', 100, 10, 'shop');
      await expectLater(
        store.checkout({1: 2}, 'shop', null, 0, 0),
        throwsFormatException,
      );
      await store.addCustomer('Corner shop', '+966500000000', 'Riyadh');
      final id = await store.checkout({1: 2}, 'shop', 1, 0, 50);
      expect((await store.customers()).single['balance'], 150);
      await store.collect(id, 100);
      expect((await store.customers()).single['balance'], 50);
      await expectLater(store.collect(id, 51), throwsFormatException);
      await expectLater(store.collect(id, 0), throwsFormatException);
      expect((await store.customers()).single['balance'], 50);
      await store.collect(id, 50);
      expect((await store.customers()).single['balance'], 0);
    },
  );

  test('concurrent sales cannot sell the same last unit', () async {
    await store.addProduct('Water', 'W01', 100, 1, 'shop');
    final results = await Future.wait(
      List.generate(2, (_) async {
        try {
          await store.checkout({1: 1}, 'shop', null, 0, null);
          return true;
        } on FormatException {
          return false;
        }
      }),
    );
    expect(results.where((r) => r).length, 1);
    expect((await store.products()).single['shop'], 0);
    expect((await store.sales()).length, 1);
  });

  test(
    'invalid stock, duplicate SKUs and excessive payments are rejected',
    () async {
      await store.addProduct('Water', 'W01', 100, 10, 'shop');
      await expectLater(
        store.addProduct('Duplicate', 'w01', 100, 5, 'shop'),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        store.receiveStock(1, -1, 'shop'),
        throwsFormatException,
      );
      await expectLater(
        store.checkout({1: 1}, 'shop', null, 0, 101),
        throwsFormatException,
      );
      await expectLater(
        store.checkout({1: 0}, 'shop', null, 0, null),
        throwsFormatException,
      );
      expect((await store.products()).single['shop'], 10);
    },
  );

  test(
    'sale price snapshot remains unchanged when catalog price changes',
    () async {
      await store.addProduct('Water', 'W01', 100, 10, 'shop');
      final id = await store.checkout({1: 2}, 'shop', null, 0, null);
      await store.db.update(
        'products',
        {'price': 999},
        where: 'id=?',
        whereArgs: [1],
      );
      expect((await store.lines(id)).single['price'], 100);
      expect((await store.sales()).single['total'], 200);
    },
  );

  test('database records survive close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp('rihla_test_');
    final path = '${directory.path}/persist.db';
    var disk = await PosStore.open(factory: databaseFactoryFfi, path: path);
    try {
      await disk.addProduct('Milk', 'M01', 700, 5, 'van');
      await disk.checkout({1: 1}, 'van', null, 0, null);
      await disk.saveSettings('Riyadh store', 1500);
      await disk.db.close();
      disk = await PosStore.open(factory: databaseFactoryFfi, path: path);
      expect((await disk.products()).single['van'], 4);
      expect((await disk.sales()).single['total'], 700);
      expect((await disk.settings())['business'], 'Riyadh store');
    } finally {
      await disk.db.close();
      await directory.delete(recursive: true);
    }
  });
}
