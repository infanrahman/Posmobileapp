import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:printing/printing.dart';
import 'backup.dart';
import 'report_export.dart';
import 'l10n.dart';
import 'invoice_pdf.dart';
import 'store.dart';
import 'barcode.dart';
import 'barcode_screen.dart';

part 'sale_screen.dart';
part 'operations_screens.dart';
part 'backup_screen.dart';

const appVersion = '0.9.0';

const ink = Color(0xFF172D36);
const teal = Color(0xFF087F72);
const canvas = Color(0xFFF5F7F8);
String money(int fils) => 'SAR ${NumberFormat('#,##0.00').format(fils / 100)}';
String invoiceNo(int id) => 'INV-${id.toString().padLeft(5, '0')}';
Future<String?> choosePaymentMethod(
  BuildContext context, {
  String title = 'Payment method',
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(title: UiText(title)),
        for (final method in supportedPaymentMethods)
          ListTile(
            leading: Icon(
              method == 'cash'
                  ? Icons.payments_outlined
                  : method == 'card'
                  ? Icons.credit_card
                  : Icons.account_balance_outlined,
            ),
            title: UiText(method),
            onTap: () => Navigator.pop(sheetContext, method),
          ),
      ],
    ),
  ),
);
String dateLabel(Object? value) => DateFormat(
  'dd MMM, h:mm a',
).format(DateTime.parse(value as String).toLocal());

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RihlaApp());
}

class RihlaApp extends StatefulWidget {
  final PosStore? store;
  const RihlaApp({super.key, this.store});
  @override
  State<RihlaApp> createState() => _RihlaAppState();
}

