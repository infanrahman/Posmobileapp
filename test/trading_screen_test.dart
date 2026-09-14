import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/main.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  testWidgets(
    'edit contacts, return a purchase and save a discounted sale on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late PosStore store;
      await tester.runAsync(() async {
        store = await PosStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        await store.addProduct('Water', 'W01', 1000, 10, 'shop');
        await store.addCustomer('Old customer', '123', 'Route 1');
        await store.addSupplier('Old supplier', '456', '', 'Riyadh');
        await store.addPurchase({1: (quantity: 1, cost: 200)}, 'shop', 1, null);
        await tester.pumpWidget(RihlaApp(store: store));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      Future<void> tap(String label) async {
        final finder = find.text(label).last;
        if (finder.evaluate().isEmpty) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -400));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(finder);
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await tester.pumpAndSettle();
      await tap('Customers');
      await tap('Old customer');
      await tap('Edit customer');
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Customer name',
        ),
        'New customer',
      );
      await tap('Save');
      expect(find.text('New customer'), findsOneWidget);
      await tap('More');
      await tap('Suppliers');
      await tap('Old supplier');
      expect(find.text('Edit supplier'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Supplier name',
        ),
        'New supplier',
      );
      await tap('Save');
      expect(find.text('New supplier'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap('Purchases');
      await tap('Old supplier');
      await tap('Return purchase items');
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Confirm only after receiving the supplier refund shown above.',
        ),
        findsOneWidget,
      );
      await tap('Confirm return');
      await tap('cash');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap('Sales');
      await tap('New sale');
      await tester.tap(find.byTooltip('Add one Water'));
      await tester.pumpAndSettle();
      final discount = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Discount (SAR)',
      );
      await tester.ensureVisible(discount);
      await tester.pumpAndSettle();
      await tester.enterText(discount, '1.00');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tap('Split');
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.decoration?.labelText == 'Cash amount (SAR)',
        ),
        '4.00',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.decoration?.labelText == 'Card amount (SAR)',
        ),
        '5.00',
      );
      await tap('Complete sale • SAR 9.00');
      await tester.runAsync(() async {
        expect((await store.customers()).single['name'], 'New customer');
        expect((await store.suppliers()).single['name'], 'New supplier');
        expect((await store.purchases()).single['refunded'], 200);
        expect((await store.sales()).single['discount'], 100);
        expect((await store.sales()).single['total'], 900);
        expect(
          (await store.salePayments(1)).map((row) => row['method']).toSet(),
          {'cash', 'card'},
        );
        expect((await store.products()).single['shop'], 9);
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => store.db.close());
    },
  );
}
