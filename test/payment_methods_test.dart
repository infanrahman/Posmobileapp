import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late PosStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rihla_payments_');
    store = await PosStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/payments.db',
    );
  });

  tearDown(() async {
    await store.db.close();
    await directory.delete(recursive: true);
  });

  test('split and named payment methods drive reports and cashbook', () async {
    await store.addProduct('Water', 'W01', 100, 20, 'shop', cost: 40);
    await store.addCustomer('Customer', '', 'Riyadh');
    await store.addSupplier('Supplier', '', '', 'Riyadh');
    final session = await store.startCashSession('shop', 1000);

    final sale = await store.checkout(
      {1: 2},
      'shop',
      null,
      0,
      200,
      paymentBreakdown: {'cash': 50, 'card': 150},
    );
    final creditSale = await store.checkout({1: 1}, 'shop', 1, 0, 0);
    await store.collect(creditSale, 50, method: 'bank');
    await store.addExpense('Fuel', '', 20, 'shop', method: 'cash');
    await store.addExpense('Supplies', '', 30, 'shop', method: 'card');

    final purchase = await store.addPurchase(
      {1: (quantity: 2, cost: 50)},
      'shop',
      1,
      100,
      method: 'bank',
    );
    final purchaseLine = (await store.purchaseLines(purchase)).single;
    await store.returnPurchase(purchase, {
      purchaseLine['id'] as int: 2,
    }, refundMethod: 'bank');
    final saleLine = (await store.lines(sale)).single;
    await store.returnSale(sale, {
      saleLine['id'] as int: 2,
    }, refundMethod: 'card');

    expect(
      (await store.salePayments(sale)).map((row) => row['method']).toSet(),
      {'cash', 'card'},
    );
    expect((await store.purchasePayments(purchase)).single['method'], 'bank');
    expect(
      (await store.db.query('expenses')).map((row) => row['method']).toSet(),
      {'cash', 'card'},
    );
    expect(
      (await store.db.query('sale_returns')).single['refund_method'],
      'card',
    );
    expect(
      (await store.db.query('purchase_returns')).single['refund_method'],
      'bank',
    );
    final report = await store.report(location: 'shop');
    expect(report['cash_received'], 50);
    expect(report['card_received'], 150);
    expect(report['bank_received'], 50);
    final cash = await store.cashSessionSummary(session);
    expect(cash['sales_receipts'], 50);
    expect(cash['expenses'], 20);
    expect(cash['supplier_payments'], 0);
    expect(cash['purchase_refunds'], 0);
    expect(cash['sales_refunds'], 0);
    expect(cash['expected'], 1030);

    await expectLater(
      store.checkout(
        {1: 1},
        'shop',
        null,
        0,
        100,
        paymentBreakdown: {'cash': 99},
      ),
      throwsFormatException,
    );
    expect(await store.sales(), hasLength(2));
  });

  test('schema 5 payment records migrate as cash', () async {
    await store.addProduct('Item', 'I01', 100, 3, 'shop');
    await store.checkout({1: 1}, 'shop', null, 0, null);
    await store.addExpense('Fuel', '', 10, 'shop');
    for (final table in ['payments', 'supplier_payments', 'expenses']) {
      await store.db.execute('ALTER TABLE $table DROP COLUMN method');
    }
    for (final table in ['sale_returns', 'purchase_returns']) {
      await store.db.execute('ALTER TABLE $table DROP COLUMN refund_method');
    }
    await store.db.setVersion(5);
    await store.db.close();

    store = await PosStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/payments.db',
    );
    expect(await store.db.getVersion(), 6);
    expect((await store.salePayments(1)).single['method'], 'cash');
    expect((await store.expenses()).single['method'], 'cash');
    expect(
      (await store.db.rawQuery(
        'PRAGMA table_info(sale_returns)',
      )).map((row) => row['name']),
      contains('refund_method'),
    );
  });
}
