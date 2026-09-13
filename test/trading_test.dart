import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/store.dart';
import 'package:rihla_pos/backup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'backup_test.dart' show editBackup;

void main() {
  sqfliteFfiInit();
  late PosStore store;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rihla_trading_');
    store = await PosStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/db',
    );
    await store.addProduct('Water', 'W01', 105, 10, 'shop', cost: 40);
    await store.addCustomer('Old customer', '123', 'Route 1');
    await store.addSupplier('Old supplier', '456', 'VAT', 'Riyadh');
  });
  tearDown(() async {
    await store.db.close();
    await directory.delete(recursive: true);
  });

  test('editing contacts keeps old invoice snapshots and balances', () async {
    await store.checkout({1: 2}, 'shop', 1, 0, 0);
    await store.addPurchase({1: (quantity: 3, cost: 40)}, 'shop', 1, 20);
    await store.updateCustomer(1, 'New customer', '789', 'Route 2');
    await store.updateSupplier(1, 'New supplier', '987', 'VAT2', 'Jeddah');
    expect((await store.customers()).single['balance'], 210);
    expect((await store.customers()).single['area'], 'Route 2');
    expect((await store.suppliers()).single['balance'], 100);
    expect((await store.suppliers()).single['address'], 'Jeddah');
    expect((await store.sales()).single['customer_name'], 'Old customer');
    expect((await store.purchases()).single['supplier_name'], 'Old supplier');
    await store.checkout({1: 1}, 'shop', 1, 0, null);
    expect((await store.sales()).first['customer_name'], 'New customer');
    await expectLater(
      store.updateCustomer(1, ' ', '', ''),
      throwsFormatException,
    );
    await expectLater(
      store.updateSupplier(999, 'Name', '', '', ''),
      throwsFormatException,
    );
  });

  test(
    'discount, split returns and tax reconcile exactly after price changes',
    () async {
      await store.addProduct('Milk', 'M01', 202, 5, 'shop', cost: 80);
      final id = await store.checkout(
        {1: 3, 2: 2},
        'shop',
        1,
        1500,
        null,
        discount: 103,
      );
      final sale = (await store.sales()).single;
      expect(sale['subtotal'], 616);
      expect(sale['tax'], 92);
      expect(sale['total'], 708);
      expect((await store.report())['gross_profit'], 336);
      final lines = await store.lines(id);
      expect(
        lines.fold<int>(0, (sum, row) => sum + (row['discount'] as int)),
        103,
      );
      await store.updateProduct(1, 'New water', 'W01', 999, 999);
      int refunds = 0;
      for (final line in lines.reversed) {
        for (var i = 0; i < (line['quantity'] as int); i++) {
          refunds += await store.returnSale(id, {line['id'] as int: 1});
        }
      }
      expect(refunds, 708);
      expect((await store.report())['net_sales'], 0);
      expect((await store.report())['sales_tax'], 0);
      expect((await store.report())['gross_profit'], 0);
      expect((await store.customers()).single['balance'], 0);
      await store.restoreBackup(PosBackup.decode(await store.exportBackup()));
    },
  );

  test(
    'discount validation rolls back and full discount supports free sale',
    () async {
      await expectLater(
        store.checkout({1: 1}, 'shop', null, 1500, null, discount: 106),
        throwsFormatException,
      );
      expect(await store.sales(), isEmpty);
      expect((await store.products()).single['shop'], 10);
      final id = await store.checkout(
        {1: 1},
        'shop',
        null,
        1500,
        null,
        discount: 105,
      );
      expect((await store.sales()).single['total'], 0);
      expect(
        await store.returnSale(id, {
          (await store.lines(id)).single['id'] as int: 1,
        }),
        0,
      );
    },
  );

  test('purchase returns reduce debt then record refunds and stock', () async {
    final id = await store.addPurchase(
      {1: (quantity: 5, cost: 100)},
      'van',
      1,
      200,
    );
    final lineId = (await store.purchaseLines(id)).single['id'] as int;
    expect(await store.returnPurchase(id, {lineId: 2}), 0);
    expect((await store.suppliers()).single['balance'], 100);
    await store.paySupplier(id, 100);
    expect(await store.returnPurchase(id, {lineId: 3}), 300);
    expect((await store.suppliers()).single['balance'], 0);
    expect((await store.products()).single['van'], 0);
    expect((await store.report())['purchases'], 0);
    expect((await store.report())['payables'], 0);
    await expectLater(store.paySupplier(id, 1), throwsFormatException);
    await expectLater(
      store.returnPurchase(id, {lineId: 1}),
      throwsFormatException,
    );
    await store.restoreBackup(PosBackup.decode(await store.exportBackup()));
    expect((await store.purchases()).single['refunded'], 300);
  });

  test('purchase return rollback prevents partial stock changes', () async {
    await store.addProduct('Milk', 'M01', 200, 0, 'shop');
    final id = await store.addPurchase(
      {1: (quantity: 2, cost: 40), 2: (quantity: 2, cost: 80)},
      'van',
      null,
      null,
    );
    await store.transfer(2, 2, 'van');
    final before = await store.products();
    final lines = await store.purchaseLines(id);
    await expectLater(
      store.returnPurchase(id, {
        for (final line in lines) line['id'] as int: 1,
      }),
      throwsFormatException,
    );
    expect(await store.products(), before);
    expect((await store.purchases()).single['returned'], 0);
    expect(await store.db.query('purchase_returns'), isEmpty);
  });

  test('v2 backup upgrades in memory and restores prior records', () async {
    await store.checkout({1: 2}, 'shop', 1, 1500, 100);
    await store.addPurchase({1: (quantity: 2, cost: 40)}, 'shop', 1, 0);
    final report = await store.report();
    final legacy = editBackup(await store.exportBackup(), (j) {
      j['database_version'] = 2;
      final tables = j['payload']['tables'] as Map;
      tables.remove('purchase_returns');
      for (final name in ['sales', 'sale_lines']) {
        for (final row in tables[name]) {
          row.remove('discount');
        }
      }
      for (final row in tables['purchases']) {
        row.remove('returned');
        row.remove('refunded');
      }
      for (final row in tables['purchase_lines']) {
        row.remove('returned');
      }
    });
    await store.addExpense('Fuel', '', 100, 'shop');
    await store.restoreBackup(PosBackup.decode(legacy));
    expect(await store.report(), report);
    expect((await store.sales()).single['discount'], 0);
    final damaged = editBackup(await store.exportBackup(), (j) {
      j['payload']['tables']['sale_lines'][0]['discount'] = 10;
    });
    await expectLater(
      store.restoreBackup(PosBackup.decode(damaged)),
      throwsFormatException,
    );
    expect(await store.report(), report);
  });

  test('v2 database upgrades without changing saved transactions', () async {
    await store.checkout({1: 2}, 'shop', 1, 1500, 100);
    await store.addPurchase({1: (quantity: 2, cost: 40)}, 'van', 1, 0);
    await store.saveLanguage('ar');
    final report = await store.report();
    await store.db.execute('DROP TABLE purchase_returns');
    for (final table in ['sales', 'sale_lines']) {
      await store.db.execute('ALTER TABLE $table DROP COLUMN discount');
    }
    await store.db.execute('ALTER TABLE purchases DROP COLUMN returned');
    await store.db.execute('ALTER TABLE purchases DROP COLUMN refunded');
    await store.db.execute('ALTER TABLE purchase_lines DROP COLUMN returned');
    await store.db.setVersion(2);
    await store.db.close();
    store = await PosStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/db',
    );
    expect(await store.db.getVersion(), 3);
    expect(await store.report(), report);
    expect((await store.settings())['language'], 'ar');
    expect((await store.sales()).single['discount'], 0);
    await store.returnPurchase(1, {
      (await store.purchaseLines(1)).single['id'] as int: 1,
    });
    expect((await store.suppliers()).single['balance'], 40);
  });
}
