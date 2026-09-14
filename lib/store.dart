import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'barcode.dart';

typedef DbRow = Map<String, Object?>;

const supportedPaymentMethods = {'cash', 'card', 'bank'};

String paymentMethod(String value) {
  if (!supportedPaymentMethods.contains(value)) {
    throw const FormatException('Choose a valid payment method.');
  }
  return value;
}

int purchaseBalance(DbRow row) =>
    (row['total'] as int) -
    (row['returned'] as int) -
    (row['paid'] as int) +
    (row['refunded'] as int);

int saleBalance(DbRow row) => (row['cancelled'] as int? ?? 0) == 1
    ? 0
    : (row['total'] as int) -
          (row['returned'] as int) -
          (row['paid'] as int) +
          (row['refunded'] as int);

// Allocate each line's saved discount cumulatively so split returns reconcile
// exactly to the original invoice, including the last halalah.
int returnedLineValue(DbRow line, int quantity) {
  final before = line['returned'] as int;
  final discount = (line['discount'] as int?) ?? 0;
  final originalQuantity = line['quantity'] as int;
  return (line['price'] as int) * quantity -
      (discount * (before + quantity) ~/ originalQuantity -
          discount * before ~/ originalQuantity);
}

int amount(String value) {
  final text = value.trim();
  if (!RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(text)) {
    throw const FormatException(
      'Enter an amount with up to two decimal places.',
    );
  }
  final parts = text.split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
}

int positiveQuantity(String value) {
  final n = int.tryParse(value.trim());
  if (n == null || n <= 0 || n > 1000000) {
    throw const FormatException(
      'Enter a whole quantity between 1 and 1,000,000.',
    );
  }
  return n;
}

String _invoiceUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final value = bytes.map(hex).join();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
      '${value.substring(12, 16)}-${value.substring(16, 20)}-'
      '${value.substring(20)}';
}

class PosStore {
  final Database db;
  PosStore(this.db);

