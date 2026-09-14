import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/main.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('cashbook opens and closes a shop session on a phone', (
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
      await tester.pumpWidget(
        MaterialApp(
          home: CashbookScreen(store: store, initialLocation: 'shop'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('No open cash session'), findsOneWidget);

    await tester.tap(find.text('Open cash session').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10.00');
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Expected cash'), findsOneWidget);
    expect(find.text('Count and close cash'), findsOneWidget);

    await tester.tap(find.text('Count and close cash'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9.50');
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Variance SAR -0.50'), findsOneWidget);
    late List<DbRow> history;
    await tester.runAsync(() async {
      history = await store.cashSessionHistory('shop');
    });
    expect(history.single['actual'], 950);
    expect(tester.takeException(), isNull);
    await tester.runAsync(store.db.close);
  });
}
