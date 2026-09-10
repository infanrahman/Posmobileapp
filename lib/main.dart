import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'store.dart';

part 'sale_screen.dart';

const ink = Color(0xFF172D36);
const teal = Color(0xFF087F72);
const canvas = Color(0xFFF5F7F8);
String money(int fils) => 'SAR ${NumberFormat('#,##0.00').format(fils / 100)}';
String invoiceNo(int id) => 'INV-${id.toString().padLeft(5, '0')}';
String dateLabel(Object? value) => DateFormat(
  'dd MMM, h:mm a',
).format(DateTime.parse(value as String).toLocal());

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RihlaApp());
}

class RihlaApp extends StatelessWidget {
  final PosStore? store;
  const RihlaApp({super.key, this.store});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Rihla • Offline POS',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        primary: teal,
        surface: Colors.white,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 29,
          fontWeight: FontWeight.w800,
          color: ink,
          letterSpacing: -1,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        bodyMedium: TextStyle(color: ink, fontSize: 14),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE5EAEC)),
        ),
      ),
    ),
    home: Home(initialStore: store),
  );
}

class Home extends StatefulWidget {
  final PosStore? initialStore;
  const Home({super.key, this.initialStore});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  PosStore? store;
  List<DbRow> products = [], customers = [], sales = [];
  Map<String, String> settings = {};
  String location = 'shop', search = '';
  int page = 0;
  String? failure;
  bool loading = true;
  final searchController = TextEditingController();
  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      store = widget.initialStore ?? await PosStore.open();
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          failure = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> refresh() async {
    final p = await store!.products();
    final c = await store!.customers();
    final s = await store!.sales();
    final prefs = await store!.settings();
    if (mounted) {
      setState(() {
        products = p;
        customers = c;
        sales = s;
        settings = prefs;
        loading = false;
        failure = null;
      });
    }
  }

