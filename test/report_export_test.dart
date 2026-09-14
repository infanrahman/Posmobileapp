import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/report_export.dart';

void main() {
  test('report CSV contains filters, SAR totals and UTF-8 marker', () {
    final bytes = reportCsv(
      {
        'net_sales': 1234,
        'sales_tax': 100,
        'gross_profit': 500,
        'purchases': 700,
        'expenses': 200,
        'receivables': 300,
        'payables': 400,
        'stock_value': 900,
      },
      dateRange: '2026-01-01 – 2026-01-31',
      location: 'shop',
      translate: (value) => value,
    );

    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final csv = utf8.decode(bytes);
    expect(csv, contains('"Dates","2026-01-01 – 2026-01-31"'));
    expect(csv, contains('"Location","shop"'));
    expect(csv, contains('"Net sales","12.34"'));
    expect(csv, contains('"Profit after expenses","3.00"'));
  });
}
