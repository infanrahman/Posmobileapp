import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'store.dart';

// Parents precede children so foreign keys remain enabled throughout restore.
const backupTables = [
  'settings',
  'products',
  'customers',
  'suppliers',
  'sales',
  'sale_lines',
  'purchases',
  'purchase_lines',
  'payments',
  'supplier_payments',
  'movements',
  'expenses',
  'sale_returns',
];

const maxBackupBytes = 25 * 1024 * 1024;

class PosBackup {
  final String created;
  final Map<String, List<DbRow>> tables;
  const PosBackup._(this.created, this.tables);

  String get business =>
      tables['settings']!.firstWhere((row) => row['key'] == 'business')['value']
          as String;
  int count(String table) => tables[table]!.length;

  static PosBackup decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBackupBytes) {
      throw const FormatException('Choose a Rihla backup smaller than 25 MB.');
    }
    try {
      final envelope = jsonDecode(utf8.decode(bytes));
      if (envelope is! Map ||
          envelope['format'] != 'rihla-pos-backup' ||
          envelope['format_version'] != 1 ||
          envelope['database_version'] != 2) {
        throw const FormatException('This backup format is not supported.');
      }
      final payload = envelope['payload'];
      if (payload is! Map ||
          envelope['sha256'] !=
              sha256.convert(utf8.encode(jsonEncode(payload))).toString()) {
        throw const FormatException('The backup is damaged or incomplete.');
      }
      final created = payload['created'];
      final rows = payload['tables'];
      if (created is! String ||
          DateTime.tryParse(created) == null ||
          rows is! Map ||
          rows.length != backupTables.length ||
          !backupTables.every(rows.containsKey)) {
        throw const FormatException('The backup is missing required records.');
      }
      final tables = <String, List<DbRow>>{};
      for (final table in backupTables) {
        if (rows[table] is! List) {
          throw const FormatException('Invalid backup records.');
        }
        tables[table] = List.unmodifiable(
          (rows[table] as List).map((row) {
            if (row is! Map<String, dynamic>) {
              throw const FormatException('Invalid backup record.');
            }
            return Map<String, Object?>.unmodifiable(row);
          }),
        );
      }
      final settings = tables['settings']!;
      final business = settings.where((row) => row['key'] == 'business');
      final tax = settings.where((row) => row['key'] == 'tax_bps');
      if (business.length != 1 ||
          business.single['value'] is! String ||
          (business.single['value'] as String).trim().isEmpty ||
          tax.length != 1 ||
          tax.single['value'] is! String) {
        throw const FormatException(
          'The backup business settings are invalid.',
        );
      }
      final rate = int.tryParse(tax.single['value'] as String);
      if (rate == null || rate < 0 || rate > 10000) {
        throw const FormatException('The backup tax setting is invalid.');
      }
      final language = settings.where((row) => row['key'] == 'language');
      if (language.length > 1 ||
          (language.isNotEmpty &&
              !['en', 'ar'].contains(language.single['value']))) {
        throw const FormatException('The backup language setting is invalid.');
      }
      return PosBackup._(created, Map.unmodifiable(tables));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('This file is not a valid Rihla backup.');
    }
  }
}

extension BackupOperations on PosStore {
  Future<Uint8List> exportBackup() => db.transaction((tx) async {
    final payload = <String, Object?>{
      'created': DateTime.now().toUtc().toIso8601String(),
      'tables': {
        for (final table in backupTables) table: await tx.query(table),
      },
    };
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'rihla-pos-backup',
          'format_version': 1,
          'database_version': 2,
          'payload': payload,
          'sha256': sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
        }),
      ),
    );
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('This backup exceeds the 25 MB limit.');
    }
    return bytes;
  });

  Future<void> restoreBackup(PosBackup backup) async {
    try {
      await db.transaction((tx) async {
        // Check shape and types before SQLite can coerce malformed JSON values.
        for (final table in backupTables) {
          final columns = await tx.rawQuery('PRAGMA table_info($table)');
          for (final row in backup.tables[table]!) {
            if (row.length != columns.length) {
              throw const FormatException(
                'Backup record fields do not match this app.',
              );
            }
            for (final column in columns) {
              final name = column['name'] as String;
              final value = row[name];
              if (!row.containsKey(name) ||
                  (value == null &&
                      (column['notnull'] == 1 || column['pk'] == 1)) ||
                  (value != null &&
                      column['type'] == 'INTEGER' &&
                      value is! int) ||
                  (value != null &&
                      column['type'] == 'TEXT' &&
                      value is! String)) {
                throw const FormatException(
                  'Backup record values are invalid.',
                );
              }
              if (name == 'id' && (value is! int || value <= 0)) {
                throw const FormatException(
                  'Backup record identifiers are invalid.',
                );
              }
            }
            if (row.containsKey('location') &&
                row['location'] != 'shop' &&
                row['location'] != 'van') {
              throw const FormatException('Backup stock location is invalid.');
            }
          }
        }
        for (final table in backupTables.reversed) {
          await tx.delete(table);
        }
        for (final table in backupTables) {
          for (final row in backup.tables[table]!) {
            await tx.insert(
              table,
              row,
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
          }
        }
        if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
          throw const FormatException(
            'The backup contains broken record links.',
          );
        }
        await _validateRestoredLedgers(tx);
      });
    } on DatabaseException {
      throw const FormatException(
        'The backup contains invalid records. Your existing data was not changed.',
      );
    }
  }
}

Future<void> _validateRestoredLedgers(Transaction tx) async {
  const checks = [
    '''SELECT id FROM sale_lines WHERE quantity<=0 OR price<0 OR cost<0
       OR returned<0 OR returned>quantity''',
    '''SELECT id FROM sales s WHERE subtotal<0 OR tax_bps<0 OR tax_bps>10000
       OR tax != (subtotal*tax_bps+5000)/10000 OR total!=subtotal+tax
       OR returned<0 OR refunded<0 OR returned>total OR refunded>paid
       OR total-returned-paid+refunded<0
       OR (customer_id IS NULL AND total-returned-paid+refunded!=0)
       OR subtotal!=COALESCE((SELECT SUM(quantity*price) FROM sale_lines WHERE sale_id=s.id),0)
       OR paid!=COALESCE((SELECT SUM(amount) FROM payments WHERE sale_id=s.id),0)
       OR returned!=COALESCE((SELECT SUM(total) FROM sale_returns WHERE sale_id=s.id),0)
       OR refunded!=COALESCE((SELECT SUM(refund) FROM sale_returns WHERE sale_id=s.id),0)''',
    '''SELECT id FROM sale_returns WHERE subtotal<0 OR tax<0 OR total!=subtotal+tax
       OR refund<0 OR refund>total''',
    '''SELECT id FROM purchases p WHERE
       total!=COALESCE((SELECT SUM(quantity*cost) FROM purchase_lines WHERE purchase_id=p.id),0)
       OR paid!=COALESCE((SELECT SUM(amount) FROM supplier_payments WHERE purchase_id=p.id),0)
       OR (supplier_id IS NULL AND total!=paid)''',
  ];
  for (final sql in checks) {
    if ((await tx.rawQuery('$sql LIMIT 1')).isNotEmpty) {
      throw const FormatException(
        'Backup balances do not match its records. Your existing data was not changed.',
      );
    }
  }
}