  void go(int tab) => setState(() {
    page = tab;
    search = '';
    searchController.clear();
  });
  bool matches(DbRow row, List<String> fields) => fields.any(
    (key) => '${row[key]}'.toLowerCase().contains(search.toLowerCase()),
  );
  void toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> newSale() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SaleScreen(store: store!, location: location, settings: settings),
      ),
    );
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (failure != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_rounded, size: 48, color: teal),
                  const SizedBox(height: 16),
                  const Text('Could not open your local data'),
                  Text(failure!),
                  FilledButton(
                    onPressed: initialize,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: teal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.route_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text(
              'rihla',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
        actions: [
          const Chip(
            avatar: Icon(Icons.offline_pin_rounded, size: 16, color: teal),
            label: Text('On-device', style: TextStyle(fontSize: 12)),
            side: BorderSide.none,
            backgroundColor: Color(0xFFE7F3EF),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          settings['business'] ?? 'My business',
                          style: const TextStyle(color: Color(0xFF71818A)),
                        ),
                      ),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: const [
                          ButtonSegment(
                            value: 'shop',
                            label: Text('Shop'),
                            icon: Icon(Icons.storefront_outlined, size: 16),
                          ),
                          ButtonSegment(
                            value: 'van',
                            label: Text('Van'),
                            icon: Icon(Icons.local_shipping_outlined, size: 16),
                          ),
                        ],
                        selected: {location},
                        onSelectionChanged: (value) =>
                            setState(() => location = value.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ...switch (page) {
                    0 => dashboard(),
                    1 => salesPage(),
                    2 => stockPage(),
                    3 => customersPage(),
                    _ => morePage(),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: page == 4
          ? null
          : FloatingActionButton.extended(
              backgroundColor: teal,
              foregroundColor: Colors.white,
              onPressed: page == 2
                  ? addProduct
                  : page == 3
                  ? addCustomer
                  : newSale,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                page == 2
                    ? 'Add item'
                    : page == 3
                    ? 'Add customer'
                    : 'New sale',
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: go,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDDF0EA),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            label: 'Customers',
          ),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'More'),
        ],
      ),
    );
  }

  List<Widget> dashboard() {
    final now = DateTime.now();
    final localSales = sales.where((s) => s['location'] == location).toList();
    final today = localSales.where((s) {
      final d = DateTime.parse(s['created'] as String).toLocal();
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();
    final revenue = today.fold(0, (n, row) => n + (row['total'] as int));
    final due = localSales.fold(
      0,
      (n, row) => n + (row['total'] as int) - (row['paid'] as int),
    );
    final low = products.where((p) => (p[location] as int) <= 5).toList();
    return [
      Text(
        location == 'van'
            ? 'Ready for the road.'
            : 'Your business, at a glance.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 6),
      Text(
        DateFormat('EEEE, d MMMM yyyy').format(now),
        style: const TextStyle(color: Color(0xFF71818A)),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  color: Color(0xFF72DBB8),
                  size: 20,
                ),
                SizedBox(width: 9),
                Text(
                  "TODAY'S SALES",
                  style: TextStyle(
                    color: Color(0xFFB9D2D1),
                    letterSpacing: 1.4,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              money(revenue),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 33,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${today.length} sales recorded  •  ${location == 'shop' ? 'Shop counter' : 'Van inventory'}',
              style: const TextStyle(color: Color(0xFFB9D2D1)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: metric(
              'To collect',
              money(due),
              Icons.account_balance_wallet_outlined,
              const Color(0xFFA96E1D),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: metric(
              'Low stock',
              '${low.length} items',
              Icons.inventory_2_outlined,
              teal,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      section('Quick actions'),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: action(Icons.point_of_sale_rounded, 'Make a sale', newSale),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: action(Icons.swap_horiz_rounded, 'Move stock', () => go(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: action(
              Icons.person_add_alt_1_outlined,
              'Customer',
              addCustomer,
            ),
          ),
        ],
      ),
      const SizedBox(height: 26),
      section('Last 7 days'),
      const SizedBox(height: 12),
      SalesChart(sales: localSales),
      const SizedBox(height: 26),
      section('Recent sales', onTap: () => go(1)),
      const SizedBox(height: 12),
      if (localSales.isEmpty)
        empty(
          Icons.receipt_long_outlined,
          'Your first sale starts here',
          'Add your products, then create a sale. Every record stays on this device.',
        )
      else
        ...localSales.take(4).map(saleTile),
      const SizedBox(height: 20),
      const Text(
        'Works without internet. Shop and van data on this device are separate stock locations.',
        style: TextStyle(color: Color(0xFF71818A), fontSize: 12),
      ),
    ];
  }

  Widget metric(String label, String value, IconData icon, Color color) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Color(0xFF71818A))),
        ],
      ),
    ),
  );
  Widget action(IconData icon, String label, VoidCallback tap) => Card(
    child: InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
        child: Column(
          children: [
            Icon(icon, color: teal),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
  Widget section(String title, {VoidCallback? onTap}) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      if (onTap != null)
        TextButton(onPressed: onTap, child: const Text('View all')),
    ],
  );
  Widget searchField(String hint) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: TextField(
      controller: searchController,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        fillColor: Colors.white,
      ),
      onChanged: (s) => setState(() => search = s),
    ),
  );
  Widget heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(color: Color(0xFF71818A))),
    ],
  );
  Widget empty(IconData icon, String title, String subtitle) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, color: teal, size: 36),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF71818A)),
          ),
        ],
      ),
    ),
  );
  List<Widget> salesPage() {
    final filtered = sales
        .where(
          (s) =>
              s['location'] == location &&
              (matches(s, ['customer_name']) ||
                  invoiceNo(
                    s['id'] as int,
                  ).toLowerCase().contains(search.toLowerCase())),
        )
        .toList();
    return [
      heading('Sales ledger', 'Every sale. Every payment. Saved locally.'),
      searchField('Search invoice or customer'),
      if (filtered.isEmpty)
        empty(
          Icons.receipt_long_outlined,
          'No sales found',
          'Create a sale using the button below.',
        )
      else
        ...filtered.map(saleTile),
    ];
  }

  Widget saleTile(DbRow sale) {
    final due = (sale['total'] as int) - (sale['paid'] as int);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFEAF3F0),
            child: Icon(
              Icons.receipt_long_outlined,
              color: due == 0 ? teal : const Color(0xFFA96E1D),
            ),
          ),
          title: Text(
            sale['customer_name'] as String,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${invoiceNo(sale['id'] as int)}\n${dateLabel(sale['created'])}',
            style: const TextStyle(fontSize: 11, height: 1.6),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(sale['total'] as int),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                due == 0 ? 'Paid' : '${money(due)} due',
                style: TextStyle(
                  fontSize: 11,
                  color: due == 0 ? teal : const Color(0xFFA96E1D),
                ),
              ),
            ],
          ),
          onTap: () => receipt(sale),
        ),
      ),
    );
  }

  List<Widget> stockPage() {
    final filtered = products
        .where((p) => matches(p, ['name', 'sku']))
        .toList();
    return [
      heading(
        location == 'shop' ? 'Shop inventory' : 'Van inventory',
        'Receive stock or transfer between shop and van.',
      ),
      searchField('Search item name or SKU'),
      if (filtered.isEmpty)
        empty(
          Icons.inventory_2_outlined,
          'No items found',
          'Add an item with its selling price and opening stock.',
        ),
      ...filtered.map(
        (p) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 9,
              ),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEEF1F8),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFF6477AA),
                ),
              ),
              title: Text(
                p['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${p['sku']}  •  ${money(p['price'] as int)}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${p[location]} units',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    (p[location] as int) <= 5 ? 'Low stock' : 'In stock',
                    style: TextStyle(
                      fontSize: 11,
                      color: (p[location] as int) <= 5
                          ? const Color(0xFFA96E1D)
                          : teal,
                    ),
                  ),
                ],
              ),
              onTap: () => stockActions(p),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> customersPage() {
    final filtered = customers
        .where((c) => matches(c, ['name', 'phone', 'area']))
        .toList();
    return [
      heading(
        'Your customers',
        'Shop and van customers • credit balances combined',
      ),
      searchField('Search name, phone or area'),
      if (filtered.isEmpty)
        empty(
          Icons.people_outline,
          'Build your customer book',
          'Save customer details to track credit sales and collections.',
        ),
      ...filtered.map(
        (c) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE8F2ED),
                child: Text(
                  (c['name'] as String).characters.first.toUpperCase(),
                  style: const TextStyle(color: teal),
                ),
              ),
              title: Text(
                c['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [c['phone'], c['area']].where((s) => s != '').join(' • '),
              ),
              trailing: Text(
                money(c['balance'] as int),
                style: TextStyle(
                  color: c['balance'] == 0 ? teal : const Color(0xFFA96E1D),
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => showCustomer(c),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> morePage() => [
    heading('Business settings', 'A simple workspace for your daily trade.'),
    const SizedBox(height: 24),
    Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.storefront_outlined, color: teal),
            title: const Text('Business profile'),
            subtitle: Text(settings['business'] ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: editSettings,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.percent_rounded, color: teal),
            title: const Text('Sales tax'),
            subtitle: Text(
              '${(int.parse(settings['tax_bps'] ?? '0') / 100).toStringAsFixed(2)}% • prices exclude tax',
            ),
            onTap: editSettings,
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    empty(
      Icons.offline_pin_outlined,
      'Built to work offline',
      'Sales, stock and customers are stored in SQLite on this phone. No account or internet is needed for daily use.',
    ),
    const SizedBox(height: 20),
    const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Early version • Local data is not yet backed up or shared between devices. Saudi e-invoicing integration, Arabic, returns and printer support are planned. Use sample business data while testing.',
          style: TextStyle(color: Color(0xFF71818A), height: 1.6),
        ),
      ),
    ),
  ];

  Future<void> addProduct() => entryForm(
    context,
    'Add inventory item',
    [
      const Entry('Item name'),
      const Entry('SKU / barcode'),
      const Entry('Selling price (SAR)', initial: '0.00', numeric: true),
      const Entry('Opening quantity', initial: '0', numeric: true),
    ],
    (v) async {
      final qty = int.tryParse(v[3]);
      if (qty == null || qty < 0 || qty > 1000000) {
        throw const FormatException(
          'Enter an opening quantity from 0 to 1,000,000.',
        );
      }
      await store!.addProduct(v[0], v[1], amount(v[2]), qty, location);
      await refresh();
    },
  );
  Future<void> addCustomer() => entryForm(
    context,
    'Add customer',
    [
      const Entry('Customer / shop name'),
      const Entry('Phone number', initial: '+966'),
      const Entry('Area / route'),
    ],
    (v) async {
      await store!.addCustomer(v[0], v[1], v[2]);
      await refresh();
    },
  );
  Future<void> editSettings() => entryForm(
    context,
    'Business profile',
    [
      Entry('Business name', initial: settings['business']!),
      Entry(
        'Tax rate (%)',
        initial: (int.parse(settings['tax_bps']!) / 100).toStringAsFixed(2),
        numeric: true,
      ),
    ],
    (v) async {
      await store!.saveSettings(v[0], amount(v[1]));
      await refresh();
    },
  );
  Future<void> stockActions(DbRow p) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                p['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Shop: ${p['shop']} • Van: ${p['van']}'),
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: Text('Receive stock into $location'),
              onTap: () => Navigator.pop(c, 'receive'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(
                'Transfer $location → ${location == 'shop' ? 'van' : 'shop'}',
              ),
              onTap: () => Navigator.pop(c, 'transfer'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await entryForm(
      context,
      choice == 'receive' ? 'Receive stock' : 'Transfer stock',
      [const Entry('Quantity', numeric: true)],
      (v) async {
        if (choice == 'receive') {
          await store!.receiveStock(
            p['id'] as int,
            positiveQuantity(v[0]),
            location,
          );
        } else {
          await store!.transfer(
            p['id'] as int,
            positiveQuantity(v[0]),
            location,
          );
        }
        await refresh();
      },
    );
  }

  Future<void> showCustomer(DbRow c) async {
    final related = sales.where((s) => s['customer_id'] == c['id']).toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .7,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                c['name'] as String,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              Text('${c['phone']}  ${c['area']}'),
              const SizedBox(height: 12),
              Text('Outstanding: ${money(c['balance'] as int)}'),
              const SizedBox(height: 20),
              if (related.isEmpty)
                const Text('No sales for this customer yet.'),
              ...related.map(
                (s) => ListTile(
                  title: Text(invoiceNo(s['id'] as int)),
                  subtitle: Text(
                    '${s['location']} • ${dateLabel(s['created'])}',
                  ),
                  trailing: Text(
                    money((s['total'] as int) - (s['paid'] as int)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    receipt(s);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> receipt(DbRow sale) async {
    final lines = await store!.lines(sale['id'] as int);
    if (!mounted) return;
    final collect = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .78,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              const Icon(Icons.check_circle_rounded, color: teal, size: 40),
              const SizedBox(height: 12),
              Text(
                invoiceNo(sale['id'] as int),
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              Text(
                'Sales record • saved on this device',
                textAlign: TextAlign.center,
                style: const TextStyle(color: teal),
              ),
              const SizedBox(height: 24),
              Text(
                sale['customer_name'] as String,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              Text('${dateLabel(sale['created'])} • ${sale['location']}'),
              const Divider(height: 32),
              ...lines.map(
                (line) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(line['name'] as String),
                  subtitle: Text(
                    '${line['quantity']} × ${money(line['price'] as int)}',
                  ),
                  trailing: Text(
                    money((line['quantity'] as int) * (line['price'] as int)),
                  ),
                ),
              ),
              const Divider(),
              totalRow('Subtotal', sale['subtotal'] as int),
              totalRow(
                'Tax (${(sale['tax_bps'] as int) / 100}%)',
                sale['tax'] as int,
              ),
              totalRow('Total', sale['total'] as int, bold: true),
              totalRow('Paid', sale['paid'] as int),
              totalRow(
                'Balance due',
                (sale['total'] as int) - (sale['paid'] as int),
                bold: true,
              ),
              const SizedBox(height: 18),
              if (sale['paid'] != sale['total'])
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Record payment'),
                ),
              const SizedBox(height: 16),
              const Text(
                'Sales record for testing. Saudi e-invoicing is not configured.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF71818A)),
              ),
            ],
          ),
        ),
      ),
    );
    if (collect == true && mounted) {
      await entryForm(
        context,
        'Record customer payment',
        [
          Entry(
            'Amount received (SAR)',
            initial: (((sale['total'] as int) - (sale['paid'] as int)) / 100)
                .toStringAsFixed(2),
            numeric: true,
          ),
        ],
        (v) async {
          await store!.collect(sale['id'] as int, amount(v[0]));
          await refresh();
        },
      );
    }
  }
}