class _RihlaAppState extends State<RihlaApp> {
  Locale locale = const Locale('en');
  void changeLanguage(String language) {
    if (locale.languageCode != language && mounted) {
      setState(() => locale = Locale(language));
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Rihla • Offline POS',
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      fontFamily: locale.languageCode == 'ar' ? 'Amiri' : null,
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
    home: Home(initialStore: widget.store, onLanguageChanged: changeLanguage),
  );
}

class Home extends StatefulWidget {
  final PosStore? initialStore;
  final ValueChanged<String>? onLanguageChanged;
  const Home({super.key, this.initialStore, this.onLanguageChanged});
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
  bool exportingPdf = false;
  bool lowStockOnly = false;
  bool exportingReorderList = false;
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
      widget.onLanguageChanged?.call(prefs['language'] ?? 'en');
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
  void toast(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: UiText(text)));
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
                  const UiText('Could not open your local data'),
                  UiText(failure!),
                  FilledButton(
                    onPressed: initialize,
                    child: const UiText('Try again'),
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
            const Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'rihla',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          const Chip(
            avatar: Icon(Icons.offline_pin_rounded, size: 16, color: teal),
            label: UiText('On-device', style: TextStyle(fontSize: 12)),
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
                            label: UiText('Shop'),
                            icon: Icon(Icons.storefront_outlined, size: 16),
                          ),
                          ButtonSegment(
                            value: 'van',
                            label: UiText('Van'),
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
              label: UiText(
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
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: tr(context, 'Overview'),
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: tr(context, 'Sales'),
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: tr(context, 'Stock'),
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            label: tr(context, 'Customers'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.tune_rounded),
            label: tr(context, 'More'),
          ),
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
    final revenue = today.fold(
      0,
      (n, row) => n + (row['total'] as int) - (row['returned'] as int),
    );
    final due = localSales.fold(
      0,
      (n, row) =>
          n +
          (row['total'] as int) -
          (row['returned'] as int) -
          (row['paid'] as int) +
          (row['refunded'] as int),
    );
    final low = products
        .where(
          (p) =>
              (p['reorder_level'] as int) > 0 &&
              (p[location] as int) < (p['reorder_level'] as int),
        )
        .toList();
    return [
      UiText(
        location == 'van'
            ? 'Ready for the road.'
            : 'Your business, at a glance.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 6),
      UiText(
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
                UiText(
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
            UiText(
              money(revenue),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 33,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 14),
            UiText(
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
      const UiText(
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
          UiText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 4),
          UiText(label, style: const TextStyle(color: Color(0xFF71818A))),
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
            UiText(
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
        child: UiText(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      if (onTap != null)
        TextButton(onPressed: onTap, child: const UiText('View all')),
    ],
  );
  Widget searchField(String hint) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: TextField(
      controller: searchController,
      decoration: InputDecoration(
        hintText: tr(context, hint),
        prefixIcon: const Icon(Icons.search_rounded),
        fillColor: Colors.white,
      ),
      onChanged: (s) => setState(() => search = s),
    ),
  );
  Widget heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      UiText(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 6),
      UiText(subtitle, style: const TextStyle(color: Color(0xFF71818A))),
    ],
  );
  Widget empty(IconData icon, String title, String subtitle) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, color: teal, size: 36),
          const SizedBox(height: 16),
          UiText(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          UiText(
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
    final netTotal = (sale['total'] as int) - (sale['returned'] as int);
    final due = netTotal - (sale['paid'] as int) + (sale['refunded'] as int);
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
          subtitle: UiText(
            '${invoiceNo(sale['id'] as int)}\n${dateLabel(sale['created'])}',
            style: const TextStyle(fontSize: 11, height: 1.6),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              UiText(
                money(netTotal),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              UiText(
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
    final low = products
        .where(
          (p) =>
              (p['reorder_level'] as int) > 0 &&
              (p[location] as int) < (p['reorder_level'] as int),
        )
        .toList()
      ..sort(
        (a, b) =>
            ((b['reorder_level'] as int) - (b[location] as int)).compareTo(
              (a['reorder_level'] as int) - (a[location] as int),
            ),
      );
    final filtered = (lowStockOnly ? low : products)
        .where((p) => matches(p, ['name', 'sku', 'barcode']))
        .toList();
    return [
      heading(
        location == 'shop' ? 'Shop inventory' : 'Van inventory',
        'Receive stock or transfer between shop and van.',
      ),
      searchField('Search item name or SKU'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const UiText('Scan barcode'),
            onPressed: () async {
              final code = await scanBarcode(context);
              if (code == null || !mounted) return;
              try {
                await stockActions(productForBarcode(products, code));
              } on FormatException catch (e) {
                if (mounted) toast(e.message);
              }
            },
          ),
          FilterChip(
            selected: lowStockOnly,
            label: UiText('Low stock only (${low.length})'),
            avatar: const Icon(Icons.warning_amber_rounded, size: 18),
            onSelected: (value) => setState(() => lowStockOnly = value),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_outlined),
            label: const UiText('Export replenishment CSV'),
            onPressed: exportingReorderList || low.isEmpty
                ? null
                : () => exportReorderList(low),
          ),
        ],
      ),
      if (filtered.isEmpty)
        empty(
          Icons.inventory_2_outlined,
          lowStockOnly ? 'No low-stock items' : 'No items found',
          lowStockOnly
              ? 'Stock is at or above each item’s reorder level.'
              : 'Add an item with its selling price and opening stock.',
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
              subtitle: UiText('${p['sku']}  •  ${money(p['price'] as int)}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  UiText(
                    '${p[location]} units',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  UiText(
                    (p['reorder_level'] as int) > 0 &&
                            (p[location] as int) <
                                (p['reorder_level'] as int)
                        ? 'Low stock'
                        : 'In stock',
                    style: TextStyle(
                      fontSize: 11,
                      color: (p['reorder_level'] as int) > 0 &&
                              (p[location] as int) <
                                  (p['reorder_level'] as int)
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
                child: UiText(
                  (c['name'] as String).characters.first.toUpperCase(),
                  style: const TextStyle(color: teal),
                ),
              ),
              title: Text(
                c['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: UiText(
                [c['phone'], c['area']].where((s) => s != '').join(' • '),
              ),
              trailing: UiText(
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
    heading('Business tools', 'Purchases, expenses, suppliers and reports.'),
    const SizedBox(height: 8),
    const UiText(
      'Rihla POS • Version $appVersion',
      style: TextStyle(color: Color(0xFF71818A)),
    ),
    const SizedBox(height: 24),
    Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined, color: teal),
            title: const UiText('Purchases'),
            subtitle: const UiText('Receive stock and track supplier credit'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openOperation(
              PurchasesScreen(store: store!, location: location),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined, color: teal),
            title: const UiText('Suppliers'),
            subtitle: const UiText('Contacts and payable balances'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openOperation(SuppliersScreen(store: store!)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.payments_outlined, color: teal),
            title: const UiText('Expenses'),
            subtitle: const UiText('Record daily business costs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openOperation(
              ExpensesScreen(store: store!, location: location),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bar_chart_rounded, color: teal),
            title: const UiText('Reports'),
            subtitle: const UiText('Sales, profit, stock and balances'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openOperation(ReportsScreen(store: store!)),
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.storefront_outlined, color: teal),
            title: const UiText('Business profile'),
            subtitle: Text(settings['business'] ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: editSettings,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.backup_outlined, color: teal),
            title: const UiText('Backup and restore'),
            subtitle: const UiText(
              'Save your records or recover from a backup',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openOperation(BackupScreen(store: store!)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.language, color: teal),
            title: const UiText('Language'),
            subtitle: Text(
              settings['language'] == 'ar' ? 'العربية' : 'English',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final chosen = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const UiText('Language'),
                  children: [
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, 'en'),
                      child: const Text('English'),
                    ),
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, 'ar'),
                      child: const Text('العربية'),
                    ),
                  ],
                ),
              );
              if (chosen != null) {
                await store!.saveLanguage(chosen);
                await refresh();
              }
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.percent_rounded, color: teal),
            title: const UiText('Sales tax'),
            subtitle: UiText(
              '${(int.parse(settings['tax_bps'] ?? '0') / 100).toStringAsFixed(2)}% • prices exclude tax',
            ),
            onTap: editSettings,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.point_of_sale_outlined, color: teal),
            title: const UiText('Daily cashbook'),
            subtitle: const UiText('Opening cash, closing count and variance'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openOperation(
              CashbookScreen(store: store!, initialLocation: location),
            ),
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
        child: UiText(
          'Save regular backups. Devices do not sync automatically. Saudi e-invoicing and thermal printer support are not configured. Use sample business data while testing.',
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
      const Entry('SKU / barcode', scan: true),
      const Entry('Selling price (SAR)', initial: '0.00', numeric: true),
      const Entry('Purchase cost (SAR)', initial: '0.00', numeric: true),
      const Entry('Opening quantity', initial: '0', numeric: true),
      const Entry('Reorder level', initial: '6', numeric: true),
      const Entry('Barcode (optional)', scan: true),
    ],
    (v) async {
      final qty = int.tryParse(v[4]);
      if (qty == null || qty < 0 || qty > 1000000) {
        throw const FormatException(
          'Enter an opening quantity from 0 to 1,000,000.',
        );
      }
      await store!.addProduct(
        v[0],
        v[1],
        amount(v[2]),
        qty,
        location,
        cost: amount(v[3]),
        reorderLevel: _reorderLevel(v[5]),
        barcode: v[6],
      );
      await refresh();
    },
  );
  Future<void> openOperation(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    await refresh();
  }

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
              subtitle: UiText('Shop: ${p['shop']} • Van: ${p['van']}'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const UiText('Edit item details'),
              onTap: () => Navigator.pop(c, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: UiText('Receive stock into $location'),
              onTap: () => Navigator.pop(c, 'receive'),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const UiText('Stock adjustment'),
              onTap: () => Navigator.pop(c, 'adjust'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const UiText('Adjustment history'),
              onTap: () => Navigator.pop(c, 'history'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: UiText(
                'Transfer $location → ${location == 'shop' ? 'van' : 'shop'}',
              ),
              onTap: () => Navigator.pop(c, 'transfer'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'history') {
      final rows = await store!.stockAdjustments(p['id'] as int);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: UiText('Adjustment history')),
              if (rows.isEmpty)
                const ListTile(title: UiText('No adjustments yet')),
              for (final row in rows)
                ListTile(
                  title: UiText(
                    (row['reason'] as String).replaceFirst('Adjustment: ', ''),
                  ),
                  subtitle: Text(
                    '${tr(c, row['location'] as String)} • ${dateLabel(row['created'])}',
                  ),
                  trailing: Text('${row['quantity']}'),
                ),
            ],
          ),
        ),
      );
      return;
    }
    if (choice == 'adjust') {
      final reason = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: UiText('Reason for stock reduction')),
              for (final reason in ['Damaged', 'Expired', 'Missing'])
                ListTile(
                  title: UiText(reason),
                  onTap: () => Navigator.pop(c, reason),
                ),
            ],
          ),
        ),
      );
      if (reason == null || !mounted) return;
      final selectedLocation = location;
      await entryForm(
        context,
        'Stock adjustment',
        const [
          Entry('Quantity to remove', numeric: true),
          Entry('Reason / details'),
        ],
        (v) async {
          await store!.adjustStock(
            p['id'] as int,
            positiveQuantity(v[0]),
            selectedLocation,
            '$reason: ${v[1]}',
          );
          await refresh();
        },
      );
      return;
    }
    if (choice == 'edit') {
      await entryForm(
        context,
        'Edit inventory item',
        [
          Entry('Item name', initial: p['name'] as String),
          Entry('SKU / barcode', initial: p['sku'] as String, scan: true),
          Entry(
            'Selling price (SAR)',
            initial: ((p['price'] as int) / 100).toStringAsFixed(2),
            numeric: true,
          ),
          Entry(
            'Purchase cost (SAR)',
            initial: ((p['cost'] as int) / 100).toStringAsFixed(2),
            numeric: true,
          ),
          Entry(
            'Barcode (optional)',
            initial: p['barcode'] as String,
            scan: true,
          ),
          Entry(
            'Reorder level',
            initial: '${p['reorder_level']}',
            numeric: true,
          ),
        ],
        (v) async {
          await store!.updateProduct(
            p['id'] as int,
            v[0],
            v[1],
            amount(v[2]),
            amount(v[3]),
            barcode: v[4],
            reorderLevel: _reorderLevel(v[5]),
          );
          await refresh();
        },
      );
      return;
    }
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
              UiText('${c['phone']}  ${c['area']}'),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const UiText('Edit customer'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await entryForm(
                    context,
                    'Edit customer',
                    [
                      Entry('Customer name', initial: c['name'] as String),
                      Entry('Phone number', initial: c['phone'] as String),
                      Entry('Area / route', initial: c['area'] as String),
                    ],
                    (v) async {
                      await store!.updateCustomer(
                        c['id'] as int,
                        v[0],
                        v[1],
                        v[2],
                      );
                      await refresh();
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              UiText('Outstanding: ${money(c['balance'] as int)}'),
              const SizedBox(height: 20),
              if (related.isEmpty)
                const UiText('No sales for this customer yet.'),
              ...related.map(
                (s) => ListTile(
                  title: UiText(invoiceNo(s['id'] as int)),
                  subtitle: UiText(
                    '${s['location']} • ${dateLabel(s['created'])}',
                  ),
                  trailing: UiText(
                    money(
                      (s['total'] as int) -
                          (s['returned'] as int) -
                          (s['paid'] as int) +
                          (s['refunded'] as int),
                    ),
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
    final payments = await store!.salePayments(sale['id'] as int);
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
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
              UiText(
                invoiceNo(sale['id'] as int),
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              UiText(
                'Sales record • saved on this device',
                textAlign: TextAlign.center,
                style: const TextStyle(color: teal),
              ),
              const SizedBox(height: 24),
              Text(
                sale['customer_name'] as String,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              UiText('${dateLabel(sale['created'])} • ${sale['location']}'),
              const Divider(height: 32),
              ...lines.map(
                (line) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(line['name'] as String),
                  subtitle: UiText(
                    '${line['quantity']} × ${money(line['price'] as int)}'
                    '${(line['returned'] as int) > 0 ? ' • ${line['returned']} returned' : ''}',
                  ),
                  trailing: UiText(
                    money(
                      (line['quantity'] as int) * (line['price'] as int) -
                          (line['discount'] as int),
                    ),
                  ),
                ),
              ),
              const Divider(),
              if ((sale['discount'] as int) > 0) ...[
                totalRow(
                  'Items total',
                  (sale['subtotal'] as int) + (sale['discount'] as int),
                ),
                totalRow('Discount', -(sale['discount'] as int)),
              ],
              totalRow('Subtotal', sale['subtotal'] as int),
              totalRow(
                'Tax (${(sale['tax_bps'] as int) / 100}%)',
                sale['tax'] as int,
              ),
              totalRow('Total', sale['total'] as int, bold: true),
              if ((sale['returned'] as int) > 0)
                totalRow('Returns', -(sale['returned'] as int)),
              totalRow('Paid', sale['paid'] as int),
              for (final payment in payments)
                totalRow(
                  '${payment['method']} payment',
                  payment['amount'] as int,
                ),
              if ((sale['refunded'] as int) > 0)
                totalRow('Refunded', -(sale['refunded'] as int)),
              totalRow(
                'Balance due',
                (sale['total'] as int) -
                    (sale['returned'] as int) -
                    (sale['paid'] as int) +
                    (sale['refunded'] as int),
                bold: true,
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: exportingPdf
                    ? null
                    : () => Navigator.pop(ctx, 'save-pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const UiText('Save PDF'),
              ),
              OutlinedButton.icon(
                onPressed: exportingPdf
                    ? null
                    : () => Navigator.pop(ctx, 'share-pdf'),
                icon: const Icon(Icons.share_outlined),
                label: const UiText('Share PDF'),
              ),
              if ((sale['total'] as int) -
                      (sale['returned'] as int) -
                      (sale['paid'] as int) +
                      (sale['refunded'] as int) >
                  0)
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'collect'),
                  icon: const Icon(Icons.payments_outlined),
                  label: const UiText('Record payment'),
                ),
              if (lines.any(
                (line) => (line['quantity'] as int) > (line['returned'] as int),
              )) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'return'),
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const UiText('Return items'),
                ),
              ],
              const SizedBox(height: 16),
              const UiText(
                'Sales record for testing. Saudi e-invoicing is not configured.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF71818A)),
              ),
            ],
          ),
        ),
      ),
    );
    if ((action == 'save-pdf' || action == 'share-pdf') && mounted) {
      await exportInvoice(sale, lines, share: action == 'share-pdf');
    }
    if (action == 'return' && mounted) {
      final quantities = await showModalBottomSheet<Map<int, int>>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => ReturnSheet(lines: lines),
      );
      if (quantities != null && mounted) {
        final method = await choosePaymentMethod(
          context,
          title: 'Refund method',
        );
        if (method == null || !mounted) return;
        try {
          final refund = await store!.returnSale(
            sale['id'] as int,
            quantities,
            refundMethod: method,
          );
          await refresh();
          toast(
            refund > 0
                ? 'Return saved. Refund ${money(refund)} to the customer.'
                : 'Return saved and stock restored.',
          );
        } catch (e) {
          toast(
            e is FormatException ? e.message : 'Could not save the return.',
          );
        }
      }
    }
    if (action == 'collect' && mounted) {
      final method = await choosePaymentMethod(context);
      if (method == null || !mounted) return;
      final balance =
          (sale['total'] as int) -
          (sale['returned'] as int) -
          (sale['paid'] as int) +
          (sale['refunded'] as int);
      await entryForm(
        context,
        'Record customer payment',
        [
          Entry(
            'Amount received (SAR)',
            initial: (balance / 100).toStringAsFixed(2),
            numeric: true,
          ),
        ],
        (v) async {
          await store!.collect(sale['id'] as int, amount(v[0]), method: method);
          await refresh();
        },
      );
    }
  }

  Future<void> exportInvoice(
    DbRow sale,
    List<DbRow> lines, {
    required bool share,
  }) async {
    if (exportingPdf) return;
    exportingPdf = true;
    final language = Localizations.localeOf(context).languageCode;
    try {
      final bytes = await createInvoicePdf(
        sale: sale,
        lines: lines,
        business: settings['business'] ?? 'My business',
        language: language,
      );
      if (!mounted) return;
      final filename = '${invoiceNo(sale['id'] as int)}.pdf';
      if (share) {
        final box = context.findRenderObject() as RenderBox?;
        await Printing.sharePdf(
          bytes: bytes,
          filename: filename,
          bounds: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
      } else {
        final saved = await FilePicker.platform.saveFile(
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          bytes: bytes,
        );
        if (mounted) {
          toast(saved == null ? 'PDF save cancelled.' : 'PDF saved.');
        }
      }
    } catch (_) {
      if (mounted) toast('Could not create the PDF. Please try again.');
    } finally {
      exportingPdf = false;
    }
  }

  int _reorderLevel(String value) {
    final level = int.tryParse(value.trim());
    if (level == null || level < 0 || level > 1000000) {
      throw const FormatException(
        'Enter a reorder level from 0 to 1,000,000.',
      );
    }
    return level;
  }

  Future<void> exportReorderList(List<DbRow> rows) async {
    if (exportingReorderList) return;
    setState(() => exportingReorderList = true);
    try {
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: tr(context, 'Export replenishment CSV'),
        fileName:
            'rihla-replenishment-$location-${DateTime.now().millisecondsSinceEpoch}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: reorderListCsv(
          rows,
          location: location,
          translate: (value) => tr(context, value),
        ),
      );
      if (mounted) {
        toast(
          saved == null
              ? 'Replenishment export cancelled.'
              : 'Replenishment list exported.',
        );
      }
    } catch (_) {
      if (mounted) {
        toast('Could not export replenishment list. Please try again.');
      }
    } finally {
      if (mounted) setState(() => exportingReorderList = false);
    }
  }
}

