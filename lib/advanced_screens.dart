part of 'main.dart';

class StatementScreen extends StatefulWidget {
  final PosStore store;
  final String title;
  final String party;
  final Future<List<DbRow>> Function() loadEntries;
  const StatementScreen({
    super.key,
    required this.store,
    required this.title,
    required this.party,
    required this.loadEntries,
  });

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  List<DbRow> entries = [];
  bool loading = true, exporting = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final rows = await widget.loadEntries();
    if (mounted) {
      setState(() {
        entries = statementWithBalances(rows);
        loading = false;
      });
    }
  }

  Future<void> export(String type) async {
    setState(() => exporting = true);
    try {
      final language = Localizations.localeOf(context).languageCode;
      final business =
          (await widget.store.settings())['business'] ?? 'My business';
      final bytes = type == 'pdf'
          ? await createStatementPdf(
              title: widget.title,
              party: widget.party,
              business: business,
              entries: entries,
              language: language,
            )
          : statementCsv(
              title: widget.title,
              party: widget.party,
              entries: entries,
              translate: (value) => tr(context, value),
            );
      if (!mounted) return;
      final safe = widget.party.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
      final saved = await FilePicker.platform.saveFile(
        fileName: 'rihla-statement-$safe.$type',
        type: FileType.custom,
        allowedExtensions: [type],
        bytes: bytes,
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: UiText('Statement exported')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: UiText('Could not export statement.')),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: UiText(widget.title)),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Text(
                widget.party,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              UiText(
                'Closing balance: ${money(entries.isEmpty ? 0 : entries.last['balance'] as int)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: exporting ? null : () => export('pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const UiText('Export PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: exporting ? null : () => export('csv'),
                    icon: const Icon(Icons.table_view_outlined),
                    label: const UiText('Export CSV'),
                  ),
                ],
              ),
              const Divider(height: 28),
              if (entries.isEmpty)
                operationEmpty(
                  context,
                  Icons.receipt_long_outlined,
                  'No statement entries',
                  'Transactions for this account will appear here.',
                ),
              for (final entry in entries.reversed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: UiText('${entry['type']} • ${entry['reference']}'),
                  subtitle: UiText(dateLabel(entry['created'])),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      UiText(
                        (entry['debit'] as int) > 0
                            ? '+${money(entry['debit'] as int)}'
                            : '-${money(entry['credit'] as int)}',
                      ),
                      UiText(
                        money(entry['balance'] as int),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF71818A),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
  );
}

class SavedSalesScreen extends StatefulWidget {
  final PosStore store;
  final String kind;
  final Map<String, String> settings;
  const SavedSalesScreen({
    super.key,
    required this.store,
    required this.kind,
    required this.settings,
  });

  @override
  State<SavedSalesScreen> createState() => _SavedSalesScreenState();
}

class _SavedSalesScreenState extends State<SavedSalesScreen> {
  List<DbRow> rows = [];
  bool loading = true;
  String get title => widget.kind == 'quotation' ? 'Quotations' : 'Held sales';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await widget.store.savedDocuments(widget.kind);
    if (mounted) {
      setState(() {
        rows = result;
        loading = false;
      });
    }
  }

  Future<void> open(DbRow row) async {
    if (row['status'] != 'open') return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SaleScreen(
          store: widget.store,
          location: row['location'] as String,
          settings: widget.settings,
          document: row,
        ),
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: UiText(title)),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (rows.isEmpty)
                operationEmpty(
                  context,
                  Icons.bookmarks_outlined,
                  widget.kind == 'quotation'
                      ? 'No quotations yet'
                      : 'No held sales',
                  widget.kind == 'quotation'
                      ? 'Save a quotation from the new sale screen.'
                      : 'Hold an unfinished cart from the new sale screen.',
                ),
              for (final row in rows)
                Card(
                  child: ListTile(
                    onTap: () => open(row),
                    leading: Icon(
                      row['status'] == 'open'
                          ? Icons.edit_note
                          : Icons.check_circle_outline,
                      color: teal,
                    ),
                    title: Text(row['name'] as String),
                    subtitle: UiText(
                      '${row['party_name']} • ${dateLabel(row['created'])}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        UiText(money(row['total'] as int)),
                        UiText(
                          row['status'] as String,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}

class PurchaseOrdersScreen extends StatefulWidget {
  final PosStore store;
  const PurchaseOrdersScreen({super.key, required this.store});
  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  List<DbRow> rows = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await widget.store.savedDocuments('purchase_order');
    if (mounted) {
      setState(() {
        rows = result;
        loading = false;
      });
    }
  }

  Future<void> open(DbRow row) async {
    if (row['status'] != 'open') return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseEditor(
          store: widget.store,
          location: row['location'] as String,
          document: row,
        ),
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const UiText('Purchase orders')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (rows.isEmpty)
                operationEmpty(
                  context,
                  Icons.assignment_outlined,
                  'No purchase orders',
                  'Save an order from the new purchase screen.',
                ),
              for (final row in rows)
                Card(
                  child: ListTile(
                    onTap: () => open(row),
                    title: Text(row['name'] as String),
                    subtitle: UiText('${row['party_name']} • ${row['status']}'),
                    trailing: UiText(money(row['total'] as int)),
                  ),
                ),
            ],
          ),
  );
}

