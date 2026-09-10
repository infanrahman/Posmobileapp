import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/main.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Optional local render. The system font is read only, never bundled in the app.
void main() {
  testWidgets(
    'render phone preview with isolated sample data',
    (tester) async {
      sqfliteFfiInit();
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      late PosStore store;
      await tester.runAsync(() async {
        final font = File(Platform.environment['RIHLA_PREVIEW_FONT']!);
        final loader = FontLoader('Roboto')
          ..addFont(font.readAsBytes().then(ByteData.sublistView));
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        store = await PosStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        await store.saveSettings('Riyadh Trading • Demo', 1500);
        await store.addProduct(
          'Drinking water · 600 ml',
          'W01',
          150,
          120,
          'shop',
        );
        await store.addProduct('Orange juice · 1 L', 'J01', 850, 30, 'shop');
        await store.addProduct('Fresh milk · 2 L', 'M01', 1150, 4, 'shop');
        await store.addCustomer(
          'Al Noor Mini Market',
          '+966 50 000 0000',
          'Al Olaya',
        );
        await store.checkout({1: 24, 2: 6}, 'shop', 1, 1500, 3000);
        await store.checkout({1: 4, 3: 1}, 'shop', null, 1500, null);
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: RihlaApp(store: store),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Future<void> capture(String name) async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await Directory('docs').create(recursive: true);
          await File('docs/$name.png').writeAsBytes(data.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('overview');
      await tester.tap(find.text('Stock').last);
      await tester.pumpAndSettle();
      await capture('inventory');
      debugDisableShadows = true;
      await tester.runAsync(() => store.db.close());
    },
    skip: !Platform.environment.containsKey('RIHLA_PREVIEW_FONT'),
  );
}
