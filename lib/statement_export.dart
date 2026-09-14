import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'store.dart';

List<DbRow> statementWithBalances(List<DbRow> entries) {
  var balance = 0;
  return entries.map((entry) {
    balance += (entry['debit'] as int) - (entry['credit'] as int);
    return {...entry, 'balance': balance};
  }).toList();
}

Uint8List statementCsv({
  required String title,
  required String party,
  required List<DbRow> entries,
  required String Function(String) translate,
}) {
  String cell(Object? value) {
    final text = '$value';
    final safe = RegExp(r'^[=+@\t\r]').hasMatch(text) ? "'$text" : text;
    return '"${safe.replaceAll('"', '""')}"';
  }

  String sar(Object? value) => ((value as int) / 100).toStringAsFixed(2);
  final balanced = statementWithBalances(entries);
  final rows = <List<Object?>>[
    [translate(title)],
    [translate('Account'), party],
    [
      translate('Date'),
      translate('Type'),
      translate('Reference'),
      translate('Debit (SAR)'),
      translate('Credit (SAR)'),
      translate('Balance (SAR)'),
    ],
    for (final entry in balanced)
      [
        entry['created'],
        translate(entry['type'] as String),
        entry['reference'],
        sar(entry['debit']),
        sar(entry['credit']),
        sar(entry['balance']),
      ],
  ];
  return Uint8List.fromList(
    utf8.encode(
      '\uFEFF${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n',
    ),
  );
}

Future<Uint8List> createStatementPdf({
  required String title,
  required String party,
  required String business,
  required List<DbRow> entries,
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
  String sar(int value) => NumberFormat('#,##0.00').format(value / 100);
  pw.Widget text(String value, {bool strong = false, double size = 10}) =>
      pw.Text(
        value,
        textDirection: RegExp(r'[\u0600-\u06FF]').hasMatch(value)
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        style: pw.TextStyle(font: strong ? bold : regular, fontSize: size),
      );
  final balanced = statementWithBalances(entries);
  final document = pw.Document(title: '$title - $party', author: business);
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (_) => [
        text(business, strong: true, size: 22),
        text(title, strong: true, size: 17),
        text('${label('Account', 'الحساب')}: $party', size: 12),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: [
            label('Date', 'التاريخ'),
            label('Type', 'النوع'),
            label('Reference', 'المرجع'),
            label('Debit', 'مدين'),
            label('Credit', 'دائن'),
            label('Balance', 'الرصيد'),
          ],
          data: [
            for (final entry in balanced)
              [
                DateFormat(
                  'yyyy-MM-dd',
                ).format(DateTime.parse(entry['created'] as String).toLocal()),
                entry['type'],
                entry['reference'],
                sar(entry['debit'] as int),
                sar(entry['credit'] as int),
                sar(entry['balance'] as int),
              ],
          ],
          headerStyle: pw.TextStyle(font: bold, fontSize: 9),
          cellStyle: pw.TextStyle(font: regular, fontSize: 8),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFE7F3EF),
          ),
          cellAlignment: pw.Alignment.centerLeft,
        ),
        pw.SizedBox(height: 12),
        text(
          '${label('Closing balance', 'الرصيد الختامي')}: SAR ${sar(balanced.isEmpty ? 0 : balanced.last['balance'] as int)}',
          strong: true,
          size: 12,
        ),
      ],
    ),
  );
  return document.save();
}
