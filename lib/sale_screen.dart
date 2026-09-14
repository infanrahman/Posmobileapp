part of 'main.dart';

class SaleScreen extends StatefulWidget {
  final PosStore store;
  final String location;
  final Map<String, String> settings;
  final DbRow? document;
  const SaleScreen({
    super.key,
    required this.store,
    required this.location,
    required this.settings,
    this.document,
  });
  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  List<DbRow> products = [], customers = [], vans = [];
  final cart = <int, int>{};
  final lineDiscounts = <int, int>{};
  final savedPrices = <int, int>{};
  final paymentController = TextEditingController(text: '0.00');
  final splitCashController = TextEditingController(text: '0.00');
  final splitCardController = TextEditingController(text: '0.00');
  final discountController = TextEditingController(text: '0.00');
  String query = '', paymentMode = 'paid', selectedPaymentMethod = 'cash';
  String discountMode = 'fixed';
  int? customer;
  int? vanId;
  bool loading = true, saving = false;
  bool scanning = false;
  String? error;
  int get taxBps => int.parse(widget.settings['tax_bps'] ?? '0');
  int get itemsTotal => products.fold(
    0,
    (total, p) =>
        total +
        (savedPrices[p['id']] ?? p['price'] as int) * (cart[p['id']] ?? 0),
  );
  int get itemDiscountTotal => lineDiscounts.values.fold(0, (a, b) => a + b);
  int get discountedItemsTotal =>
      (itemsTotal - itemDiscountTotal).clamp(0, itemsTotal);
  int get discount {
    try {
      if (discountMode == 'percent') {
        final basisPoints = amount(discountController.text);
        if (basisPoints > 10000) return 0;
        return (discountedItemsTotal * basisPoints + 5000) ~/ 10000;
      }
      return amount(discountController.text);
    } on FormatException {
      return 0;
    }
  }

  int get subtotal => (discountedItemsTotal - discount).clamp(0, itemsTotal);
  String? get discountError {
    try {
      if (discountMode == 'percent') {
        final basisPoints = amount(discountController.text);
        return basisPoints > 10000 ? 'Enter a percentage from 0 to 100.' : null;
      }
      final value = amount(discountController.text);
      return value > discountedItemsTotal
          ? 'Discount exceeds the items total.'
          : null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  int get tax => (subtotal * taxBps + 5000) ~/ 10000;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    paymentController.dispose();
    splitCashController.dispose();
    splitCardController.dispose();
    discountController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final p = await widget.store.products();
      final c = await widget.store.customers();
      final availableVans = widget.location == 'van'
          ? await widget.store.vans(activeOnly: true)
          : <DbRow>[];
      if (availableVans.isNotEmpty) vanId = availableVans.first['id'] as int;
      if (widget.document != null) {
        final payload = widget.store.documentPayload(widget.document!);
        final savedCart = payload['cart'];
        if (savedCart is Map) {
          for (final entry in savedCart.entries) {
            final id = int.tryParse('${entry.key}');
            final quantity = entry.value is num
                ? (entry.value as num).toInt()
                : 0;
            if (id != null && quantity > 0 && p.any((row) => row['id'] == id)) {
              cart[id] = quantity;
            }
          }
        }
        final savedDiscounts = payload['line_discounts'];
        if (savedDiscounts is Map) {
          for (final entry in savedDiscounts.entries) {
            final id = int.tryParse('${entry.key}');
            final value = entry.value is num ? (entry.value as num).toInt() : 0;
            if (id != null && value > 0) lineDiscounts[id] = value;
          }
        }
        final prices = payload['unit_prices'];
        if (prices is Map) {
          for (final entry in prices.entries) {
            final id = int.tryParse('${entry.key}');
            final value = entry.value is num
                ? (entry.value as num).toInt()
                : -1;
            if (id != null && value >= 0) savedPrices[id] = value;
          }
        }
        customer = (payload['customer_id'] as num?)?.toInt();
        final savedVanId = (payload['van_id'] as num?)?.toInt();
        if (availableVans.any((row) => row['id'] == savedVanId)) {
          vanId = savedVanId;
        }
        paymentMode = '${payload['payment_mode'] ?? 'paid'}';
        selectedPaymentMethod = '${payload['payment_method'] ?? 'cash'}';
        discountMode = '${payload['discount_mode'] ?? 'fixed'}';
        discountController.text = '${payload['discount_value'] ?? '0.00'}';
        paymentController.text = '${payload['payment_value'] ?? '0.00'}';
        splitCashController.text = '${payload['split_cash'] ?? '0.00'}';
        splitCardController.text = '${payload['split_card'] ?? '0.00'}';
      }
      if (mounted) {
        setState(() {
          products = p;
          customers = c;
          vans = availableVans;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not load inventory. Reopen this sale to retry.';
        });
      }
    }
  }

