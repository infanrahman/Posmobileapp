import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late PosStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rihla_cashbook_');
    store = await PosStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/cashbook.db',
    );
  });

  tearDown(() async {
    await store.db.close();
    await directory.delete(recursive: true);
  });

  test(
    'cash session totals every cash flow and saves closing variance',
    () async {
      await store.addProduct('Water', 'W01', 200, 10, 'shop', cost: 100);
      await store.addSupplier('Supplier', '', '', 'Riyadh');
      final session = await store.startCashSession('shop', 1000);
      await expectLater(
        store.startCashSession('shop', 0),
        throwsFormatException,
      );

      final sale = await store.checkout({1: 1}, 'shop', null, 0, null);
      final saleLine = (await store.lines(sale)).single;
      final purchase = await store.addPurchase(
        {1: (quantity: 1, cost: 100)},
        'shop',
        1,
        100,
      );
      final purchaseLine = (await store.purchaseLines(purchase)).single;
      await store.addExpense('Fuel', '', 30, 'shop');
      await store.addExpense('Van fuel', '', 999, 'van');
      await store.returnSale(sale, {saleLine['id'] as int: 1});
      await store.returnPurchase(purchase, {purchaseLine['id'] as int: 1});

      final summary = await store.cashSessionSummary(session);
      expect(summary, {
        'opening': 1000,
        'sales_receipts': 200,
        'purchase_refunds': 100,
        'expenses': 30,
        'supplier_payments': 100,
        'sales_refunds': 200,
        'expected': 970,
      });

      await store.closeCashSession(session, 950, 'Short count');
      expect(await store.openCashSession('shop'), isNull);
      final closed = (await store.cashSessionHistory('shop')).single;
      expect(closed['expected'], 970);
      expect(closed['actual'], 950);
      expect(closed['note'], 'Short count');
      await expectLater(
        store.closeCashSession(session, 950, ''),
        throwsFormatException,
      );
      expect(await store.startCashSession('shop', 950), greaterThan(session));
    },
  );

  test('schema 4 database upgrades without losing existing records', () async {
    await store.addProduct('Existing item', 'E01', 100, 4, 'shop');
    await store.db.execute('DROP TABLE cash_sessions');
    await store.db.setVersion(4);
    await store.db.close();

    store = await PosStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/cashbook.db',
    );
    expect(await store.db.getVersion(), 7);
    expect((await store.products()).single['name'], 'Existing item');
    expect(await store.openCashSession('shop'), isNull);
    expect(await store.startCashSession('shop', 0), 1);
  });
}
