import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/main.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  testWidgets('phone layout, inventory and checkout work together', (
    tester,
  ) async {
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
      await store.addProduct('Water bottle', 'W01', 200, 10, 'shop');
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(RihlaApp(store: store));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Your business, at a glance.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Stock').last);
    await tester.pumpAndSettle();
    expect(find.text('Water bottle'), findsOneWidget);
    expect(find.text('10 units'), findsOneWidget);
    await tester.tap(find.text('Sales').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('New sale'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add one Water bottle'));
    await tester.pumpAndSettle();
    final complete = find.text('Complete sale • SAR 2.00');
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(complete);
    await tester.runAsync(() async {
      await tester.tap(complete);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('Walk-in customer'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('Purchases'), findsOneWidget);
    expect(find.text('Suppliers'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Reports'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Business reports'), findsOneWidget);
    expect(find.text('Net sales'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      expect((await store.products()).single['shop'], 9);
      await store.db.close();
    });
  });
}