  void change(DbRow p, int delta) {
    final id = p['id'] as int;
    final next = (cart[id] ?? 0) + delta;
    if (next > (p[widget.location] as int)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: UiText('No more stock available at this location.'),
        ),
      );
      return;
    }
    setState(() {
      if (next <= 0) {
        cart.remove(id);
        lineDiscounts.remove(id);
      } else {
        cart[id] = next;
      }
      error = null;
    });
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final invoiceTotal = subtotal + tax;
      final paid = switch (paymentMode) {
        'paid' => invoiceTotal,
        'credit' => 0,
        'split' =>
          amount(splitCashController.text) + amount(splitCardController.text),
        _ => amount(paymentController.text),
      };
      final breakdown = switch (paymentMode) {
        'credit' => <String, int>{},
        'split' => <String, int>{
          if (amount(splitCashController.text) > 0)
            'cash': amount(splitCashController.text),
          if (amount(splitCardController.text) > 0)
            'card': amount(splitCardController.text),
        },
        _ => <String, int>{if (paid > 0) selectedPaymentMethod: paid},
      };
      final id = await widget.store.checkout(
        Map.of(cart),
        widget.location,
        customer,
        taxBps,
        paid,
        discount: discount,
        paymentBreakdown: breakdown,
        lineDiscounts: Map.of(lineDiscounts),
        unitPrices: Map.of(savedPrices),
        vanId: vanId,
      );
      if (widget.document != null) {
        if (widget.document!['kind'] == 'held_sale') {
          await widget.store.deleteDocument(widget.document!['id'] as int);
        } else {
          await widget.store.finishDocument(widget.document!['id'] as int, id);
        }
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: UiText(
            '${invoiceNo(id)} saved. Stock and balances updated.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is FormatException
              ? e.message
              : 'Could not save the sale. Please try again.';
        });
      }
    }
  }

  Future<void> editItemDiscount(DbRow product) async {
    final id = product['id'] as int;
    final lineTotal =
        (savedPrices[id] ?? product['price'] as int) * (cart[id] ?? 0);
    await entryForm(
      context,
      'Item discount',
      [
        Entry(
          'Discount (SAR)',
          initial: ((lineDiscounts[id] ?? 0) / 100).toStringAsFixed(2),
          numeric: true,
        ),
      ],
      (values) async {
        final value = amount(values[0]);
        if (value < 0 || value > lineTotal) {
          throw const FormatException(
            'Item discount must be between zero and the line total.',
          );
        }
        setState(() {
          if (value == 0) {
            lineDiscounts.remove(id);
          } else {
            lineDiscounts[id] = value;
          }
        });
      },
    );
  }

  Future<void> saveForLater(String kind) async {
    if (cart.isEmpty) return;
    var saved = false;
    await entryForm(
      context,
      kind == 'quotation' ? 'Save quotation' : 'Hold sale',
      [
        Entry(
          'Document name',
          initial: kind == 'quotation'
              ? 'Quotation ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'
              : 'Held sale ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
        ),
        const Entry('Notes'),
      ],
      (values) async {
        final party = customer == null
            ? 'Walk-in customer'
            : customers.firstWhere((row) => row['id'] == customer)['name']
                  as String;
        if (widget.document != null && widget.document!['status'] == 'open') {
          await widget.store.deleteDocument(widget.document!['id'] as int);
        }
        await widget.store.saveDocument(
          kind: kind,
          name: values[0],
          partyId: customer,
          partyName: party,
          location: widget.location,
          total: subtotal + tax,
          notes: values[1],
          payload: {
            'cart': {
              for (final entry in cart.entries) '${entry.key}': entry.value,
            },
            'line_discounts': {
              for (final entry in lineDiscounts.entries)
                '${entry.key}': entry.value,
            },
            'unit_prices': {
              for (final entry in cart.entries)
                '${entry.key}':
                    savedPrices[entry.key] ??
                    products.firstWhere(
                          (row) => row['id'] == entry.key,
                        )['price']
                        as int,
            },
            'customer_id': customer,
            'van_id': vanId,
            'payment_mode': paymentMode,
            'payment_method': selectedPaymentMethod,
            'payment_value': paymentController.text,
            'split_cash': splitCashController.text,
            'split_card': splitCardController.text,
            'discount_mode': discountMode,
            'discount_value': discountController.text,
          },
        );
        saved = true;
      },
    );
    if (saved && mounted) Navigator.pop(context);
  }

  Future<void> scanItem() async {
    if (scanning || saving) return;
    scanning = true;
    try {
      final code = await scanBarcode(context);
      if (code == null || !mounted) return;
      final product = productForBarcode(products, code);
      final canAdd =
          (cart[product['id']] ?? 0) < (product[widget.location] as int);
      change(product, 1);
      if (canAdd) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: UiText('Added ${product['name']} to the sale.')),
        );
      }
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

  Future<void> close() async {
    if (cart.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const UiText('Discard this sale?'),
        content: const UiText(
          'This unsaved cart will be cleared. Your inventory has not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const UiText('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const UiText('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(cart.clear);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = products
        .where(
          (p) => '${p['name']} ${p['sku']} ${p['barcode']}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    return PopScope(
      canPop: !saving && cart.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !saving) close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: saving ? null : close,
            icon: const Icon(Icons.close),
          ),
          title: UiText(
            widget.document?['kind'] == 'quotation'
                ? 'Convert quotation'
                : widget.document?['kind'] == 'held_sale'
                ? 'Resume held sale'
                : 'New sale',
          ),
          actions: [
            PopupMenuButton<String>(
              enabled: !saving && cart.isNotEmpty,
              onSelected: saveForLater,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'held_sale', child: UiText('Hold sale')),
                PopupMenuItem(
                  value: 'quotation',
                  child: UiText('Save quotation'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Chip(
                label: UiText(
                  widget.location == 'shop' ? 'Shop stock' : 'Van stock',
                ),
              ),
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : AbsorbPointer(
                absorbing: saving,
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          DropdownButtonFormField<int>(
                            initialValue: customer,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: tr(context, 'Customer'),
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
                                child: UiText('Walk-in customer'),
                              ),
                              ...customers.map(
                                (c) => DropdownMenuItem(
                                  value: c['id'] as int,
                                  child: Text(
                                    c['name'] as String,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() => customer = v),
                          ),
                          if (widget.location == 'van') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              initialValue: vanId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: tr(context, 'Van / salesperson'),
                                prefixIcon: const Icon(
                                  Icons.local_shipping_outlined,
                                ),
                              ),
                              items: [
                                for (final van in vans)
                                  DropdownMenuItem(
                                    value: van['id'] as int,
                                    child: Text(
                                      [van['name'], van['salesperson']]
                                          .where((value) => '$value'.isNotEmpty)
                                          .join(' • '),
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => vanId = value),
                            ),
                          ],
                          const SizedBox(height: 22),
                          UiText(
                            'Add items',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            decoration: InputDecoration(
                              hintText: tr(context, 'Search item or SKU'),
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
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: UiText(
                                'Add items from the Stock tab before making a sale.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (products.isNotEmpty && filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: UiText('No matching items.'),
                            ),
                          ...filtered.map(
                            (p) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p['name'] as String,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            UiText(
                                              '${money(savedPrices[p['id']] ?? p['price'] as int)} • ${p[widget.location]} available',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF71818A),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: tr(
                                          context,
                                          'Remove one ${p['name']}',
                                        ),
                                        onPressed: (cart[p['id']] ?? 0) == 0
                                            ? null
                                            : () => change(p, -1),
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: teal,
                                        ),
                                      ),
                                      UiText(
                                        '${cart[p['id']] ?? 0}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: tr(
                                          context,
                                          'Add one ${p['name']}',
                                        ),
                                        onPressed:
                                            (p[widget.location] as int) == 0
                                            ? null
                                            : () => change(p, 1),
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          color: teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          UiText(
                            'Sale summary',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  ...products
                                      .where((p) => cart.containsKey(p['id']))
                                      .map(
                                        (p) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: UiText(
                                                  '${cart[p['id']]} × ${p['name']}',
                                                ),
                                              ),
                                              UiText(
                                                money(
                                                  (savedPrices[p['id']] ??
                                                              p['price']
                                                                  as int) *
                                                          cart[p['id']]! -
                                                      (lineDiscounts[p['id']] ??
                                                          0),
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: tr(
                                                  context,
                                                  'Item discount',
                                                ),
                                                onPressed: () =>
                                                    editItemDiscount(p),
                                                icon: const Icon(
                                                  Icons.discount_outlined,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  totalRow('Items total', itemsTotal),
                                  if (itemDiscountTotal > 0)
                                    totalRow(
                                      'Item discounts',
                                      -itemDiscountTotal,
                                    ),
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(
                                        value: 'fixed',
                                        label: UiText('Fixed SAR'),
                                      ),
                                      ButtonSegment(
                                        value: 'percent',
                                        label: UiText('Percentage'),
                                      ),
                                    ],
                                    selected: {discountMode},
                                    onSelectionChanged: (value) => setState(() {
                                      discountMode = value.first;
                                      discountController.text = '0.00';
                                    }),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: discountController,
                                    enabled: !saving,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: tr(
                                        context,
                                        discountMode == 'percent'
                                            ? 'Discount (%)'
                                            : 'Discount (SAR)',
                                      ),
                                      helperText: tr(
                                        context,
                                        'Discount is applied before tax.',
                                      ),
                                      errorText: discountError == null
                                          ? null
                                          : tr(context, discountError!),
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                  totalRow('Subtotal', subtotal),
                                  totalRow('Tax (${taxBps / 100}%)', tax),
                                  const Divider(),
                                  totalRow('Total', subtotal + tax, bold: true),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          UiText(
                            'Payment',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'paid',
                                label: UiText('Paid'),
                              ),
                              ButtonSegment(
                                value: 'partial',
                                label: UiText('Partial'),
                              ),
                              ButtonSegment(
                                value: 'split',
                                label: UiText('Split'),
                              ),
                              ButtonSegment(
                                value: 'credit',
                                label: UiText('Credit'),
                              ),
                            ],
                            selected: {paymentMode},
                            onSelectionChanged: (v) =>
                                setState(() => paymentMode = v.first),
                          ),
                          const SizedBox(height: 14),
                          if (paymentMode == 'paid' || paymentMode == 'partial')
                            DropdownButtonFormField<String>(
                              initialValue: selectedPaymentMethod,
                              decoration: InputDecoration(
                                labelText: tr(context, 'Payment method'),
                              ),
                              items: [
                                for (final method in supportedPaymentMethods)
                                  DropdownMenuItem(
                                    value: method,
                                    child: UiText(method),
                                  ),
                              ],
                              onChanged: (value) => setState(
                                () => selectedPaymentMethod = value ?? 'cash',
                              ),
                            ),
                          if (paymentMode == 'partial')
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: TextField(
                                controller: paymentController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: tr(
                                    context,
                                    'Amount received (SAR)',
                                  ),
                                ),
                              ),
                            ),
                          if (paymentMode == 'split') ...[
                            TextField(
                              controller: splitCashController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: tr(context, 'Cash amount (SAR)'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: splitCardController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: tr(context, 'Card amount (SAR)'),
                              ),
                            ),
                          ],
                          if (paymentMode == 'partial' ||
                              paymentMode == 'credit')
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: UiText(
                                'Select a named customer to keep an unpaid balance.',
                                style: TextStyle(color: Color(0xFF71818A)),
                              ),
                            ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: UiText(
                                error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed:
                                saving || cart.isEmpty || discountError != null
                                ? null
                                : save,
                            icon: Icon(
                              saving
                                  ? Icons.hourglass_top
                                  : Icons.check_rounded,
                            ),
                            label: UiText(
                              saving
                                  ? 'Saving locally…'
                                  : widget.document?['kind'] == 'quotation'
                                  ? 'Convert to sale • ${money(subtotal + tax)}'
                                  : 'Complete sale • ${money(subtotal + tax)}',
                            ),
                          ),
                          const SizedBox(height: 12),
                          const UiText(
                            'Saved on this device. No internet required.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF71818A),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