Widget totalRow(String label, int value, {bool bold = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 7),
  child: Row(
    children: [
      Expanded(child: UiText(label)),
      UiText(
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
              .fold(
                0,
                (n, s) => n + (s['total'] as int) - (s['returned'] as int),
              ),
        )
        .toList();
    final max = totals.fold(1, (a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UiText(
              money(totals.fold(0, (a, b) => a + b)),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const UiText(
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
                          UiText(
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
  final bool numeric, scan;
  const Entry(
    this.label, {
    this.initial = '',
    this.numeric = false,
    this.scan = false,
  });
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
              : '$e'.contains('products.barcode')
              ? 'This barcode already belongs to another product.'
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
              UiText(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
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
                      labelText: tr(context, widget.fields[i].label),
                      suffixIcon: widget.fields[i].scan
                          ? IconButton(
                              tooltip: tr(context, 'Scan barcode'),
                              icon: const Icon(Icons.qr_code_scanner),
                              onPressed: busy
                                  ? null
                                  : () async {
                                      final code = await scanBarcode(context);
                                      if (code != null && mounted) {
                                        controllers[i].text = code;
                                      }
                                    },
                            )
                          : null,
                    ),
                    textInputAction: i == widget.fields.length - 1
                        ? TextInputAction.done
                        : TextInputAction.next,
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: UiText(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: UiText(busy ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
