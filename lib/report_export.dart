import 'dart:convert';
import 'dart:typed_data';

import 'store.dart';

const reportBasis =
    'Invoices are selected by original date, including all recorded returns and payments. Expenses use their recorded date. Stock value is current for the selected location, independent of dates.';
const reportLabels = {
  'net_sales': 'Net sales',
  'sales_tax': 'Net sales tax',
  'gross_profit': 'Gross profit',
  'purchases': 'Purchases',
  'expenses': 'Expenses',
  'receivables': 'Receivable',
  'payables': 'Payable',
  'cash_received': 'Cash received',
  'card_received': 'Card received',
  'bank_received': 'Bank transfer received',
  'stock_value': 'Current stock value at cost',
};

Uint8List reportCsv(
  Map<String, int> values, {
  required String dateRange,
  required String location,
  required String Function(String) translate,
}) {
  String cell(String value) {
    // Prevent spreadsheet formula execution if text fields are later extended.
    final safe = RegExp(r'^[=+@\t\r]').hasMatch(value) ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  final rows = <List<String>>[
    [translate('Business reports')],
    [translate('Dates'), dateRange],
    [translate('Location'), location],
    [translate(reportBasis)],
    [translate('Report'), 'SAR'],
    for (final e in reportLabels.entries)
      [translate(e.value), ((values[e.key] ?? 0) / 100).toStringAsFixed(2)],
    [
      translate('Profit after expenses'),
      (((values['gross_profit'] ?? 0) - (values['expenses'] ?? 0)) / 100)
          .toStringAsFixed(2),
    ],
  ];
  return Uint8List.fromList(
    utf8.encode(
      '\uFEFF${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n',
    ),
  );
}

Uint8List cashbookCsv(
  List<DbRow> sessions, {
  required String location,
  required String Function(String) translate,
}) {
  String cell(Object? value) {
    final text = '$value';
    final safe = RegExp(r'^[=+@\t\r]').hasMatch(text) ? "'$text" : text;
    return '"${safe.replaceAll('"', '""')}"';
  }

  String sar(Object? value) => ((value as int) / 100).toStringAsFixed(2);
  final rows = <List<Object?>>[
    [translate('Daily cashbook')],
    [translate('Location'), location],
    [
      translate('Opened'),
      translate('Closed'),
      translate('Opening cash'),
      translate('Sales and collections'),
      translate('Purchase refunds'),
      translate('Expenses'),
      translate('Supplier payments'),
      translate('Sales refunds'),
      translate('Expected cash'),
      translate('Actual cash'),
      translate('Variance'),
    ],
    for (final session in sessions)
      [
        session['opened'],
        session['closed'],
        sar(session['opening']),
        sar(session['sales_receipts']),
        sar(session['purchase_refunds']),
        sar(session['expenses']),
        sar(session['supplier_payments']),
        sar(session['sales_refunds']),
        sar(session['expected']),
        sar(session['actual']),
        sar((session['actual'] as int) - (session['expected'] as int)),
      ],
  ];
  return Uint8List.fromList(
    utf8.encode(
      '\uFEFF${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n',
    ),
  );
}