Widget totalRow(String label, int value, {bool bold = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 7),
  child: Row(
    children: [
      Expanded(child: Text(label)),
      Text(
        money(value),
        style: TextStyle(
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          fontSize: bold ? 18 : 14,
        ),
      ),
    ],
  ),
);

class SalesChart extends StatelessWidget {
  final List<DbRow> sales;
  const SalesChart({super.key, required this.sales});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(
      7,
      (i) => DateTime(now.year, now.month, now.day - 6 + i),
    );
    final totals = days
        .map(
          (day) => sales
              .where((s) {
                final date = DateTime.parse(s['created'] as String).toLocal();
                return date.year == day.year &&
                    date.month == day.month &&
                    date.day == day.day;
              })
              .fold(0, (n, s) => n + (s['total'] as int)),
        )
        .toList();
    final max = totals.fold(1, (a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              money(totals.fold(0, (a, b) => a + b)),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Total sales including configured tax',
              style: TextStyle(fontSize: 11, color: Color(0xFF71818A)),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 105,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(
                  7,
                  (i) => Expanded(
                    child: Tooltip(
                      message:
                          '${DateFormat('d MMM').format(days[i])}: ${money(totals[i])}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: totals[i] == 0
                                ? 3
                                : 8 + (totals[i] / max) * 65,
                            width: 22,
                            decoration: BoxDecoration(
                              color: i == 6 ? teal : const Color(0xFFBBDCD0),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            DateFormat('E').format(days[i]),
                            style: const TextStyle(
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
            ),
          ],
        ),
      ),
    );
  }
}

class Entry {
  final String label, initial;
  final bool numeric;
  const Entry(this.label, {this.initial = '', this.numeric = false});
}

Future<void> entryForm(
  BuildContext context,
  String title,
  List<Entry> fields,
  Future<void> Function(List<String>) save,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => EntrySheet(title: title, fields: fields, save: save),
  );
}

class EntrySheet extends StatefulWidget {
  final String title;
  final List<Entry> fields;
  final Future<void> Function(List<String>) save;
  const EntrySheet({
    super.key,
    required this.title,
    required this.fields,
    required this.save,
  });
  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  late final controllers = widget.fields
      .map((f) => TextEditingController(text: f.initial))
      .toList();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(controllers.map((c) => c.text.trim()).toList());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is FormatException
              ? e.message
              : '$e'.contains('UNIQUE')
              ? 'This SKU already exists. Use a different SKU.'
              : 'Could not save. Your changes were not applied. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              for (var i = 0; i < widget.fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextField(
                    controller: controllers[i],
                    enabled: !busy,
                    keyboardType: widget.fields[i].numeric
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: widget.fields[i].label,
                    ),
                    textInputAction: i == widget.fields.length - 1
                        ? TextInputAction.done
                        : TextInputAction.next,
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
