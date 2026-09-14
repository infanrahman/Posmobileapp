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

  test(
    'purchases update stock, cost and supplier balance atomically',
    () async {
      await store.addProduct('Water', 'W01', 150, 2, 'shop', cost: 50);
      await store.addSupplier(
        'Riyadh Wholesale',
        '+966500000001',
        '310000000000003',
        'Riyadh',
      );

      final purchase = await store.addPurchase(
        {1: (quantity: 3, cost: 75)},
        'van',
        1,
        100,
      );

      final product = (await store.products()).single;
      expect(product['shop'], 2);
      expect(product['van'], 3);
      expect(product['cost'], 75);
      expect((await store.suppliers()).single['balance'], 125);
      expect((await store.purchaseLines(purchase)).single['quantity'], 3);

      await store.paySupplier(purchase, 125);
      expect((await store.suppliers()).single['balance'], 0);
      expect(
        (await store.db.query(
          'supplier_payments',
        )).map((payment) => payment['amount']),
        [100, 125],
      );
      await expectLater(store.paySupplier(purchase, 1), throwsFormatException);
    },
  );

  test('credit purchase requires a supplier and rolls back stock', () async {
    await store.addProduct('Water', 'W01', 150, 2, 'shop', cost: 50);

    await expectLater(
      store.addPurchase({1: (quantity: 3, cost: 75)}, 'shop', null, 0),
      throwsFormatException,
    );

    expect(await store.purchases(), isEmpty);
    final product = (await store.products()).single;
    expect(product['shop'], 2);
    expect(product['cost'], 50);
  });

  test('partial returns restore stock and settle credit and refunds', () async {
    await store.addProduct('Water', 'W01', 100, 10, 'shop', cost: 40);
    await store.addCustomer('Corner shop', '+966500000000', 'Riyadh');
    final sale = await store.checkout({1: 3}, 'shop', 1, 1500, 150);
    final line = (await store.lines(sale)).single;

    expect(await store.returnSale(sale, {line['id'] as int: 1}), 0);
    expect((await store.products()).single['shop'], 8);
    expect((await store.customers()).single['balance'], 80);

    expect(await store.returnSale(sale, {line['id'] as int: 2}), 150);
    final returnedSale = (await store.sales()).single;
    expect(returnedSale['returned'], 345);
    expect(returnedSale['refunded'], 150);
    expect((await store.products()).single['shop'], 10);
    expect((await store.customers()).single['balance'], 0);
    await expectLater(
      store.returnSale(sale, {line['id'] as int: 1}),
      throwsFormatException,
    );
  });

  test('reports use saved costs, returns, expenses and balances', () async {
    await store.addProduct('Juice', 'J01', 200, 5, 'shop', cost: 80);
    await store.addCustomer('Mini market', '', 'Riyadh');
    final sale = await store.checkout({1: 3}, 'shop', 1, 0, 200);
    final line = (await store.lines(sale)).single;
    await store.returnSale(sale, {line['id'] as int: 1});
    await store.addExpense('Fuel', 'Van delivery', 50, 'van');

    final report = await store.report();
    expect(report['net_sales'], 400);
    expect(report['gross_profit'], 240);
    expect(report['expenses'], 50);
    expect(report['receivables'], 200);
    expect(report['stock_value'], 240);
  });

  test(
    'stock adjustments reduce only available stock and keep a reason',
    () async {
      await store.addProduct('Dates', 'D01', 200, 5, 'shop', cost: 100);

      await store.adjustStock(1, 2, 'shop', 'Damaged: crushed box');
      expect((await store.products()).single['shop'], 3);
      final adjustment = (await store.stockAdjustments(1)).single;
      expect(adjustment['quantity'], -2);
      expect(adjustment['location'], 'shop');
      expect(adjustment['reason'], 'Adjustment: Damaged: crushed box');

      await expectLater(
        store.adjustStock(1, 4, 'shop', 'Missing: count'),
        throwsFormatException,
      );
      expect((await store.products()).single['shop'], 3);
      expect(await store.stockAdjustments(1), hasLength(1));
    },
  );

  test('reports filter invoice and expense dates and stock location', () async {
    await store.addProduct('Shop item', 'S01', 200, 5, 'shop', cost: 100);
    await store.addProduct('Van item', 'V01', 100, 5, 'van', cost: 50);
    final shopSale = await store.checkout({1: 1}, 'shop', null, 0, null);
    final vanSale = await store.checkout({2: 1}, 'van', null, 0, null);
    await store.addExpense('Rent', '', 30, 'shop');
    await store.addExpense('Fuel', '', 40, 'van');
    await store.db.update(
      'sales',
      {'created': '2026-01-05T12:00:00.000Z'},
      where: 'id=?',
      whereArgs: [shopSale],
    );
    await store.db.update(
      'sales',
      {'created': '2026-02-05T12:00:00.000Z'},
      where: 'id=?',
      whereArgs: [vanSale],
    );
    final expenses = await store.expenses();
    await store.db.update(
      'expenses',
      {'created': '2026-01-06T12:00:00.000Z'},
      where: 'id=?',
      whereArgs: [expenses.last['id']],
    );
    await store.db.update(
      'expenses',
      {'created': '2026-02-06T12:00:00.000Z'},
      where: 'id=?',
      whereArgs: [expenses.first['id']],
    );

    final report = await store.report(
      start: DateTime.utc(2026, 1),
      end: DateTime.utc(2026, 2),
      location: 'shop',
    );
    expect(report['net_sales'], 200);
    expect(report['gross_profit'], 100);
    expect(report['expenses'], 30);
    expect(report['stock_value'], 400);
  });

  test('version 1 database upgrades without losing product data', () async {
    final directory = await Directory.systemTemp.createTemp('rihla_upgrade_');
    final path = '${directory.path}/upgrade.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            '''CREATE TABLE products (
            id INTEGER PRIMARY KEY, name TEXT NOT NULL,
            sku TEXT NOT NULL UNIQUE, price INTEGER NOT NULL,
            shop INTEGER NOT NULL DEFAULT 0, van INTEGER NOT NULL DEFAULT 0)''',
          );
          await db.execute('''CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT, created TEXT NOT NULL,
            customer_id INTEGER, customer_name TEXT NOT NULL,
            location TEXT NOT NULL, subtotal INTEGER NOT NULL,
            tax INTEGER NOT NULL, total INTEGER NOT NULL,
            paid INTEGER NOT NULL, tax_bps INTEGER NOT NULL)''');
          await db.execute('''CREATE TABLE sale_lines (
            id INTEGER PRIMARY KEY, sale_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL, name TEXT NOT NULL,
            quantity INTEGER NOT NULL, price INTEGER NOT NULL)''');
          await db.insert('products', {
            'name': 'Legacy item',
            'sku': 'OLD01',
            'price': 500,
            'shop': 4,
            'van': 1,
          });
        },
      ),
    );
    await legacy.close();

    var upgraded = await PosStore.open(factory: databaseFactoryFfi, path: path);
    try {
      final product = (await upgraded.products()).single;
      expect(product['name'], 'Legacy item');
      expect(product['shop'], 4);
      expect(product['cost'], 0);
      expect(await upgraded.suppliers(), isEmpty);
      expect(
        (await upgraded.db.rawQuery(
          'PRAGMA table_info(sales)',
        )).map((column) => column['name']),
        containsAll(['returned', 'refunded']),
      );
    } finally {
      await upgraded.db.close();
      await directory.delete(recursive: true);
    }
  });

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
