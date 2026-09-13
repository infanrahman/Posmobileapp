part of 'main.dart';

class SuppliersScreen extends StatefulWidget {
  final PosStore store;
  const SuppliersScreen({super.key, required this.store});
  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<DbRow> suppliers = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final rows = await widget.store.suppliers();
    if (mounted) {
      setState(() {
        suppliers = rows;
        loading = false;
      });
    }
  }

  Future<void> add() => entryForm(
    context,
    'Add supplier',
    const [
      Entry('Supplier name'),
      Entry('Phone number', initial: '+966'),
      Entry('VAT / tax number'),
      Entry('Address'),
    ],
    (v) async {
      await widget.store.addSupplier(v[0], v[1], v[2], v[3]);
      await load();
    },
  );
  Future<void> edit(DbRow supplier) => entryForm(
    context,
    'Edit supplier',
    [
      Entry('Supplier name', initial: supplier['name'] as String),
      Entry('Phone number', initial: supplier['phone'] as String),
      Entry('VAT / tax number', initial: supplier['tax_number'] as String),
      Entry('Address', initial: supplier['address'] as String),
    ],
    (v) async {
      await widget.store.updateSupplier(
        supplier['id'] as int,
        v[0],
        v[1],
        v[2],
        v[3],
      );
      await load();
    },
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const UiText('Suppliers')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const UiText('Add supplier'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              UiText(
                'Supplier accounts',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              const UiText(
                'Contacts and purchase balances saved offline.',
                style: TextStyle(color: Color(0xFF71818A)),
              ),
              const SizedBox(height: 22),
              if (suppliers.isEmpty)
                operationEmpty(
                  context,
                  Icons.local_shipping_outlined,
                  'No suppliers yet',
                  'Add a supplier before recording a credit purchase.',
                ),
              ...suppliers.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      onTap: () => edit(s),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE8F2ED),
                        child: UiText(
                          (s['name'] as String).characters.first.toUpperCase(),
                          style: const TextStyle(color: teal),
                        ),
                      ),
                      title: Text(
                        s['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: UiText(
                        [
                          s['phone'],
                          s['tax_number'],
                        ].where((v) => '$v'.isNotEmpty).join(' • '),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          UiText(
                            money(s['balance'] as int),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const UiText(
                            'payable',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF71818A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}

class PurchasesScreen extends StatefulWidget {
  final PosStore store;
  final String location;
  const PurchasesScreen({
    super.key,
    required this.store,
    required this.location,
  });
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  List<DbRow> rows = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await widget.store.purchases();
    if (mounted) {
      setState(() {
        rows = result;
        loading = false;
      });
    }
  }

  Future<void> add() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PurchaseEditor(store: widget.store, location: widget.location),
      ),
    );
    await load();
  }

  Future<void> details(DbRow purchase) async {
    final lines = await widget.store.purchaseLines(purchase['id'] as int);
    if (!mounted) return;
    final pay = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UiText(
                  'Purchase #${purchase['id']}',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                UiText(
                  '${purchase['supplier_name']} • ${dateLabel(purchase['created'])}',
                ),
                const Divider(height: 28),
                ...lines.map(
                  (line) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(line['name'] as String),
                    subtitle: UiText(
                      '${line['quantity']} × ${money(line['cost'] as int)} • ${line['returned']} returned',
                    ),
                    trailing: UiText(
                      money((line['quantity'] as int) * (line['cost'] as int)),
                    ),
                  ),
                ),
                const Divider(),
                totalRow('Total', purchase['total'] as int, bold: true),
                totalRow('Paid', purchase['paid'] as int),
                totalRow('Returns', purchase['returned'] as int),
                totalRow(
                  'Supplier refunds received',
                  purchase['refunded'] as int,
                ),
                totalRow('Balance', purchaseBalance(purchase), bold: true),
                if (purchaseBalance(purchase) > 0)
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'pay'),
                    icon: const Icon(Icons.payments_outlined),
                    label: const UiText('Record supplier payment'),
                  ),
                if (lines.any(
                  (line) =>
                      (line['quantity'] as int) > (line['returned'] as int),
                ))
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'return'),
                    icon: const Icon(Icons.undo_rounded),
                    label: const UiText('Return purchase items'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (pay == 'return' && mounted) {
      final selected = await showModalBottomSheet<Map<int, int>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ReturnSheet(lines: lines, purchase: purchase),
      );
      if (selected != null && mounted) {
        try {
          final refund = await widget.store.returnPurchase(
            purchase['id'] as int,
            selected,
          );
          await load();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: UiText(
                  'Purchase return saved. Supplier refund received: ${money(refund)}',
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: UiText(
                  e is FormatException
                      ? e.message
                      : 'Could not save the return.',
                ),
              ),
            );
          }
        }
      }
    }
    if (pay == 'pay' && mounted) {
      await entryForm(
        context,
        'Pay supplier',
        [
          Entry(
            'Amount (SAR)',
            initial: (purchaseBalance(purchase) / 100).toStringAsFixed(2),
            numeric: true,
          ),
        ],
        (v) async {
          await widget.store.paySupplier(purchase['id'] as int, amount(v[0]));
          await load();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const UiText('Purchases')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const UiText('New purchase'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              UiText(
                'Purchase ledger',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              UiText(
                'Stock received into ${widget.location}.',
                style: const TextStyle(color: Color(0xFF71818A)),
              ),
              const SizedBox(height: 22),
              if (rows.isEmpty)
                operationEmpty(
                  context,
                  Icons.shopping_cart_outlined,
                  'No purchases yet',
                  'Record stock bought from a supplier.',
                ),
              ...rows.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFEEF1F8),
                        child: Icon(
                          Icons.shopping_cart_outlined,
                          color: Color(0xFF6477AA),
                        ),
                      ),
                      title: Text(
                        p['supplier_name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: UiText(
                        'PUR-${p['id'].toString().padLeft(5, '0')} • ${dateLabel(p['created'])} • ${p['location']}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          UiText(
                            money((p['total'] as int) - (p['returned'] as int)),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          UiText(
                            purchaseBalance(p) == 0
                                ? 'Paid'
                                : '${money(purchaseBalance(p))} due',
                            style: TextStyle(
                              fontSize: 11,
                              color: purchaseBalance(p) == 0
                                  ? teal
                                  : const Color(0xFFA96E1D),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => details(p),
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}

class PurchaseDraft {
  int quantity, cost;
  PurchaseDraft(this.quantity, this.cost);
}

class PurchaseEditor extends StatefulWidget {
  final PosStore store;
  final String location;
  const PurchaseEditor({
    super.key,
    required this.store,
    required this.location,
  });
  @override
  State<PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<PurchaseEditor> {
  List<DbRow> products = [], suppliers = [];
  final cart = <int, PurchaseDraft>{};
  final payment = TextEditingController(text: '0.00');
  int? supplier;
  String paymentMode = 'paid', query = '';
  bool loading = true, saving = false;
  bool scanning = false;
  String? error;
  int get total => products.fold(0, (sum, p) {
    final item = cart[p['id']];
    return sum + (item == null ? 0 : item.quantity * item.cost);
  });
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    payment.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final p = await widget.store.products();
    final s = await widget.store.suppliers();
    if (mounted) {
      setState(() {
        products = p;
        suppliers = s;
        loading = false;
      });
    }
  }

  Future<void> editItem(DbRow product) async {
    final existing = cart[product['id']];
    await entryForm(
      context,
      'Purchase ${product['name']}',
      [
        Entry('Quantity', initial: '${existing?.quantity ?? 1}', numeric: true),
        Entry(
          'Unit cost (SAR)',
          initial: ((existing?.cost ?? product['cost'] as int) / 100)
              .toStringAsFixed(2),
          numeric: true,
        ),
      ],
      (v) async {
        setState(
          () => cart[product['id'] as int] = PurchaseDraft(
            positiveQuantity(v[0]),
            amount(v[1]),
          ),
        );
      },
    );
  }

  Future<void> scanItem() async {
    if (scanning || saving) return;
    scanning = true;
    try {
      final code = await scanBarcode(context);
      if (code == null || !mounted) return;
      await editItem(productForBarcode(products, code));
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: UiText(e.message)));
      }
    } finally {
      scanning = false;
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.addPurchase(
        {
          for (final e in cart.entries)
            e.key: (quantity: e.value.quantity, cost: e.value.cost),
        },
        widget.location,
        supplier,
        paymentMode == 'paid'
            ? null
            : paymentMode == 'credit'
            ? 0
            : amount(payment.text),
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is FormatException
              ? e.message
              : 'Could not save this purchase.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = products.where(
      (p) => '${p['name']} ${p['sku']} ${p['barcode']}'.toLowerCase().contains(
        query.toLowerCase(),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const UiText('New purchase')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: saving,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: supplier,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Supplier'),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: UiText('Cash supplier'),
                      ),
                      ...suppliers.map(
                        (s) => DropdownMenuItem(
                          value: s['id'] as int,
                          child: Text(s['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => supplier = v),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      hintText: tr(context, 'Search products'),
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: tr(context, 'Scan barcode'),
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: saving ? null : scanItem,
                      ),
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 12),
                  if (products.isEmpty)
                    operationEmpty(
                      context,
                      Icons.inventory_2_outlined,
                      'No products available',
                      'Add products from the Stock tab first.',
                    ),
                  ...filtered.map((p) {
                    final item = cart[p['id']];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          title: Text(
                            p['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: UiText(
                            item == null
                                ? 'Current cost ${money(p['cost'] as int)}'
                                : '${item.quantity} × ${money(item.cost)}',
                          ),
                          trailing: item == null
                              ? const Icon(
                                  Icons.add_circle_outline,
                                  color: teal,
                                )
                              : UiText(
                                  money(item.quantity * item.cost),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                          onTap: () => editItem(p),
                          onLongPress: () =>
                              setState(() => cart.remove(p['id'])),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 18),
                  totalRow('Purchase total', total, bold: true),
                  const SizedBox(height: 18),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'paid', label: UiText('Paid')),
                      ButtonSegment(value: 'partial', label: UiText('Partial')),
                      ButtonSegment(value: 'credit', label: UiText('Credit')),
                    ],
                    selected: {paymentMode},
                    onSelectionChanged: (v) =>
                        setState(() => paymentMode = v.first),
                  ),
                  if (paymentMode == 'partial')
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: TextField(
                        controller: payment,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: tr(context, 'Amount paid (SAR)'),
                        ),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: UiText(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: saving || cart.isEmpty ? null : save,
                    icon: const Icon(Icons.check),
                    label: UiText(
                      saving ? 'Saving…' : 'Save purchase • ${money(total)}',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class ExpensesScreen extends StatefulWidget {
  final PosStore store;
  final String location;
  const ExpensesScreen({
    super.key,
    required this.store,
    required this.location,
  });
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<DbRow> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await widget.store.expenses();
    if (mounted) {
      setState(() {
        rows = result;
        loading = false;
      });
    }
  }

  Future<void> add() => entryForm(
    context,
    'Add expense',
    const [
      Entry('Category'),
      Entry('Description'),
      Entry('Amount (SAR)', numeric: true),
    ],
    (v) async {
      await widget.store.addExpense(v[0], v[1], amount(v[2]), widget.location);
      await load();
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const UiText('Expenses')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const UiText('Add expense'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              UiText(
                'Expense book',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              const UiText(
                'Fuel, meals, rent and other operating costs.',
                style: TextStyle(color: Color(0xFF71818A)),
              ),
              const SizedBox(height: 22),
              if (rows.isEmpty)
                operationEmpty(
                  context,
                  Icons.payments_outlined,
                  'No expenses yet',
                  'Record business costs to improve your profit report.',
                ),
              ...rows.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFF2DF),
                        child: Icon(
                          Icons.payments_outlined,
                          color: Color(0xFFA96E1D),
                        ),
                      ),
                      title: Text(
                        e['category'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: UiText(
                        '${e['note']} • ${e['location']} • ${dateLabel(e['created'])}',
                      ),
                      trailing: UiText(
                        money(e['amount'] as int),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}

class ReportsScreen extends StatelessWidget {
  final PosStore store;
  const ReportsScreen({super.key, required this.store});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const UiText('Reports')),
    body: FutureBuilder<Map<String, int>>(
      future: store.report(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final r = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            UiText(
              'Business reports',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            const UiText(
              'All recorded activity • shop and van combined',
              style: TextStyle(color: Color(0xFF71818A)),
            ),
            const SizedBox(height: 22),
            reportCard(
              context,
              'Net sales',
              r['net_sales']!,
              Icons.trending_up,
              teal,
            ),
            reportCard(
              context,
              'Gross profit',
              r['gross_profit']!,
              Icons.auto_graph,
              teal,
            ),
            reportCard(
              context,
              'Expenses',
              r['expenses']!,
              Icons.payments_outlined,
              const Color(0xFFA96E1D),
            ),
            reportCard(
              context,
              'Receivable',
              r['receivables']!,
              Icons.account_balance_wallet_outlined,
              const Color(0xFFA96E1D),
            ),
            reportCard(
              context,
              'Payable',
              r['payables']!,
              Icons.request_quote_outlined,
              const Color(0xFFA96E1D),
            ),
            reportCard(
              context,
              'Stock value at cost',
              r['stock_value']!,
              Icons.inventory_2_outlined,
              const Color(0xFF6477AA),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    totalRow('Purchases', r['purchases']!),
                    totalRow('Net sales tax', r['sales_tax']!),
                    totalRow(
                      'Profit after expenses',
                      r['gross_profit']! - r['expenses']!,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const UiText(
              'Gross profit uses the item cost saved at the time of sale. '
              'It is an operational estimate, not a filed tax statement.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF71818A),
                height: 1.5,
              ),
            ),
          ],
        );
      },
    ),
  );
}

Widget reportCard(
  BuildContext context,
  String title,
  int value,
  IconData icon,
  Color color,
) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: UiText(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          UiText(
            value < 0 ? '-${money(-value)}' : money(value),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  ),
);

class ReturnSheet extends StatefulWidget {
  final List<DbRow> lines;
  final DbRow? purchase;
  const ReturnSheet({super.key, required this.lines, this.purchase});
  @override
  State<ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<ReturnSheet> {
  final quantities = <int, int>{};
  int get purchaseReturnTotal => widget.lines.fold(
    0,
    (sum, line) =>
        sum + ((line['cost'] as int?) ?? 0) * (quantities[line['id']] ?? 0),
  );
  int get supplierRefund => widget.purchase == null
      ? 0
      : (purchaseReturnTotal - purchaseBalance(widget.purchase!)).clamp(
          0,
          purchaseReturnTotal,
        );
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiText(
              widget.purchase == null
                  ? 'Return sale items'
                  : 'Return purchase items',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            UiText(
              widget.purchase == null
                  ? 'Returned quantities go back to the original stock location.'
                  : 'Purchase returns remove stock from the original location and reduce the supplier balance.',
              style: const TextStyle(color: Color(0xFF71818A)),
            ),
            const SizedBox(height: 16),
            ...widget.lines
                .where(
                  (line) =>
                      (line['quantity'] as int) > (line['returned'] as int),
                )
                .map((line) {
                  final id = line['id'] as int;
                  final selected = quantities[id] ?? 0;
                  final available =
                      (line['quantity'] as int) - (line['returned'] as int);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(line['name'] as String),
                    subtitle: UiText('$available available to return'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: selected == 0
                              ? null
                              : () => setState(
                                  () => quantities[id] = selected - 1,
                                ),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        UiText('$selected'),
                        IconButton(
                          onPressed: selected == available
                              ? null
                              : () => setState(
                                  () => quantities[id] = selected + 1,
                                ),
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: teal,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            const SizedBox(height: 16),
            if (widget.purchase != null) ...[
              totalRow('Return value', purchaseReturnTotal),
              totalRow('Supplier refund received', supplierRefund),
              if (supplierRefund > 0)
                const UiText(
                  'Confirm only after receiving the supplier refund shown above.',
                ),
            ],
            FilledButton(
              onPressed: quantities.values.any((q) => q > 0)
                  ? () => Navigator.pop(context, {
                      for (final e in quantities.entries)
                        if (e.value > 0) e.key: e.value,
                    })
                  : null,
              child: const UiText('Confirm return'),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget operationEmpty(
  BuildContext context,
  IconData icon,
  String title,
  String subtitle,
) => Card(
  child: Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        Icon(icon, color: teal, size: 36),
        const SizedBox(height: 14),
        UiText(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        UiText(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF71818A)),
        ),
      ],
    ),
  ),
);
