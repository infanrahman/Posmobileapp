import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef DbRow = Map<String, Object?>;

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

class PosStore {
  final Database db;
  PosStore(this.db);

  static Future<PosStore> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final database = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'rihla.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE products (
            id INTEGER PRIMARY KEY, name TEXT NOT NULL,
            sku TEXT NOT NULL UNIQUE, price INTEGER NOT NULL CHECK(price >= 0),
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
            tax_bps INTEGER NOT NULL)''');
          await db.execute(
            '''CREATE TABLE sale_lines (
            id INTEGER PRIMARY KEY, sale_id INTEGER NOT NULL REFERENCES sales(id),
            product_id INTEGER NOT NULL REFERENCES products(id),
            name TEXT NOT NULL, quantity INTEGER NOT NULL, price INTEGER NOT NULL)''',
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
        },
      ),
    );
    return PosStore(database);
  }

  Future<List<DbRow>> products() =>
      db.query('products', orderBy: 'name COLLATE NOCASE');
  Future<List<DbRow>> customers() => db.rawQuery(
    '''SELECT c.*,
    COALESCE(SUM(s.total-s.paid),0) AS balance FROM customers c
    LEFT JOIN sales s ON s.customer_id=c.id GROUP BY c.id ORDER BY c.name COLLATE NOCASE''',
  );
  Future<List<DbRow>> sales() => db.query('sales', orderBy: 'id DESC');
  Future<List<DbRow>> lines(int sale) =>
      db.query('sale_lines', where: 'sale_id=?', whereArgs: [sale]);
  Future<Map<String, String>> settings() async => {
    for (final row in await db.query('settings'))
      row['key'] as String: row['value'] as String,
  };

  Future<void> saveSettings(String business, int taxBps) async {
    if (business.trim().isEmpty || taxBps < 0 || taxBps > 10000) {
      throw const FormatException(
        'Enter a business name and a tax rate from 0 to 100.',
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
    });
  }

  Future<void> addProduct(
    String name,
    String sku,
    int price,
    int stock,
    String location,
  ) async {
    _location(location);
    if (name.trim().isEmpty || sku.trim().isEmpty || price < 0 || stock < 0) {
      throw const FormatException(
        'Name, unique SKU, price and stock are required.',
      );
    }
    await db.transaction((tx) async {
      final id = await tx.insert('products', {
        'name': name.trim(),
        'sku': sku.trim().toUpperCase(),
        'price': price,
        location: stock,
      });
      if (stock > 0) await _movement(tx, id, location, stock, 'Opening stock');
    });
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
    int? payment,
  ) async {
    _location(location);
    if (cart.isEmpty) throw const FormatException('Add an item to the sale.');
    if (taxBps < 0 || taxBps > 10000) {
      throw const FormatException('Invalid tax rate.');
    }
    return db.transaction((tx) async {
      String customerName = 'Walk-in customer';
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
      int subtotal = 0;
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
        subtotal += (row['price'] as int) * entry.value;
        items.add({
          'product_id': entry.key,
          'name': row['name'],
          'quantity': entry.value,
          'price': row['price'],
        });
      }
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
      final id = await tx.insert('sales', {
        'created': DateTime.now().toUtc().toIso8601String(),
        'customer_id': customer,
        'customer_name': customerName,
        'location': location,
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'paid': paid,
        'tax_bps': taxBps,
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
      if (paid > 0) {
        await tx.insert('payments', {
          'sale_id': id,
          'amount': paid,
          'created': DateTime.now().toUtc().toIso8601String(),
        });
      }
      return id;
    });
  }

  Future<void> collect(int sale, int payment) async {
    if (payment <= 0) {
      throw const FormatException('Payment must be greater than zero.');
    }
    await db.transaction((tx) async {
      final changed = await tx.rawUpdate(
        'UPDATE sales SET paid=paid+? WHERE id=? AND total-paid>=?',
        [payment, sale, payment],
      );
      if (changed != 1) {
        throw const FormatException('Payment exceeds the outstanding balance.');
      }
      await tx.insert('payments', {
        'sale_id': sale,
        'amount': payment,
        'created': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }
}