class VansScreen extends StatefulWidget {
  final PosStore store;
  const VansScreen({super.key, required this.store});
  @override
  State<VansScreen> createState() => _VansScreenState();
}

class _VansScreenState extends State<VansScreen> {
  List<DbRow> rows = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final v = await widget.store.vans();
    if (mounted) setState(() => rows = v);
  }

  Future<void> add() => entryForm(
    context,
    'Add van',
    const [Entry('Van name'), Entry('Salesperson')],
    (v) async {
      await widget.store.addVan(v[0], v[1]);
      await load();
    },
  );
  Future<void> edit(DbRow row) => entryForm(
    context,
    'Edit van',
    [
      Entry('Van name', initial: row['name'] as String),
      Entry('Salesperson', initial: row['salesperson'] as String),
    ],
    (v) async {
      await widget.store.updateVan(
        row['id'] as int,
        v[0],
        v[1],
        row['active'] == 1,
      );
      await load();
    },
  );
  Future<void> toggle(DbRow row, bool active) async {
    await widget.store.updateVan(
      row['id'] as int,
      row['name'] as String,
      row['salesperson'] as String,
      active,
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const UiText('Vans and salespeople')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const UiText('Add van'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const UiText(
          'Van profiles identify salespeople. The current release retains one shared van stock quantity.',
          style: TextStyle(color: Color(0xFF71818A)),
        ),
        const SizedBox(height: 16),
        for (final row in rows)
          Card(
            child: ListTile(
              onTap: () => edit(row),
              leading: const Icon(Icons.local_shipping_outlined, color: teal),
              title: Text(row['name'] as String),
              subtitle: Text(
                (row['salesperson'] as String).isEmpty
                    ? 'No salesperson'
                    : row['salesperson'] as String,
              ),
              trailing: Switch(
                value: row['active'] == 1,
                onChanged: row['id'] == 1
                    ? null
                    : (active) => toggle(row, active),
              ),
            ),
          ),
      ],
    ),
  );
}

class ZatcaStatusScreen extends StatelessWidget {
  final Map<String, String> settings;
  const ZatcaStatusScreen({super.key, required this.settings});
  @override
  Widget build(BuildContext context) {
    final vat = settings['seller_vat'] ?? '';
    final ready = RegExp(r'^3\d{13}3$').hasMatch(vat);
    return Scaffold(
      appBar: AppBar(title: const UiText('ZATCA invoice status')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            leading: Icon(
              ready ? Icons.check_circle : Icons.warning_amber,
              color: ready ? teal : Colors.orange,
            ),
            title: UiText(
              ready ? 'Phase 1 QR enabled' : 'Phase 1 QR needs VAT number',
            ),
            subtitle: const UiText(
              'Configure the seller VAT number and address in Business profile.',
            ),
          ),
          const Divider(),
          const UiText(
            'Phase 2 is not active. ZATCA requires an onboarded EGS, production CSID, signed UBL XML, cryptographic stamp, invoice hash chain and reporting or clearance through FATOORA APIs.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 12),
          const UiText(
            'The app remains offline for daily use. Phase 2 cannot be represented as compliant until onboarding credentials and the required online submission service are configured and validated.',
            style: TextStyle(color: Color(0xFF71818A), height: 1.6),
          ),
        ],
      ),
    );
  }
}
