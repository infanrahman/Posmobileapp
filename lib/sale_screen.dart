part of 'main.dart';

class SaleScreen extends StatefulWidget {
  final PosStore store;
  final String location;
  final Map<String, String> settings;
  const SaleScreen({
    super.key,
    required this.store,
    required this.location,
    required this.settings,
  });
  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  List<DbRow> products = [], customers = [];
  final cart = <int, int>{};
  final paymentController = TextEditingController(text: '0.00');
  String query = '', paymentMode = 'paid';
  int? customer;
  bool loading = true, saving = false;
  String? error;
  int get taxBps => int.parse(widget.settings['tax_bps'] ?? '0');
  int get subtotal => products.fold(
    0,
    (total, p) => total + (p['price'] as int) * (cart[p['id']] ?? 0),
  );
  int get tax => (subtotal * taxBps + 5000) ~/ 10000;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    paymentController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final p = await widget.store.products();
      final c = await widget.store.customers();
      if (mounted) {
        setState(() {
          products = p;
          customers = c;
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
          content: Text('No more stock available at this location.'),
        ),
      );
      return;
    }
    setState(() {
      if (next <= 0) {
        cart.remove(id);
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
      final id = await widget.store.checkout(
        Map.of(cart),
        widget.location,
        customer,
        taxBps,
        paymentMode == 'paid'
            ? null
            : paymentMode == 'credit'
            ? 0
            : amount(paymentController.text),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${invoiceNo(id)} saved. Stock and balances updated.'),
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

  Future<void> close() async {
    if (cart.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this sale?'),
        content: const Text(
          'This unsaved cart will be cleared. Your inventory has not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
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
          (p) => '${p['name']} ${p['sku']}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
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
          title: const Text('New sale'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Chip(
                label: Text(
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
                            decoration: const InputDecoration(
                              labelText: 'Customer',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
                                child: Text('Walk-in customer'),
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
                          const SizedBox(height: 22),
                          Text(
                            'Add items',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            decoration: const InputDecoration(
                              hintText: 'Search item or SKU',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (v) => setState(() => query = v),
                          ),
                          const SizedBox(height: 12),
                          if (products.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Add items from the Stock tab before making a sale.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (products.isNotEmpty && filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No matching items.'),
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
                                            Text(
                                              '${money(p['price'] as int)} • ${p[widget.location]} available',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF71818A),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove one ${p['name']}',
                                        onPressed: (cart[p['id']] ?? 0) == 0
                                            ? null
                                            : () => change(p, -1),
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: teal,
                                        ),
                                      ),
                                      Text(
                                        '${cart[p['id']] ?? 0}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Add one ${p['name']}',
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
                          Text(
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
                                                child: Text(
                                                  '${cart[p['id']]} × ${p['name']}',
                                                ),
                                              ),
                                              Text(
                                                money(
                                                  (p['price'] as int) *
                                                      cart[p['id']]!,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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
                          Text(
                            'Payment',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'paid', label: Text('Paid')),
                              ButtonSegment(
                                value: 'partial',
                                label: Text('Partial'),
                              ),
                              ButtonSegment(
                                value: 'credit',
                                label: Text('Credit'),
                              ),
                            ],
                            selected: {paymentMode},
                            onSelectionChanged: (v) =>
                                setState(() => paymentMode = v.first),
                          ),
                          const SizedBox(height: 14),
                          if (paymentMode == 'partial')
                            TextField(
                              controller: paymentController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Amount received (SAR)',
                              ),
                            ),
                          if (paymentMode != 'paid')
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text(
                                'Select a named customer to keep an unpaid balance.',
                                style: TextStyle(color: Color(0xFF71818A)),
                              ),
                            ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: saving || cart.isEmpty ? null : save,
                            icon: Icon(
                              saving
                                  ? Icons.hourglass_top
                                  : Icons.check_rounded,
                            ),
                            label: Text(
                              saving
                                  ? 'Saving locally…'
                                  : 'Complete sale • ${money(subtotal + tax)}',
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
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
