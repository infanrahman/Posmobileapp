import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/main.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('displayed version matches the packaged app version', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: $appVersion+'),
    );
  });
  testWidgets(
    'Arabic persists and shows RTL navigation without changing product names',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late PosStore store;
      final previewKey = GlobalKey();
      await tester.runAsync(() async {
        await (FontLoader(
          'Amiri',
        )..addFont(rootBundle.load('assets/fonts/Amiri-Regular.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        store = await PosStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        await store.addProduct('Sales', 'A01', 100, 4, 'shop');
        await tester.pumpWidget(
          RepaintBoundary(
            key: previewKey,
            child: RihlaApp(store: store),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text(label));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        if (Platform.environment['RIHLA_ARABIC_PREVIEW'] != '1') return;
        final boundary =
            previewKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/arabic-preview').create(recursive: true);
          await File(
            'build/arabic-preview/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpAndSettle();
      await tap('More');
      await tap('Language');
      await tap('العربية');
      await tester.drag(find.byType(ListView).first, const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(find.text('المشتريات'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('المزيد'))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
      await capture('more');
      await tap('المخزون');
      expect(find.text('Sales'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        expect((await store.settings())['language'], 'ar');
        await tester.pumpWidget(
          RepaintBoundary(
            key: previewKey,
            child: RihlaApp(store: store),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text('الرئيسية'), findsOneWidget);
      await tap('المزيد');
      await tap('النسخ الاحتياطي والاستعادة');
      expect(find.text('حفظ نسخة احتياطية'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('backup');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => store.db.close());
    },
  );
}
