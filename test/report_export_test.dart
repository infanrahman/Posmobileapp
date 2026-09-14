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

  test('cashbook CSV contains closing amounts and variance', () {
    final bytes = cashbookCsv(
      [
        {
          'opened': '2026-09-14T06:00:00.000Z',
          'closed': '2026-09-14T14:00:00.000Z',
          'opening': 1000,
          'sales_receipts': 500,
          'purchase_refunds': 0,
          'expenses': 100,
          'supplier_payments': 200,
          'sales_refunds': 50,
          'expected': 1150,
          'actual': 1100,
        },
      ],
      location: 'shop',
      translate: (value) => value,
    );
    final csv = utf8.decode(bytes);
    expect(csv, contains('"Daily cashbook"'));
    expect(csv, contains('"Expected cash","Actual cash","Variance"'));
    expect(csv, contains('"11.50","11.00","-0.50"'));
  });
}
