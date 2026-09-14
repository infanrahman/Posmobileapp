import 'dart:convert';
import 'dart:typed_data';

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
    final safe = RegExp(r'^[=+@\-\t\r]').hasMatch(value) ? "'$value" : value;
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
