import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'store.dart';

Future<Uint8List> createInvoicePdf({
  required DbRow sale,
  required List<DbRow> lines,
  required String business,
  required String language,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Amiri-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Amiri-Bold.ttf'),
  );
  final ar = language == 'ar';
  String label(String en, String arabic) => ar ? arabic : en;
  String cash(int value) =>
      'SAR ${NumberFormat('#,##0.00').format(value / 100)}';
  final direction = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final invoice = 'INV-${sale['id'].toString().padLeft(5, '0')}';
  final document = pw.Document(title: invoice, author: business);
  pw.Widget text(String value, {bool strong = false, double size = 12}) =>
      pw.Text(
        value,
        textDirection: RegExp(r'[\u0600-\u06FF]').hasMatch(value)
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        style: pw.TextStyle(font: strong ? bold : regular, fontSize: size),
      );
  pw.Widget total(String title, int value, {bool strong = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        text(title, strong: strong),
        text(cash(value), strong: strong),
      ],
    ),
  );
  final headers = [
    label('Item', 'الصنف'),
    label('Qty', 'الكمية'),
    label('Unit price', 'سعر الوحدة'),
    label('Returned', 'المرتجع'),
    label('Line total', 'إجمالي الصنف'),
  ];
  pw.TableRow row(List<String> values, {bool header = false}) => pw.TableRow(
    repeat: header,
    decoration: header
        ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE7F3EF))
        : null,
    children: (ar ? values.reversed : values)
        .map(
          (value) => pw.Padding(
            padding: const pw.EdgeInsets.all(7),
            child: text(value, strong: header, size: 11),
          ),
        )
        .toList(),
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      textDirection: direction,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            text('Rihla POS', size: 10),
            text('${context.pageNumber} / ${context.pagesCount}', size: 10),
          ],
        ),
      ),
      build: (_) => [
        text(business, strong: true, size: 24),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            text(label('Sales invoice', 'فاتورة بيع'), strong: true, size: 19),
            text(invoice, strong: true, size: 15),
          ],
        ),
        pw.Divider(color: const PdfColor.fromInt(0xFF087F72)),
        text(
          '${label('Customer', 'العميل')}: ${sale['customer_name'] == 'Walk-in customer' ? label('Walk-in customer', 'عميل نقدي') : sale['customer_name']}',
        ),
        text(
          '${label('Date', 'التاريخ')}: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(sale['created'] as String).toLocal())}',
        ),
        text(
          '${label('Location', 'الموقع')}: ${sale['location'] == 'van' ? label('Van', 'السيارة') : label('Shop', 'المحل')}',
        ),
        pw.SizedBox(height: 20),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
          columnWidths: ar
              ? {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(.8),
                  2: const pw.FlexColumnWidth(1.4),
                  3: const pw.FlexColumnWidth(.6),
                  4: const pw.FlexColumnWidth(2.7),
                }
              : {
                  0: const pw.FlexColumnWidth(2.7),
                  1: const pw.FlexColumnWidth(.6),
                  2: const pw.FlexColumnWidth(1.4),
                  3: const pw.FlexColumnWidth(.8),
                  4: const pw.FlexColumnWidth(1.5),
                },
          children: [
            row(headers, header: true),
            ...lines.map(
              (line) => row([
                '${line['name']}${((line['discount'] as int?) ?? 0) > 0 ? '\n${label('Discount', 'الخصم')}: ${cash(line['discount'] as int)}' : ''}',
                '${line['quantity']}',
                cash(line['price'] as int),
                '${line['returned']}',
                cash(
                  (line['quantity'] as int) * (line['price'] as int) -
                      ((line['discount'] as int?) ?? 0),
                ),
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        if (((sale['discount'] as int?) ?? 0) > 0) ...[
          total(
            label('Items total', 'إجمالي الأصناف'),
            (sale['subtotal'] as int) + (sale['discount'] as int),
          ),
          total(label('Discount', 'الخصم'), -(sale['discount'] as int)),
        ],
        total(label('Subtotal', 'المجموع الفرعي'), sale['subtotal'] as int),
        total(
          '${label('Tax', 'الضريبة')} (${(sale['tax_bps'] as int) / 100}%)',
          sale['tax'] as int,
        ),
        total(
          label('Original total', 'الإجمالي الأصلي'),
          sale['total'] as int,
          strong: true,
        ),
        if ((sale['returned'] as int) > 0)
          total(
            label('Returns (including tax)', 'المرتجعات شاملة الضريبة'),
            -(sale['returned'] as int),
          ),
        total(
          label('Net total', 'صافي الإجمالي'),
          (sale['total'] as int) - (sale['returned'] as int),
          strong: true,
        ),
        total(
          label('Payments received', 'المدفوعات المستلمة'),
          sale['paid'] as int,
        ),
        if ((sale['refunded'] as int) > 0)
          total(label('Refunds', 'المبالغ المستردة'), sale['refunded'] as int),
        pw.Divider(),
        total(
          label('Balance due', 'الرصيد المستحق'),
          (sale['total'] as int) -
              (sale['returned'] as int) -
              (sale['paid'] as int) +
              (sale['refunded'] as int),
          strong: true,
        ),
        pw.SizedBox(height: 20),
        text(
          label(
            'Sales record for testing. Saudi e-invoicing is not configured.',
            'سجل بيع للاختبار. الفوترة الإلكترونية السعودية غير مهيأة.',
          ),
          size: 10,
        ),
      ],
    ),
  );
  return document.save();
}
