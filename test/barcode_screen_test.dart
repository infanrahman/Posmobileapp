import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rihla_pos/barcode_screen.dart';
import 'package:rihla_pos/main.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestCamera extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  bool denied = false;
  int starts = 0, stops = 0;
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> pause() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> setFocusPoint(Offset position) async {}
  void detect(List<String> codes) => captures.add(
    BarcodeCapture(
      barcodes: codes.map((code) => Barcode(rawValue: code)).toList(),
    ),
  );
}

void main() {
  sqfliteFfiInit();
  late TestCamera camera;
  late MobileScannerPlatform previous;
  setUp(() {
    previous = MobileScannerPlatform.instance;
    camera = TestCamera();
    MobileScannerPlatform.instance = camera;
  });
  tearDown(() async {
    MobileScannerPlatform.instance = previous;
    await camera.captures.close();
  });
  testWidgets(
    'camera scans add one sale item, reject unknown codes and open purchase details',
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
        await store.addProduct(
          'Water',
          'W01',
          100,
          1,
          'shop',
          cost: 40,
          barcode: '123456789012',
        );
        await tester.pumpWidget(RihlaApp(store: store));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(target);
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> scan(List<String> codes, {bool duplicate = false}) async {
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tap(find.byTooltip('Scan barcode'));
        expect(camera.captures.hasListener, isTrue);
        await tester.runAsync(() async {
          camera.detect(codes);
          if (duplicate) camera.detect(codes);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BarcodeScreen), findsNothing);
      }

      await tester.pumpAndSettle();
      await tap(find.text('Sales').last);
      await tap(find.text('New sale'));
      await tap(find.byTooltip('Scan barcode'));
      await tester.runAsync(() async {
        camera.detect(['111', '222']);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Show one barcode at a time.'), findsOneWidget);
      final stops = camera.stops;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(camera.stops, greaterThan(stops));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        camera.detect(['0123456789012']);
        camera.detect(['0123456789012']);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(BarcodeScreen), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('New sale'), findsOneWidget);
      await scan(['unknown']);
      expect(
        find.text(
          'No product matches this code. Add its barcode in Stock first.',
        ),
        findsOneWidget,
      );
      await scan(['123456789012'], duplicate: true);
      expect(
        find.text('No more stock available at this location.'),
        findsOneWidget,
      );
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tap(find.text('Complete sale • SAR 1.00'));
      await tap(find.text('More'));
      await tap(find.text('Purchases'));
      await tap(find.text('New purchase'));
      await scan(['123456789012']);
      expect(find.text('Purchase Water'), findsOneWidget);
      await tap(find.text('Save'));
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tap(find.text('Save purchase • SAR 0.40'));
      await tester.runAsync(() async {
        expect((await store.sales()).single['total'], 100);
        expect((await store.purchases()).single['total'], 40);
        expect((await store.products()).single['shop'], 1);
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(() => store.db.close());
    },
  );

  testWidgets(
    'camera denied supports manual entry and cancellation without mutation',
    (tester) async {
      camera.denied = true;
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await scanBarcode(context);
                },
                child: const Text('Open scanner'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open scanner'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Camera unavailable.'), findsOneWidget);
      await tester.tap(find.text('Enter code manually'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '00123456');
      await tester.tap(find.text('Use code'));
      await tester.pumpAndSettle();
      expect(result, '00123456');
      await tester.tap(find.text('Open scanner'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
