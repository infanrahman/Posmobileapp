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
        version: 2,
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
        },
      ),
    );
    return PosStore(database);
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
    COALESCE(SUM(s.total-s.returned-s.paid+s.refunded),0) AS balance FROM customers c
    LEFT JOIN sales s ON s.customer_id=c.id GROUP BY c.id ORDER BY c.name COLLATE NOCASE''',
  );
  Future<List<DbRow>> sales() => db.query('sales', orderBy: 'id DESC');
  Future<List<DbRow>> lines(int sale) =>
      db.query('sale_lines', where: 'sale_id=?', whereArgs: [sale]);
  Future<List<DbRow>> suppliers() =>
      db.rawQuery('''SELECT s.*, COALESCE(SUM(p.total-p.paid),0) AS balance
    FROM suppliers s LEFT JOIN purchases p ON p.supplier_id=s.id
    GROUP BY s.id ORDER BY s.name COLLATE NOCASE''');
  Future<List<DbRow>> purchases() => db.query('purchases', orderBy: 'id DESC');
  Future<List<DbRow>> purchaseLines(int purchase) =>
      db.query('purchase_lines', where: 'purchase_id=?', whereArgs: [purchase]);
  Future<List<DbRow>> expenses() => db.query('expenses', orderBy: 'id DESC');
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
  }) async {
    _location(location);
    if (name.trim().isEmpty ||
        sku.trim().isEmpty ||
        price < 0 ||
        cost < 0 ||
        stock < 0) {
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
    int cost,
  ) async {
    if (name.trim().isEmpty || sku.trim().isEmpty || price < 0 || cost < 0) {
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
          'cost': row['cost'],
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
        '''UPDATE sales SET paid=paid+? WHERE id=?
        AND total-returned-paid+refunded>=?''',
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

  Future<int> addPurchase(
    Map<int, ({int quantity, int cost})> cart,
    String location,
    int? supplier,
    int? payment,
  ) async {
    _location(location);
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
        });
      }
      return id;
    });
  }

  Future<void> paySupplier(int purchase, int payment) async {
    if (payment <= 0) {
      throw const FormatException('Payment must be greater than zero.');
    }
    await db.transaction((tx) async {
      final changed = await tx.rawUpdate(
        'UPDATE purchases SET paid=paid+? WHERE id=? AND total-paid>=?',
        [payment, purchase, payment],
      );
      if (changed != 1) {
        throw const FormatException('Payment exceeds the purchase balance.');
      }
      await tx.insert('supplier_payments', {
        'purchase_id': purchase,
        'created': DateTime.now().toUtc().toIso8601String(),
        'amount': payment,
      });
    });
  }

  Future<void> addExpense(
    String category,
    String note,
    int value,
    String location,
  ) async {
    _location(location);
    if (category.trim().isEmpty || value <= 0) {
      throw const FormatException('Expense category and amount are required.');
    }
    await db.insert('expenses', {
      'created': DateTime.now().toUtc().toIso8601String(),
      'category': category.trim(),
      'note': note.trim(),
      'location': location,
      'amount': value,
    });
  }

  Future<int> returnSale(int saleId, Map<int, int> quantities) async {
    if (quantities.isEmpty) {
      throw const FormatException('Choose at least one item to return.');
    }
    return db.transaction((tx) async {
      final sales = await tx.query('sales', where: 'id=?', whereArgs: [saleId]);
      if (sales.isEmpty) throw const FormatException('Sale no longer exists.');
      final sale = sales.first;
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
        subtotal += (line['price'] as int) * entry.value;
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
      });
      return refund;
    });
  }

  Future<Map<String, int>> report() async {
    Future<int> value(String sql) async =>
        (await db.rawQuery(sql)).first['value'] as int;
    return {
      'net_sales': await value(
        'SELECT COALESCE(SUM(total-returned),0) value FROM sales',
      ),
      'sales_tax': await value(
        '''SELECT COALESCE((SELECT SUM(tax) FROM sales),0)-
        COALESCE((SELECT SUM(tax) FROM sale_returns),0) value''',
      ),
      'gross_profit': await value(
        'SELECT COALESCE(SUM((price-cost)*(quantity-returned)),0) value FROM sale_lines',
      ),
      'purchases': await value(
        'SELECT COALESCE(SUM(total),0) value FROM purchases',
      ),
      'expenses': await value(
        'SELECT COALESCE(SUM(amount),0) value FROM expenses',
      ),
      'receivables': await value(
        'SELECT COALESCE(SUM(total-returned-paid+refunded),0) value FROM sales',
      ),
      'payables': await value(
        'SELECT COALESCE(SUM(total-paid),0) value FROM purchases',
      ),
      'stock_value': await value(
        'SELECT COALESCE(SUM(cost*(shop+van)),0) value FROM products',
      ),
    };
  }
}
