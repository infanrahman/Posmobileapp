import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/invoice_pdf.dart';
import 'package:rihla_pos/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('long invoices paginate in both languages', () async {
    for (final language in ['en', 'ar']) {
      final bytes = await createInvoicePdf(
        sale: {
          'id': 12,
          'created': '2026-09-12T09:00:00Z',
          'customer_name': 'متجر الرياض',
          'location': 'van',
          'subtotal': 6000,
          'tax_bps': 0,
          'tax': 0,
          'total': 6000,
          'paid': 6000,
          'returned': 0,
          'refunded': 0,
        },
        lines: List.generate(
          60,
          (i) => {
            'name': 'منتج تجريبي Product ${i + 1}',
            'quantity': 1,
            'price': 100,
            'returned': 0,
          },
        ),
        business: 'Riyadh Trading',
        language: language,
      );
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length,
        greaterThan(1),
      );
      if (Platform.environment['RIHLA_PDF_PREVIEW'] == '1') {
        await Directory('build/pdf-preview').create(recursive: true);
        await File('build/pdf-preview/long-$language.pdf').writeAsBytes(bytes);
      }
    }
  });
  test(
    'saved invoices export offline in English and Arabic with returns',
    () async {
      final store = await PosStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      try {
        await store.addProduct(
          'مياه شرب Water 600 ml',
          'W01',
          105,
          20,
          'shop',
          cost: 40,
        );
        await store.addCustomer('متجر النور', '', 'Riyadh');
        final id = await store.checkout(
          {1: 3},
          'shop',
          1,
          1500,
          150,
          discount: 45,
        );
        await store.returnSale(id, {
          (await store.lines(id)).single['id'] as int: 1,
        });
        final sale = (await store.sales()).single;
        for (final language in ['en', 'ar']) {
          final bytes = await createInvoicePdf(
            sale: sale,
            lines: await store.lines(id),
            business: 'Riyadh Trading - تجارة الرياض',
            language: language,
          );
          expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
          expect(bytes.length, greaterThan(1000));
          if (Platform.environment['RIHLA_PDF_PREVIEW'] == '1') {
            await Directory('build/pdf-preview').create(recursive: true);
            await File(
              'build/pdf-preview/invoice-$language.pdf',
            ).writeAsBytes(bytes);
          }
        }
        expect((await store.sales()).single, sale);
      } finally {
        await store.db.close();
      }
    },
  );

  test('thermal receipt supports long carts and a Phase 1 QR', () async {
    final bytes = await createThermalReceiptPdf(
      sale: {
        'id': 9,
        'created': '2026-09-14T10:00:00Z',
        'subtotal': 10000,
        'tax': 1500,
        'total': 11500,
      },
      lines: List.generate(
        35,
        (index) => {
          'name': 'Product ${index + 1}',
          'quantity': 1,
          'price': 300,
          'discount': 0,
        },
      ),
      business: 'Riyadh Trading',
      language: 'en',
      sellerVat: '310123456789013',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
}