  static Future<PosStore> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final database = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'rihla.db'),
      options: OpenDatabaseOptions(
        version: 8,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE products (
            id INTEGER PRIMARY KEY, name TEXT NOT NULL,
            sku TEXT NOT NULL UNIQUE, price INTEGER NOT NULL CHECK(price >= 0),
            cost INTEGER NOT NULL DEFAULT 0 CHECK(cost >= 0),
            shop INTEGER NOT NULL DEFAULT 0 CHECK(shop >= 0),
            van INTEGER NOT NULL DEFAULT 0 CHECK(van >= 0))''');
          await db.execute('''CREATE TABLE customers (
            id INTEGER PRIMARY KEY, name TEXT NOT NULL, phone TEXT NOT NULL,
            area TEXT NOT NULL)''');
          await db.execute('''CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT, created TEXT NOT NULL,
            customer_id INTEGER REFERENCES customers(id),
            customer_name TEXT NOT NULL, location TEXT NOT NULL,
            subtotal INTEGER NOT NULL, tax INTEGER NOT NULL,
            total INTEGER NOT NULL, paid INTEGER NOT NULL CHECK(paid >= 0 AND paid <= total),
            returned INTEGER NOT NULL DEFAULT 0 CHECK(returned >= 0),
            refunded INTEGER NOT NULL DEFAULT 0 CHECK(refunded >= 0),
            tax_bps INTEGER NOT NULL)''');
          await db.execute(
            '''CREATE TABLE sale_lines (
            id INTEGER PRIMARY KEY, sale_id INTEGER NOT NULL REFERENCES sales(id),
            product_id INTEGER NOT NULL REFERENCES products(id),
            name TEXT NOT NULL, quantity INTEGER NOT NULL, price INTEGER NOT NULL,
            cost INTEGER NOT NULL DEFAULT 0, returned INTEGER NOT NULL DEFAULT 0)''',
          );
          await db.execute('''CREATE TABLE movements (
            id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES products(id),
            created TEXT NOT NULL, location TEXT NOT NULL, quantity INTEGER NOT NULL,
            reason TEXT NOT NULL)''');
          await db.execute(
            '''CREATE TABLE payments (
            id INTEGER PRIMARY KEY, sale_id INTEGER NOT NULL REFERENCES sales(id),
            created TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0))''',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.insert('settings', {
            'key': 'business',
            'value': 'My business',
          });
          await db.insert('settings', {'key': 'tax_bps', 'value': '0'});
          await _createOperations(db);
          await _upgradeTrading(db);
          await _upgradeBarcodes(db);
          await _createCashbook(db);
          await _upgradePaymentMethods(db);
          await _upgradeReorderLevels(db);
          await _upgradeAdvancedWorkflows(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE products ADD COLUMN cost INTEGER NOT NULL DEFAULT 0 CHECK(cost >= 0)',
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN returned INTEGER NOT NULL DEFAULT 0 CHECK(returned >= 0)',
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN refunded INTEGER NOT NULL DEFAULT 0 CHECK(refunded >= 0)',
            );
            await db.execute(
              'ALTER TABLE sale_lines ADD COLUMN cost INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE sale_lines ADD COLUMN returned INTEGER NOT NULL DEFAULT 0',
            );
            await _createOperations(db);
          }
          if (oldVersion < 3) await _upgradeTrading(db);
          if (oldVersion < 4) await _upgradeBarcodes(db);
          if (oldVersion < 5) await _createCashbook(db);
          if (oldVersion < 6) await _upgradePaymentMethods(db);
          if (oldVersion < 7) await _upgradeReorderLevels(db);
          if (oldVersion < 8) await _upgradeAdvancedWorkflows(db);
        },
      ),
    );
    return PosStore(database);
  }

  static Future<void> _upgradeTrading(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE sales ADD COLUMN discount INTEGER NOT NULL DEFAULT 0 CHECK(discount >= 0)',
    );
    await db.execute(
      'ALTER TABLE sale_lines ADD COLUMN discount INTEGER NOT NULL DEFAULT 0 CHECK(discount >= 0)',
    );
    await db.execute(
      'ALTER TABLE purchases ADD COLUMN returned INTEGER NOT NULL DEFAULT 0 CHECK(returned >= 0)',
    );
    await db.execute(
      'ALTER TABLE purchases ADD COLUMN refunded INTEGER NOT NULL DEFAULT 0 CHECK(refunded >= 0)',
    );
    await db.execute(
      'ALTER TABLE purchase_lines ADD COLUMN returned INTEGER NOT NULL DEFAULT 0 CHECK(returned >= 0)',
    );
    await db.execute('''CREATE TABLE purchase_returns (
      id INTEGER PRIMARY KEY, purchase_id INTEGER NOT NULL REFERENCES purchases(id),
      created TEXT NOT NULL, total INTEGER NOT NULL CHECK(total >= 0),
      refund INTEGER NOT NULL CHECK(refund >= 0 AND refund <= total))''');
  }

  static Future<void> _upgradeBarcodes(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE products ADD COLUMN barcode TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "CREATE UNIQUE INDEX product_barcode_unique ON products(barcode) WHERE barcode != ''",
    );
  }

  static Future<void> _createCashbook(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS cash_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT, opened TEXT NOT NULL,
      closed TEXT, location TEXT NOT NULL, opening INTEGER NOT NULL CHECK(opening >= 0),
      sales_receipts INTEGER NOT NULL DEFAULT 0 CHECK(sales_receipts >= 0),
      purchase_refunds INTEGER NOT NULL DEFAULT 0 CHECK(purchase_refunds >= 0),
      expenses INTEGER NOT NULL DEFAULT 0 CHECK(expenses >= 0),
      supplier_payments INTEGER NOT NULL DEFAULT 0 CHECK(supplier_payments >= 0),
      sales_refunds INTEGER NOT NULL DEFAULT 0 CHECK(sales_refunds >= 0),
      expected INTEGER NOT NULL DEFAULT 0,
      actual INTEGER CHECK(actual >= 0), note TEXT NOT NULL DEFAULT '')''');
    await db.execute(
      '''CREATE UNIQUE INDEX IF NOT EXISTS cash_session_open_location
      ON cash_sessions(location) WHERE closed IS NULL''',
    );
  }

  static Future<void> _upgradePaymentMethods(DatabaseExecutor db) async {
    Future<void> add(String table, String column) async {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (columns.isNotEmpty && !columns.any((row) => row['name'] == column)) {
        await db.execute(
          "ALTER TABLE $table ADD COLUMN $column TEXT NOT NULL DEFAULT 'cash'",
        );
      }
    }

    await add('payments', 'method');
    await add('supplier_payments', 'method');
    await add('expenses', 'method');
    await add('sale_returns', 'refund_method');
    await add('purchase_returns', 'refund_method');
  }

  static Future<void> _upgradeReorderLevels(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(products)');
    if (columns.isNotEmpty &&
        !columns.any((row) => row['name'] == 'reorder_level')) {
      // Six preserves the previous fixed warning for quantities of five or less.
      await db.execute(
        'ALTER TABLE products ADD COLUMN reorder_level INTEGER NOT NULL '
        'DEFAULT 6 CHECK(reorder_level >= 0)',
      );
    }
  }

  static Future<void> _upgradeAdvancedWorkflows(DatabaseExecutor db) async {
    Future<void> addColumn(String table, String definition) async {
      final name = definition.split(' ').first;
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (columns.isNotEmpty && !columns.any((row) => row['name'] == name)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $definition');
      }
    }

    await addColumn(
      'sales',
      'cancelled INTEGER NOT NULL DEFAULT 0 CHECK(cancelled IN (0,1))',
    );
    await addColumn('sales', "cancelled_at TEXT NOT NULL DEFAULT ''");
    await addColumn('sales', "cancellation_reason TEXT NOT NULL DEFAULT ''");
    await addColumn('sales', "invoice_uuid TEXT NOT NULL DEFAULT ''");
    await addColumn('sales', 'invoice_counter INTEGER NOT NULL DEFAULT 0');
    await addColumn('sales', 'van_id INTEGER');
    await addColumn('sales', "van_name TEXT NOT NULL DEFAULT ''");
    await addColumn('sales', "salesperson TEXT NOT NULL DEFAULT ''");
    await db.execute('''CREATE TABLE IF NOT EXISTS sale_cancellations (
      id INTEGER PRIMARY KEY, sale_id INTEGER NOT NULL UNIQUE REFERENCES sales(id),
      created TEXT NOT NULL, reason TEXT NOT NULL,
      refund INTEGER NOT NULL CHECK(refund >= 0),
      refund_method TEXT NOT NULL DEFAULT 'cash')''');
    await db.execute('''CREATE TABLE IF NOT EXISTS saved_documents (
      id INTEGER PRIMARY KEY, kind TEXT NOT NULL, created TEXT NOT NULL,
      name TEXT NOT NULL, party_id INTEGER, party_name TEXT NOT NULL,
      location TEXT NOT NULL, payload TEXT NOT NULL, total INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'open', linked_id INTEGER,
      notes TEXT NOT NULL DEFAULT '')''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS saved_document_kind ON saved_documents(kind, status, id DESC)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS vans (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE,
      salesperson TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1
      CHECK(active IN (0,1)))''');
    await db.insert('vans', {
      'id': 1,
      'name': 'Van 1',
      'salesperson': '',
      'active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final settingsTable = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='settings'",
    );
    if (settingsTable.isNotEmpty) {
      for (final setting in const {
        'seller_vat': '',
        'business_address': '',
        'invoice_counter': '0',
      }.entries) {
        await db.insert('settings', {
          'key': setting.key,
          'value': setting.value,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  static Future<void> _createOperations(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS suppliers (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, phone TEXT NOT NULL,
      tax_number TEXT NOT NULL, address TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS purchases (
      id INTEGER PRIMARY KEY AUTOINCREMENT, created TEXT NOT NULL,
      supplier_id INTEGER REFERENCES suppliers(id), supplier_name TEXT NOT NULL,
      location TEXT NOT NULL, total INTEGER NOT NULL CHECK(total >= 0),
      paid INTEGER NOT NULL CHECK(paid >= 0 AND paid <= total))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS purchase_lines (
      id INTEGER PRIMARY KEY, purchase_id INTEGER NOT NULL REFERENCES purchases(id),
      product_id INTEGER NOT NULL REFERENCES products(id), name TEXT NOT NULL,
      quantity INTEGER NOT NULL CHECK(quantity > 0), cost INTEGER NOT NULL CHECK(cost >= 0))''',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS supplier_payments (
      id INTEGER PRIMARY KEY, purchase_id INTEGER NOT NULL REFERENCES purchases(id),
      created TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS expenses (
      id INTEGER PRIMARY KEY, created TEXT NOT NULL, category TEXT NOT NULL,
      note TEXT NOT NULL, location TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0))''',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS sale_returns (
      id INTEGER PRIMARY KEY, sale_id INTEGER NOT NULL REFERENCES sales(id),
      created TEXT NOT NULL, subtotal INTEGER NOT NULL, tax INTEGER NOT NULL,
      total INTEGER NOT NULL, refund INTEGER NOT NULL)''');
  }

  Future<List<DbRow>> products() =>
      db.query('products', orderBy: 'name COLLATE NOCASE');
  Future<List<DbRow>> customers() => db.rawQuery(
    '''SELECT c.*,
    COALESCE(SUM(CASE WHEN COALESCE(s.cancelled,0)=0
      THEN s.total-s.returned-s.paid+s.refunded ELSE 0 END),0) AS balance FROM customers c
    LEFT JOIN sales s ON s.customer_id=c.id GROUP BY c.id ORDER BY c.name COLLATE NOCASE''',
  );
  Future<List<DbRow>> sales() => db.query('sales', orderBy: 'id DESC');
  Future<List<DbRow>> lines(int sale) =>
      db.query('sale_lines', where: 'sale_id=?', whereArgs: [sale]);
  Future<List<DbRow>> suppliers() => db.rawQuery(
    '''SELECT s.*, COALESCE(SUM(p.total-p.returned-p.paid+p.refunded),0) AS balance
    FROM suppliers s LEFT JOIN purchases p ON p.supplier_id=s.id
    GROUP BY s.id ORDER BY s.name COLLATE NOCASE''',
  );
  Future<List<DbRow>> purchases() => db.query('purchases', orderBy: 'id DESC');
  Future<List<DbRow>> purchaseLines(int purchase) =>
      db.query('purchase_lines', where: 'purchase_id=?', whereArgs: [purchase]);
  Future<List<DbRow>> salePayments(int sale) =>
      db.query('payments', where: 'sale_id=?', whereArgs: [sale]);
  Future<List<DbRow>> saleCancellations(int sale) =>
      db.query('sale_cancellations', where: 'sale_id=?', whereArgs: [sale]);
  Future<List<DbRow>> purchasePayments(int purchase) => db.query(
    'supplier_payments',
    where: 'purchase_id=?',
    whereArgs: [purchase],
  );
  Future<List<DbRow>> expenses() => db.query('expenses', orderBy: 'id DESC');
  Future<List<DbRow>> vans({bool activeOnly = false}) => db.query(
    'vans',
    where: activeOnly ? 'active=1' : null,
    orderBy: 'active DESC, name COLLATE NOCASE',
  );
  Future<List<DbRow>> savedDocuments(String kind) {
    if (!{'held_sale', 'quotation', 'purchase_order'}.contains(kind)) {
      throw ArgumentError('Invalid document kind');
    }
    return db.query(
      'saved_documents',
      where: 'kind=?',
      whereArgs: [kind],
      orderBy: 'id DESC',
    );
  }

  Future<List<DbRow>> customerStatement(int customer) => db.rawQuery(
    '''SELECT created, type, reference, debit, credit FROM (
      SELECT s.created created, 'Sale' type, 'INV-' || printf('%05d',s.id) reference,
        s.total debit, 0 credit
        FROM sales s WHERE s.customer_id=?
      UNION ALL
      SELECT r.created, 'Sales return', 'INV-' || printf('%05d',r.sale_id), 0, r.total
        FROM sale_returns r JOIN sales s ON s.id=r.sale_id
        WHERE s.customer_id=? AND COALESCE(s.cancelled,0)=0
      UNION ALL
      SELECT p.created, 'Customer payment', 'INV-' || printf('%05d',p.sale_id), 0, p.amount
        FROM payments p JOIN sales s ON s.id=p.sale_id
        WHERE s.customer_id=?
      UNION ALL
      SELECT r.created, 'Customer refund', 'INV-' || printf('%05d',r.sale_id), r.refund, 0
        FROM sale_returns r JOIN sales s ON s.id=r.sale_id
        WHERE s.customer_id=? AND COALESCE(s.cancelled,0)=0
      UNION ALL
      SELECT c.created, 'Sale cancellation', 'INV-' || printf('%05d',c.sale_id),
        c.refund, s.total FROM sale_cancellations c
        JOIN sales s ON s.id=c.sale_id WHERE s.customer_id=?
    ) ORDER BY created, reference''',
    [customer, customer, customer, customer, customer],
  );

  Future<List<DbRow>> supplierStatement(int supplier) => db.rawQuery(
    '''SELECT created, type, reference, debit, credit FROM (
      SELECT created, 'Purchase' type, 'PUR-' || printf('%05d',id) reference,
        total debit, 0 credit FROM purchases WHERE supplier_id=?
      UNION ALL
      SELECT r.created, 'Purchase return', 'PUR-' || printf('%05d',r.purchase_id), 0, r.total
        FROM purchase_returns r JOIN purchases p ON p.id=r.purchase_id WHERE p.supplier_id=?
      UNION ALL
      SELECT sp.created, 'Supplier payment', 'PUR-' || printf('%05d',sp.purchase_id), 0, sp.amount
        FROM supplier_payments sp JOIN purchases p ON p.id=sp.purchase_id WHERE p.supplier_id=?
      UNION ALL
      SELECT r.created, 'Supplier refund', 'PUR-' || printf('%05d',r.purchase_id), r.refund, 0
        FROM purchase_returns r JOIN purchases p ON p.id=r.purchase_id WHERE p.supplier_id=?
    ) ORDER BY created, reference''',
    [supplier, supplier, supplier, supplier],
  );
  Future<Map<String, String>> settings() async => {
    for (final row in await db.query('settings'))
      row['key'] as String: row['value'] as String,
  };

  Future<void> saveSettings(
    String business,
    int taxBps, {
    String? sellerVat,
    String? businessAddress,
  }) async {
    final vat = sellerVat?.trim();
    if (business.trim().isEmpty ||
        taxBps < 0 ||
        taxBps > 10000 ||
        (vat != null &&
            vat.isNotEmpty &&
            !RegExp(r'^3\d{13}3$').hasMatch(vat))) {
      throw const FormatException(
        'Enter a business name, a tax rate from 0 to 100 and a valid 15-digit VAT number.',
      );
    }
    await db.transaction((tx) async {
      await tx.update(
        'settings',
        {'value': business.trim()},
        where: 'key=?',
        whereArgs: ['business'],
      );
      await tx.update(
        'settings',
        {'value': '$taxBps'},
        where: 'key=?',
        whereArgs: ['tax_bps'],
      );
      if (sellerVat != null) {
        await tx.insert('settings', {
          'key': 'seller_vat',
          'value': vat!,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (businessAddress != null) {
        await tx.insert('settings', {
          'key': 'business_address',
          'value': businessAddress.trim(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> addVan(String name, String salesperson) async {
    if (name.trim().isEmpty) {
      throw const FormatException('Van name is required.');
    }
    if ((await db.query(
      'vans',
      where: 'name=? COLLATE NOCASE',
      whereArgs: [name.trim()],
      limit: 1,
    )).isNotEmpty) {
      throw const FormatException('A van with this name already exists.');
    }
    return db.insert('vans', {
      'name': name.trim(),
      'salesperson': salesperson.trim(),
      'active': 1,
    });
  }

  Future<void> updateVan(
    int id,
    String name,
    String salesperson,
    bool active,
  ) async {
    if (name.trim().isEmpty || id == 1 && !active) {
      throw const FormatException('The default van must remain active.');
    }
    if ((await db.query(
      'vans',
      where: 'name=? COLLATE NOCASE AND id!=?',
      whereArgs: [name.trim(), id],
      limit: 1,
    )).isNotEmpty) {
      throw const FormatException('A van with this name already exists.');
    }
    final changed = await db.update(
      'vans',
      {
        'name': name.trim(),
        'salesperson': salesperson.trim(),
        'active': active ? 1 : 0,
      },
      where: 'id=?',
      whereArgs: [id],
    );
    if (changed != 1) throw const FormatException('Van no longer exists.');
  }

  Future<int> saveDocument({
    required String kind,
    required String name,
    required int? partyId,
    required String partyName,
    required String location,
    required Map<String, Object?> payload,
    required int total,
    String notes = '',
  }) async {
    if (!{'held_sale', 'quotation', 'purchase_order'}.contains(kind) ||
        name.trim().isEmpty ||
        total < 0) {
      throw const FormatException('Saved document details are invalid.');
    }
    _location(location);
    return db.insert('saved_documents', {
      'kind': kind,
      'created': DateTime.now().toUtc().toIso8601String(),
      'name': name.trim(),
      'party_id': partyId,
      'party_name': partyName.trim(),
      'location': location,
      'payload': jsonEncode(payload),
      'total': total,
      'status': 'open',
      'notes': notes.trim(),
    });
  }

  Map<String, dynamic> documentPayload(DbRow document) {
    final value = jsonDecode(document['payload'] as String);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Saved document is damaged.');
    }
    return value;
  }

  Future<void> finishDocument(int id, int linkedId) async {
    final changed = await db.update(
      'saved_documents',
      {'status': 'converted', 'linked_id': linkedId},
      where: 'id=? AND status=?',
      whereArgs: [id, 'open'],
    );
    if (changed != 1) {
      throw const FormatException('Saved document is no longer open.');
    }
  }

  Future<void> deleteDocument(int id) => db.delete(
    'saved_documents',
    where: 'id=? AND status=?',
    whereArgs: [id, 'open'],
  );

  Future<void> saveLanguage(String language) async {
    if (language != 'en' && language != 'ar') {
      throw const FormatException('Unsupported language.');
    }
    await db.insert('settings', {
      'key': 'language',
      'value': language,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> addProduct(
    String name,
    String sku,
    int price,
    int stock,
    String location, {
    int cost = 0,
    String barcode = '',
    int reorderLevel = 6,
  }) async {
    _location(location);
    if (name.trim().isEmpty ||
        sku.trim().isEmpty ||
        price < 0 ||
        cost < 0 ||
        stock < 0 ||
        reorderLevel < 0 ||
        reorderLevel > 1000000) {
      throw const FormatException(
        'Name, unique SKU, price and stock are required.',
      );
    }
    await db.transaction((tx) async {
      final id = await tx.insert('products', {
        'name': name.trim(),
        'sku': sku.trim().toUpperCase(),
        'price': price,
        'cost': cost,
        'barcode': normalizeBarcode(barcode),
        'reorder_level': reorderLevel,
        location: stock,
      });
      if (stock > 0) await _movement(tx, id, location, stock, 'Opening stock');
    });
  }

  Future<void> updateProduct(
    int id,
    String name,
    String sku,
    int price,
    int cost, {
    String? barcode,
    int? reorderLevel,
  }) async {
    if (name.trim().isEmpty ||
        sku.trim().isEmpty ||
        price < 0 ||
        cost < 0 ||
        (reorderLevel != null &&
            (reorderLevel < 0 || reorderLevel > 1000000))) {
      throw const FormatException(
        'Name, unique SKU, cost and price are required.',
      );
    }
    final changed = await db.update(
      'products',
      {
        'name': name.trim(),
        'sku': sku.trim().toUpperCase(),
        'price': price,
        'cost': cost,
        if (barcode != null) 'barcode': normalizeBarcode(barcode),
        'reorder_level': ?reorderLevel,
      },
      where: 'id=?',
      whereArgs: [id],
    );
    if (changed != 1) throw const FormatException('Product no longer exists.');
  }

  Future<void> addCustomer(String name, String phone, String area) async {
    if (name.trim().isEmpty) {
      throw const FormatException('Customer name is required.');
    }
    await db.insert('customers', {
      'name': name.trim(),
      'phone': phone.trim(),
      'area': area.trim(),
    });
  }

  Future<void> updateCustomer(
    int id,
    String name,
    String phone,
    String area,
  ) async {
    if (name.trim().isEmpty) {
      throw const FormatException('Customer name is required.');
    }
    final changed = await db.update(
      'customers',
      {'name': name.trim(), 'phone': phone.trim(), 'area': area.trim()},
      where: 'id=?',
      whereArgs: [id],
    );
    if (changed != 1) throw const FormatException('Customer no longer exists.');
  }

  static void _location(String location) {
    if (location != 'shop' && location != 'van') {
      throw ArgumentError('Invalid stock location');
    }
  }

  Future<void> _movement(
    Transaction tx,
    int product,
    String location,
    int quantity,
    String reason,
  ) async {
    await tx.insert('movements', {
      'product_id': product,
      'created': DateTime.now().toUtc().toIso8601String(),
      'location': location,
      'quantity': quantity,
      'reason': reason,
    });
  }

  Future<void> receiveStock(int product, int quantity, String location) async {
    _location(location);
    if (quantity <= 0) {
      throw const FormatException('Quantity must be positive.');
    }
    await db.transaction((tx) async {
      final changed = await tx.rawUpdate(
        'UPDATE products SET $location=$location+? WHERE id=?',
        [quantity, product],
      );
      if (changed != 1) {
        throw const FormatException('Product no longer exists.');
      }
      await _movement(tx, product, location, quantity, 'Stock received');
    });
  }

  Future<void> transfer(int product, int quantity, String from) async {
    _location(from);
    if (quantity <= 0) {
      throw const FormatException('Quantity must be positive.');
    }
    final to = from == 'shop' ? 'van' : 'shop';
    await db.transaction((tx) async {
      final changed = await tx.rawUpdate(
        'UPDATE products SET $from=$from-?, $to=$to+? WHERE id=? AND $from>=?',
        [quantity, quantity, product, quantity],
      );
      if (changed != 1) {
        throw const FormatException('Not enough stock to transfer.');
      }
      await _movement(tx, product, from, -quantity, 'Transfer to $to');
      await _movement(tx, product, to, quantity, 'Transfer from $from');
    });
  }

  Future<int> checkout(
    Map<int, int> cart,
    String location,
    int? customer,
    int taxBps,
    int? payment, {
    int discount = 0,
    Map<String, int>? paymentBreakdown,
    Map<int, int>? lineDiscounts,
    Map<int, int>? unitPrices,
    int? vanId,
  }) async {
    _location(location);
    if (cart.isEmpty) throw const FormatException('Add an item to the sale.');
    if (taxBps < 0 || taxBps > 10000) {
      throw const FormatException('Invalid tax rate.');
    }
    return db.transaction((tx) async {
      String customerName = 'Walk-in customer';
      int? savedVanId;
      String vanName = '', salesperson = '';
      if (customer != null) {
        final rows = await tx.query(
          'customers',
          where: 'id=?',
          whereArgs: [customer],
        );
        if (rows.isEmpty) {
          throw const FormatException('Customer no longer exists.');
        }
        customerName = rows.first['name'] as String;
      }
      if (location == 'van') {
        final vanRows = await tx.query(
          'vans',
          where: 'id=? AND active=1',
          whereArgs: [vanId ?? 1],
          limit: 1,
        );
        if (vanRows.isEmpty) {
          throw const FormatException('Choose an active van.');
        }
        savedVanId = vanRows.single['id'] as int;
        vanName = vanRows.single['name'] as String;
        salesperson = vanRows.single['salesperson'] as String;
      }
      int itemsTotal = 0;
      int lineDiscountTotal = 0;
      final items = <DbRow>[];
      for (final entry in cart.entries) {
        if (entry.value <= 0 || entry.value > 1000000) {
          throw const FormatException('Invalid quantity.');
        }
        final rows = await tx.query(
          'products',
          where: 'id=?',
          whereArgs: [entry.key],
        );
        if (rows.isEmpty) {
          throw const FormatException('Product no longer exists.');
        }
        final row = rows.first;
        if ((row[location] as int) < entry.value) {
          throw FormatException(
            'Not enough ${row['name']} stock in $location.',
          );
        }
        final unitPrice = unitPrices?[entry.key] ?? row['price'] as int;
        if (unitPrice < 0) {
          throw const FormatException('Item price cannot be negative.');
        }
        final lineTotal = unitPrice * entry.value;
        final lineDiscount = lineDiscounts?[entry.key] ?? 0;
        if (lineDiscount < 0 || lineDiscount > lineTotal) {
          throw const FormatException(
            'Item discount must be between zero and the line total.',
          );
        }
        itemsTotal += lineTotal;
        lineDiscountTotal += lineDiscount;
        items.add({
          'product_id': entry.key,
          'name': row['name'],
          'quantity': entry.value,
          'price': unitPrice,
          'cost': row['cost'],
          'discount': lineDiscount,
        });
      }
      final discountedItemsTotal = itemsTotal - lineDiscountTotal;
      if (discount < 0 || discount > discountedItemsTotal) {
        throw const FormatException(
          'Discount must be between zero and the items total.',
        );
      }
      int cumulative = 0, allocated = 0;
      for (final item in items) {
        cumulative +=
            (item['price'] as int) * (item['quantity'] as int) -
            (item['discount'] as int);
        final target = discountedItemsTotal == 0
            ? 0
            : discount * cumulative ~/ discountedItemsTotal;
        item['discount'] = (item['discount'] as int) + target - allocated;
        allocated = target;
      }
      final subtotal = discountedItemsTotal - discount;
      final tax = (subtotal * taxBps + 5000) ~/ 10000;
      final total = subtotal + tax;
      final paid = payment ?? total;
      if (paid < 0 || paid > total) {
        throw const FormatException(
          'Payment must be between zero and the sale total.',
        );
      }
      if (paid < total && customer == null) {
        throw const FormatException('Select a customer for a credit sale.');
      }
      final methods = paymentBreakdown ?? {if (paid > 0) 'cash': paid};
      if (methods.entries.any(
            (entry) =>
                !supportedPaymentMethods.contains(entry.key) ||
                entry.value <= 0,
          ) ||
          methods.values.fold(0, (sum, value) => sum + value) != paid) {
        throw const FormatException(
          'Payment methods do not match the total paid.',
        );
      }
      final counterRow = await tx.query(
        'settings',
        where: 'key=?',
        whereArgs: ['invoice_counter'],
        limit: 1,
      );
      final counter =
          int.tryParse(
            counterRow.isEmpty ? '0' : counterRow.single['value'] as String,
          ) ??
          0;
      final nextCounter = counter + 1;
      await tx.insert('settings', {
        'key': 'invoice_counter',
        'value': '$nextCounter',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final id = await tx.insert('sales', {
        'created': DateTime.now().toUtc().toIso8601String(),
        'customer_id': customer,
        'customer_name': customerName,
        'location': location,
        'subtotal': subtotal,
        'discount': lineDiscountTotal + discount,
        'tax': tax,
        'total': total,
        'paid': paid,
        'tax_bps': taxBps,
        'invoice_uuid': _invoiceUuid(),
        'invoice_counter': nextCounter,
        'van_id': savedVanId,
        'van_name': vanName,
        'salesperson': salesperson,
      });
      for (final item in items) {
        await tx.insert('sale_lines', {...item, 'sale_id': id});
        await tx.rawUpdate(
          'UPDATE products SET $location=$location-? WHERE id=?',
          [item['quantity'], item['product_id']],
        );
        await _movement(
          tx,
          item['product_id'] as int,
          location,
          -(item['quantity'] as int),
          'Sale #$id',
        );
      }
      for (final entry in methods.entries) {
        await tx.insert('payments', {
          'sale_id': id,
          'amount': entry.value,
          'method': entry.key,
          'created': DateTime.now().toUtc().toIso8601String(),
        });
      }
      return id;
    });
  }

  Future<void> collect(int sale, int payment, {String method = 'cash'}) async {
    paymentMethod(method);
    if (payment <= 0) {
      throw const FormatException('Payment must be greater than zero.');
    }
    await db.transaction((tx) async {
      final changed = await tx.rawUpdate(
        '''UPDATE sales SET paid=paid+? WHERE id=?
        AND COALESCE(cancelled,0)=0 AND total-returned-paid+refunded>=?''',
        [payment, sale, payment],
      );
      if (changed != 1) {
        throw const FormatException('Payment exceeds the outstanding balance.');
      }
      await tx.insert('payments', {
        'sale_id': sale,
        'amount': payment,
        'method': method,
        'created': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<int> cancelSale(
    int saleId,
    String reason, {
    String refundMethod = 'cash',
  }) async {
    paymentMethod(refundMethod);
    if (reason.trim().isEmpty) {
      throw const FormatException('Enter a cancellation reason.');
    }
    return db.transaction((tx) async {
      final rows = await tx.query(
        'sales',
        where: 'id=?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (rows.isEmpty || (rows.single['cancelled'] as int? ?? 0) == 1) {
        throw const FormatException('Sale is already cancelled.');
      }
      final sale = rows.single;
      if ((sale['returned'] as int) != 0) {
        throw const FormatException(
          'A sale with returns cannot be cancelled. Return its remaining items instead.',
        );
      }
      final location = sale['location'] as String;
      final lines = await tx.query(
        'sale_lines',
        where: 'sale_id=?',
        whereArgs: [saleId],
      );
      for (final line in lines) {
        await tx.rawUpdate(
          'UPDATE products SET $location=$location+? WHERE id=?',
          [line['quantity'], line['product_id']],
        );
        await _movement(
          tx,
          line['product_id'] as int,
          location,
          line['quantity'] as int,
          'Cancellation for sale #$saleId',
        );
      }
      final created = DateTime.now().toUtc().toIso8601String();
      await tx.update(
        'sales',
        {
          'cancelled': 1,
          'cancelled_at': created,
          'cancellation_reason': reason.trim(),
        },
        where: 'id=?',
        whereArgs: [saleId],
      );
      final refund = sale['paid'] as int;
      await tx.insert('sale_cancellations', {
        'sale_id': saleId,
        'created': created,
        'reason': reason.trim(),
        'refund': refund,
        'refund_method': refundMethod,
      });
      return refund;
    });
  }

  Future<void> addSupplier(
    String name,
    String phone,
    String taxNumber,
    String address,
  ) async {
    if (name.trim().isEmpty) {
      throw const FormatException('Supplier name is required.');
    }
    await db.insert('suppliers', {
      'name': name.trim(),
      'phone': phone.trim(),
      'tax_number': taxNumber.trim(),
      'address': address.trim(),
    });
  }

  Future<void> updateSupplier(
    int id,
    String name,
    String phone,
    String taxNumber,
    String address,
  ) async {
    if (name.trim().isEmpty) {
      throw const FormatException('Supplier name is required.');
    }
    final changed = await db.update(
      'suppliers',
      {
        'name': name.trim(),
        'phone': phone.trim(),
        'tax_number': taxNumber.trim(),
        'address': address.trim(),
      },
      where: 'id=?',
      whereArgs: [id],
    );
    if (changed != 1) throw const FormatException('Supplier no longer exists.');
  }

  Future<int> addPurchase(
    Map<int, ({int quantity, int cost})> cart,
    String location,
    int? supplier,
    int? payment, {
    String method = 'cash',
  }) async {
    _location(location);
    paymentMethod(method);
    if (cart.isEmpty) {
      throw const FormatException('Add an item to the purchase.');
    }
    return db.transaction((tx) async {
      String supplierName = 'Cash supplier';
      if (supplier != null) {
        final rows = await tx.query(
          'suppliers',
          where: 'id=?',
          whereArgs: [supplier],
        );
        if (rows.isEmpty) {
          throw const FormatException('Supplier no longer exists.');
        }
        supplierName = rows.first['name'] as String;
      }
      int total = 0;
      final items = <DbRow>[];
      for (final entry in cart.entries) {
        if (entry.value.quantity <= 0 || entry.value.cost < 0) {
          throw const FormatException(
            'Purchase quantities and costs are invalid.',
          );
        }
        final rows = await tx.query(
          'products',
          where: 'id=?',
          whereArgs: [entry.key],
        );
        if (rows.isEmpty) {
          throw const FormatException('Product no longer exists.');
        }
        total += entry.value.quantity * entry.value.cost;
        items.add({
          'product_id': entry.key,
          'name': rows.first['name'],
          'quantity': entry.value.quantity,
          'cost': entry.value.cost,
        });
      }
      final paid = payment ?? total;
      if (paid < 0 || paid > total) {
        throw const FormatException(
          'Payment must be between zero and the purchase total.',
        );
      }
      if (paid < total && supplier == null) {
        throw const FormatException('Select a supplier for a credit purchase.');
      }
      final id = await tx.insert('purchases', {
        'created': DateTime.now().toUtc().toIso8601String(),
        'supplier_id': supplier,
        'supplier_name': supplierName,
        'location': location,
        'total': total,
        'paid': paid,
      });
      for (final item in items) {
        await tx.insert('purchase_lines', {...item, 'purchase_id': id});
        await tx.rawUpdate(
          'UPDATE products SET $location=$location+?, cost=? WHERE id=?',
          [item['quantity'], item['cost'], item['product_id']],
        );
        await _movement(
          tx,
          item['product_id'] as int,
          location,
          item['quantity'] as int,
          'Purchase #$id',
        );
      }
      if (paid > 0) {
        await tx.insert('supplier_payments', {
          'purchase_id': id,
          'created': DateTime.now().toUtc().toIso8601String(),
          'amount': paid,
          'method': method,
        });
      }
      return id;
    });
  }

  Future<void> paySupplier(
    int purchase,
    int payment, {
    String method = 'cash',
  }) async {
    paymentMethod(method);
    if (payment <= 0) {
      throw const FormatException('Payment must be greater than zero.');
    }
    await db.transaction((tx) async {
      final changed = await tx.rawUpdate(
        'UPDATE purchases SET paid=paid+? WHERE id=? AND total-returned-paid+refunded>=?',
        [payment, purchase, payment],
      );
      if (changed != 1) {
        throw const FormatException('Payment exceeds the purchase balance.');
      }
      await tx.insert('supplier_payments', {
        'purchase_id': purchase,
        'created': DateTime.now().toUtc().toIso8601String(),
        'amount': payment,
        'method': method,
      });
    });
  }

  Future<void> addExpense(
    String category,
    String note,
    int value,
    String location, {
    String method = 'cash',
  }) async {
    _location(location);
    paymentMethod(method);
    if (category.trim().isEmpty || value <= 0) {
      throw const FormatException('Expense category and amount are required.');
    }
    await db.insert('expenses', {
      'created': DateTime.now().toUtc().toIso8601String(),
      'category': category.trim(),
      'note': note.trim(),
      'location': location,
      'amount': value,
      'method': method,
    });
  }

  Future<int> returnSale(
    int saleId,
    Map<int, int> quantities, {
    String refundMethod = 'cash',
  }) async {
    paymentMethod(refundMethod);
    if (quantities.isEmpty) {
      throw const FormatException('Choose at least one item to return.');
    }
    return db.transaction((tx) async {
      final sales = await tx.query('sales', where: 'id=?', whereArgs: [saleId]);
      if (sales.isEmpty) throw const FormatException('Sale no longer exists.');
      final sale = sales.first;
      if ((sale['cancelled'] as int? ?? 0) == 1) {
        throw const FormatException('Cancelled sales cannot be returned.');
      }
      final location = sale['location'] as String;
      _location(location);
      int subtotal = 0;
      final returnedItems = <({DbRow line, int quantity})>[];
      for (final entry in quantities.entries) {
        if (entry.value <= 0) {
          throw const FormatException('Return quantity must be positive.');
        }
        final rows = await tx.query(
          'sale_lines',
          where: 'id=? AND sale_id=?',
          whereArgs: [entry.key, saleId],
        );
        if (rows.isEmpty) {
          throw const FormatException('Sale item no longer exists.');
        }
        final line = rows.first;
        final available = (line['quantity'] as int) - (line['returned'] as int);
        if (entry.value > available) {
          throw FormatException(
            'Only $available ${line['name']} can be returned.',
          );
        }
        subtotal += returnedLineValue(line, entry.value);
        returnedItems.add((line: line, quantity: entry.value));
      }
      final previous = await tx.rawQuery(
        '''SELECT COALESCE(SUM(subtotal),0) subtotal, COALESCE(SUM(tax),0) tax
        FROM sale_returns WHERE sale_id=?''',
        [saleId],
      );
      final previousSubtotal = previous.first['subtotal'] as int;
      final previousTax = previous.first['tax'] as int;
      final cumulativeTax =
          ((previousSubtotal + subtotal) * (sale['tax_bps'] as int) + 5000) ~/
          10000;
      final tax = cumulativeTax - previousTax;
      final total = subtotal + tax;
      final newNetTotal =
          (sale['total'] as int) - (sale['returned'] as int) - total;
      final netPaid = (sale['paid'] as int) - (sale['refunded'] as int);
      final refund = netPaid > newNetTotal ? netPaid - newNetTotal : 0;
      await tx.update(
        'sales',
        {
          'returned': (sale['returned'] as int) + total,
          'refunded': (sale['refunded'] as int) + refund,
        },
        where: 'id=?',
        whereArgs: [saleId],
      );
      for (final item in returnedItems) {
        await tx.rawUpdate(
          'UPDATE sale_lines SET returned=returned+? WHERE id=?',
          [item.quantity, item.line['id']],
        );
        await tx.rawUpdate(
          'UPDATE products SET $location=$location+? WHERE id=?',
          [item.quantity, item.line['product_id']],
        );
        await _movement(
          tx,
          item.line['product_id'] as int,
          location,
          item.quantity,
          'Return for sale #$saleId',
        );
      }
      await tx.insert('sale_returns', {
        'sale_id': saleId,
        'created': DateTime.now().toUtc().toIso8601String(),
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'refund': refund,
        'refund_method': refundMethod,
      });
      return refund;
    });
  }

  Future<int> returnPurchase(
    int purchaseId,
    Map<int, int> quantities, {
    String refundMethod = 'cash',
  }) async {
    paymentMethod(refundMethod);
    if (quantities.isEmpty) {
      throw const FormatException('Choose at least one item to return.');
    }
    return db.transaction((tx) async {
      final rows = await tx.query(
        'purchases',
        where: 'id=?',
        whereArgs: [purchaseId],
      );
      if (rows.isEmpty) {
        throw const FormatException('Purchase no longer exists.');
      }
      final purchase = rows.single;
      final location = purchase['location'] as String;
      _location(location);
      int total = 0;
      for (final entry in quantities.entries) {
        if (entry.value <= 0) {
          throw const FormatException('Return quantity must be positive.');
        }
        final lines = await tx.query(
          'purchase_lines',
          where: 'id=? AND purchase_id=?',
          whereArgs: [entry.key, purchaseId],
        );
        if (lines.isEmpty) {
          throw const FormatException('Purchase item no longer exists.');
        }
        final line = lines.single;
        final available = (line['quantity'] as int) - (line['returned'] as int);
        if (entry.value > available) {
          throw FormatException(
            'Only $available ${line['name']} can be returned.',
          );
        }
        final changed = await tx.rawUpdate(
          'UPDATE products SET $location=$location-? WHERE id=? AND $location>=?',
          [entry.value, line['product_id'], entry.value],
        );
        if (changed != 1) {
          throw const FormatException(
            'Not enough stock at the original purchase location.',
          );
        }
        await tx.rawUpdate(
          'UPDATE purchase_lines SET returned=returned+? WHERE id=?',
          [entry.value, entry.key],
        );
        await _movement(
          tx,
          line['product_id'] as int,
          location,
          -entry.value,
          'Return for purchase #$purchaseId',
        );
        total += (line['cost'] as int) * entry.value;
      }
      final balance = purchaseBalance(purchase);
      final refund = total > balance ? total - balance : 0;
      await tx.update(
        'purchases',
        {
          'returned': (purchase['returned'] as int) + total,
          'refunded': (purchase['refunded'] as int) + refund,
        },
        where: 'id=?',
        whereArgs: [purchaseId],
      );
      await tx.insert('purchase_returns', {
        'purchase_id': purchaseId,
        'created': DateTime.now().toUtc().toIso8601String(),
        'total': total,
        'refund': refund,
        'refund_method': refundMethod,
      });
      return refund;
    });
  }

  Future<DbRow?> openCashSession(String location) async {
    _location(location);
    final rows = await db.query(
      'cash_sessions',
      where: 'location=? AND closed IS NULL',
      whereArgs: [location],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<DbRow>> cashSessionHistory(String location) {
    _location(location);
    return db.query(
      'cash_sessions',
      where: 'location=? AND closed IS NOT NULL',
      whereArgs: [location],
      orderBy: 'id DESC',
    );
  }

  Future<int> startCashSession(String location, int opening) async {
    _location(location);
    if (opening < 0 || opening > 9999999999) {
      throw const FormatException('Enter a valid opening cash amount.');
    }
    try {
      return await db.transaction((tx) async {
        if ((await tx.query(
          'cash_sessions',
          columns: ['id'],
          where: 'location=? AND closed IS NULL',
          whereArgs: [location],
          limit: 1,
        )).isNotEmpty) {
          throw const FormatException('Close the current cash session first.');
        }
        return tx.insert('cash_sessions', {
          'opened': DateTime.now().toUtc().toIso8601String(),
          'location': location,
          'opening': opening,
          'expected': opening,
        });
      });
    } on DatabaseException {
      throw const FormatException('Close the current cash session first.');
    }
  }

  static Future<Map<String, int>> _cashTotals(
    DatabaseExecutor executor,
    String location,
    String opened,
    String until,
  ) async {
    Future<int> value(String sql) async =>
        ((await executor.rawQuery(sql, [
                  location,
                  opened,
                  until,
                ])).single['value']
                as num)
            .toInt();
    return {
      'sales_receipts': await value(
        '''SELECT COALESCE(SUM(p.amount),0) value FROM payments p
           JOIN sales s ON s.id=p.sale_id
           WHERE s.location=? AND p.created>=? AND p.created<? AND p.method='cash' ''',
      ),
      'purchase_refunds': await value(
        '''SELECT COALESCE(SUM(r.refund),0) value FROM purchase_returns r
           JOIN purchases p ON p.id=r.purchase_id
           WHERE p.location=? AND r.created>=? AND r.created<? AND r.refund_method='cash' ''',
      ),
      'expenses': await value(
        '''SELECT COALESCE(SUM(amount),0) value FROM expenses
           WHERE location=? AND created>=? AND created<? AND method='cash' ''',
      ),
      'supplier_payments': await value(
        '''SELECT COALESCE(SUM(sp.amount),0) value FROM supplier_payments sp
           JOIN purchases p ON p.id=sp.purchase_id
           WHERE p.location=? AND sp.created>=? AND sp.created<? AND sp.method='cash' ''',
      ),
      'sales_refunds':
          await value(
            '''SELECT COALESCE(SUM(r.refund),0) value FROM sale_returns r
           JOIN sales s ON s.id=r.sale_id
           WHERE s.location=? AND r.created>=? AND r.created<? AND r.refund_method='cash' ''',
          ) +
          await value(
            '''SELECT COALESCE(SUM(c.refund),0) value FROM sale_cancellations c
           JOIN sales s ON s.id=c.sale_id
           WHERE s.location=? AND c.created>=? AND c.created<? AND c.refund_method='cash' ''',
          ),
    };
  }

  Future<Map<String, int>> cashSessionSummary(int sessionId) => db.transaction((
    tx,
  ) async {
    final rows = await tx.query(
      'cash_sessions',
      where: 'id=?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) throw const FormatException('Cash session not found.');
    final session = rows.single;
    if (session['closed'] != null) {
      return {
        for (final key in [
          'opening',
          'sales_receipts',
          'purchase_refunds',
          'expenses',
          'supplier_payments',
          'sales_refunds',
          'expected',
        ])
          key: session[key] as int,
      };
    }
    final totals = await _cashTotals(
      tx,
      session['location'] as String,
      session['opened'] as String,
      DateTime.now().toUtc().toIso8601String(),
    );
    return {
      'opening': session['opening'] as int,
      ...totals,
      'expected':
          (session['opening'] as int) +
          totals['sales_receipts']! +
          totals['purchase_refunds']! -
          totals['expenses']! -
          totals['supplier_payments']! -
          totals['sales_refunds']!,
    };
  });

  Future<void> closeCashSession(int sessionId, int actual, String note) async {
    if (actual < 0 || actual > 9999999999) {
      throw const FormatException('Enter the actual cash counted.');
    }
    await db.transaction((tx) async {
      final rows = await tx.query(
        'cash_sessions',
        where: 'id=? AND closed IS NULL',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const FormatException('This cash session is already closed.');
      }
      final session = rows.single;
      final closed = DateTime.now().toUtc().toIso8601String();
      final totals = await _cashTotals(
        tx,
        session['location'] as String,
        session['opened'] as String,
        closed,
      );
      final expected =
          (session['opening'] as int) +
          totals['sales_receipts']! +
          totals['purchase_refunds']! -
          totals['expenses']! -
          totals['supplier_payments']! -
          totals['sales_refunds']!;
      await tx.update(
        'cash_sessions',
        {
          'closed': closed,
          ...totals,
          'expected': expected,
          'actual': actual,
          'note': note.trim(),
        },
        where: 'id=?',
        whereArgs: [sessionId],
      );
    });
  }

  Future<void> adjustStock(
    int product,
    int quantity,
    String location,
    String reason,
  ) async {
    _location(location);
    if (quantity <= 0 || quantity > 1000000 || reason.trim().isEmpty) {
      throw const FormatException('Enter a quantity and reason.');
    }
    await db.transaction((tx) async {
      final changed = await tx.rawUpdate(
        'UPDATE products SET $location=$location-? WHERE id=? AND $location>=?',
        [quantity, product, quantity],
      );
      if (changed != 1) throw const FormatException('Not enough stock.');
      await _movement(
        tx,
        product,
        location,
        -quantity,
        'Adjustment: ${reason.trim()}',
      );
    });
  }

  Future<List<DbRow>> stockAdjustments(int product) => db.query(
    'movements',
    where: "product_id=? AND reason LIKE 'Adjustment: %'",
    whereArgs: [product],
    orderBy: 'id DESC',
  );

  // Invoice cohort report: original invoice dates, with all recorded returns
  // and payments. Stock is current, never a historical stock reconstruction.
  Future<Map<String, int>> report({
    DateTime? start,
    DateTime? end,
    String? location,
  }) => db.transaction((tx) async {
    if (location != null) _location(location);
    if (start != null && end != null && !start.isBefore(end)) {
      throw const FormatException('Invalid report dates.');
    }
    final clauses = <String>[];
    final args = <Object?>[];
    if (start != null) {
      clauses.add('created>=?');
      args.add(start.toUtc().toIso8601String());
    }
    if (end != null) {
      clauses.add('created<?');
      args.add(end.toUtc().toIso8601String());
    }
    if (location != null) {
      clauses.add('location=?');
      args.add(location);
    }
    final where = clauses.isEmpty ? '' : ' WHERE ${clauses.join(' AND ')}';
    final saleClauses = ['COALESCE(cancelled,0)=0', ...clauses];
    final saleWhere = ' WHERE ${saleClauses.join(' AND ')}';
    Future<int> value(String sql, [List<Object?>? params]) async =>
        ((await tx.rawQuery(sql, params ?? args)).first['value'] as num)
            .toInt();
    final sales = 'SELECT id FROM sales$saleWhere';
    return {
      'net_sales': await value(
        'SELECT COALESCE(SUM(total-returned),0) value FROM sales$saleWhere',
      ),
      'sales_tax':
          await value(
            'SELECT COALESCE(SUM(tax),0) value FROM sales$saleWhere',
          ) -
          await value(
            'SELECT COALESCE(SUM(tax),0) value FROM sale_returns WHERE sale_id IN ($sales)',
          ),
      'gross_profit': await value(
        'SELECT COALESCE(SUM((price-cost)*(quantity-returned)-discount+(discount*returned/quantity)),0) value FROM sale_lines WHERE sale_id IN ($sales)',
      ),
      'purchases': await value(
        'SELECT COALESCE(SUM(total-returned),0) value FROM purchases$where',
      ),
      'expenses': await value(
        'SELECT COALESCE(SUM(amount),0) value FROM expenses$where',
      ),
      'receivables': await value(
        'SELECT COALESCE(SUM(total-returned-paid+refunded),0) value FROM sales$saleWhere',
      ),
      'payables': await value(
        'SELECT COALESCE(SUM(total-returned-paid+refunded),0) value FROM purchases$where',
      ),
      for (final method in supportedPaymentMethods)
        '${method}_received': await value(
          "SELECT COALESCE(SUM(amount),0) value FROM payments WHERE method='$method' AND sale_id IN ($sales)",
        ),
      'stock_value': await value(
        'SELECT COALESCE(SUM(cost*${location ?? '(shop+van)'}),0) value FROM products',
        [],
      ),
    };
  });
}
