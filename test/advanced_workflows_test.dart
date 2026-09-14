import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/backup.dart';
import 'package:rihla_pos/invoice_pdf.dart';
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
    await store.addProduct('Water', 'W01', 100, 10, 'shop', cost: 40);
    await store.addCustomer('Riyadh Market', '', 'Riyadh');
    await store.addSupplier('Main Supplier', '', '', 'Riyadh');
  });

  tearDown(() => store.db.close());

  test(
    'line and invoice discounts are saved and reconcile to totals',
    () async {
      final id = await store.checkout(
        {1: 3},
        'shop',
        1,
        1500,
        100,
        lineDiscounts: {1: 30},
        discount: 20,
      );
      final sale = (await store.sales()).single;
      final line = (await store.lines(id)).single;
      expect(sale['subtotal'], 250);
      expect(sale['discount'], 50);
      expect(sale['tax'], 38);
      expect(sale['total'], 288);
      expect(line['discount'], 50);
    },
  );

  test(
    'cancelling a sale restores stock and removes financial effect',
    () async {
      await store.startCashSession('shop', 500);
      final id = await store.checkout({1: 3}, 'shop', 1, 1500, 200);
      expect((await store.products()).single['shop'], 7);
      final refund = await store.cancelSale(
        id,
        'Customer cancelled order',
        refundMethod: 'cash',
      );
      final sale = (await store.sales()).single;
      expect(refund, 200);
      expect(sale['cancelled'], 1);
      expect(saleBalance(sale), 0);
      expect((await store.products()).single['shop'], 10);
      expect(
        (await store.saleCancellations(id)).single['refund_method'],
        'cash',
      );
      expect((await store.customers()).single['balance'], 0);
      expect((await store.report())['net_sales'], 0);
      final openCash = await store.openCashSession('shop');
      final cash = await store.cashSessionSummary(openCash!['id'] as int);
      expect(cash['sales_receipts'], 200);
      expect(cash['sales_refunds'], 200);
      expect(cash['expected'], 500);
      final statement = await store.customerStatement(1);
      expect(
        statement.any((row) => row['type'] == 'Sale cancellation'),
        isTrue,
      );
      expect(
        statement.fold<int>(
          0,
          (sum, row) => sum + (row['debit'] as int) - (row['credit'] as int),
        ),
        0,
      );
      await expectLater(store.cancelSale(id, 'Again'), throwsFormatException);
    },
  );

  test('statements reconcile customer and supplier balances', () async {
    final sale = await store.checkout({1: 2}, 'shop', 1, 0, 50);
    await store.collect(sale, 25, method: 'bank');
    final customer = await store.customerStatement(1);
    expect(
      customer.fold<int>(
        0,
        (sum, row) => sum + (row['debit'] as int) - (row['credit'] as int),
      ),
      (await store.customers()).single['balance'],
    );

    final purchase = await store.addPurchase(
      {1: (quantity: 2, cost: 40)},
      'shop',
      1,
      20,
    );
    await store.paySupplier(purchase, 10, method: 'card');
    final supplier = await store.supplierStatement(1);
    expect(
      supplier.fold<int>(
        0,
        (sum, row) => sum + (row['debit'] as int) - (row['credit'] as int),
      ),
      (await store.suppliers()).single['balance'],
    );
  });

  test('saved documents, van profiles and settings survive backup', () async {
    await store.saveSettings(
      'Riyadh Trading',
      1500,
      sellerVat: '310123456789013',
      businessAddress: 'Riyadh',
    );
    final van = await store.addVan('Route North', 'Ahmed');
    await store.transfer(1, 1, 'shop');
    await store.checkout({1: 1}, 'van', null, 1500, null, vanId: van);
    final vanSale = (await store.sales()).single;
    expect(vanSale['van_name'], 'Route North');
    expect(vanSale['salesperson'], 'Ahmed');
    final document = await store.saveDocument(
      kind: 'quotation',
      name: 'Quote 1',
      partyId: 1,
      partyName: 'Riyadh Market',
      location: 'shop',
      payload: {
        'cart': {'1': 2},
      },
      total: 200,
    );
    expect(
      store.documentPayload(
        (await store.savedDocuments('quotation')).single,
      )['cart'],
      {'1': 2},
    );
    await store.finishDocument(document, 44);
    expect(
      (await store.savedDocuments('quotation')).single['status'],
      'converted',
    );
    expect((await store.vans()).any((row) => row['id'] == van), isTrue);

    final restored = await PosStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    try {
      await restored.restoreBackup(
        PosBackup.decode(await store.exportBackup()),
      );
      expect((await restored.settings())['seller_vat'], '310123456789013');
      expect((await restored.vans()).length, 2);
      expect(
        (await restored.savedDocuments('quotation')).single['linked_id'],
        44,
      );
    } finally {
      await restored.db.close();
    }
  });

  test('ZATCA QR contains the five Phase 1 TLV fields', () {
    final qr = zatcaQrData(
      seller: 'Riyadh Trading',
      vatNumber: '310123456789013',
      timestamp: '2026-09-14T10:00:00Z',
      total: 11500,
      tax: 1500,
    );
    final bytes = base64Decode(qr);
    final values = <int, String>{};
    for (var index = 0; index < bytes.length;) {
      final tag = bytes[index++];
      final length = bytes[index++];
      values[tag] = utf8.decode(bytes.sublist(index, index + length));
      index += length;
    }
    expect(values, {
      1: 'Riyadh Trading',
      2: '310123456789013',
      3: '2026-09-14T10:00:00.000Z',
      4: '115.00',
      5: '15.00',
    });
  });
}
