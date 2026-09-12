part of 'main.dart';

class BackupScreen extends StatefulWidget {
  final PosStore store;
  const BackupScreen({super.key, required this.store});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool busy = false;
  bool failed = false;
  String? message;

  Future<bool> saveCurrentBackup() async {
    final bytes = await widget.store.exportBackup();
    final now = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: mounted
          ? tr(context, 'Save Rihla backup')
          : 'Save Rihla backup',
      fileName: 'rihla-backup-$now.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    return path != null;
  }

  Future<void> run(Future<String> Function() operation) async {
    setState(() {
      busy = true;
      failed = false;
      message = null;
    });
    try {
      final result = await operation();
      if (mounted) setState(() => message = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          message = e is FormatException
              ? e.message
              : 'Could not complete this operation. Your records have not been replaced.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() => run(
    () async => await saveCurrentBackup()
        ? 'Backup saved. Keep a copy outside this app.'
        : 'Backup cancelled. No file was saved to your selected location.',
  );

  Future<void> restore() => run(() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: tr(context, 'Choose a Rihla backup'),
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
      withData: false,
    );
    if (picked == null) return 'Restore cancelled. Your records are unchanged.';
    final file = picked.files.single.xFile;
    if (await file.length() > maxBackupBytes) {
      throw const FormatException('Choose a Rihla backup smaller than 25 MB.');
    }
    final backup = PosBackup.decode(await file.readAsBytes());
    if (!mounted) return '';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const UiText('Restore this backup?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                backup.business,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              UiText('Saved ${dateLabel(backup.created)}'),
              const SizedBox(height: 16),
              UiText('${backup.count('products')} products'),
              UiText('${backup.count('customers')} customers'),
              UiText('${backup.count('suppliers')} suppliers'),
              UiText('${backup.count('sales')} sales'),
              UiText('${backup.count('purchases')} purchases'),
              UiText('${backup.count('expenses')} expenses'),
              const SizedBox(height: 16),
              const UiText(
                'This replaces all records on this phone, including payments, '
                'returns, stock and settings. Records are not merged. '
                'Save a backup of your current data first if you want to keep it.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const UiText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const UiText('Replace records'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return 'Restore cancelled. Your records are unchanged.';
    }
    await widget.store.restoreBackup(backup);
    return 'Backup restored for ${backup.business}. Your records are ready.';
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const UiText('Backup and restore')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            UiText(
              'Keep a copy of your business',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const UiText(
              'Backups include products, shop and van stock, customers, suppliers, '
              'sales, purchases, payments, returns, expenses and settings.',
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.save_alt_rounded, color: teal, size: 36),
                    const SizedBox(height: 12),
                    const UiText(
                      'Save to Files or a folder you choose. A local backup works without internet.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: busy ? null : export,
                      icon: const Icon(Icons.download_outlined),
                      label: const UiText('Save backup'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: busy ? null : restore,
              icon: const Icon(Icons.restore_rounded),
              label: const UiText('Restore from file'),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: UiText(
                  message!,
                  style: TextStyle(color: failed ? Colors.red : teal),
                ),
              ),
            const SizedBox(height: 16),
            const UiText(
              'Backup files are not encrypted and contain business and customer details. '
              'Keep them in a private location outside the app. '
              'Cloud file providers may need internet. Backups do not sync devices.',
              style: TextStyle(color: Color(0xFF71818A), height: 1.5),
            ),
            const SizedBox(height: 16),
            const UiText(
              'Rihla POS • Version $appVersion',
              style: TextStyle(color: Color(0xFF71818A)),
            ),
          ],
        ),
      ),
    ),
  );
}
