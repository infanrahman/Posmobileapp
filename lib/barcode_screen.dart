import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'barcode.dart';
import 'l10n.dart';

Future<String?> scanBarcode(BuildContext context) => Navigator.push<String>(
  context,
  MaterialPageRoute(builder: (_) => const BarcodeScreen()),
);

class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key});
  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  final input = TextEditingController();
  bool finished = false, manual = false;
  int cameraAttempt = 0;
  String? message;

  void accept(String raw) {
    if (finished || !mounted) return;
    try {
      final code = normalizeBarcode(raw);
      if (code.isEmpty) throw const FormatException('Enter or scan a barcode.');
      finished = true;
      Navigator.pop(context, code);
    } on FormatException catch (e) {
      setState(() => message = e.message);
    }
  }

  void detected(BarcodeCapture capture) {
    if (finished || manual || !mounted) return;
    final codes = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet();
    if (codes.length == 1) {
      accept(codes.single);
    } else if (codes.length > 1 && message != 'Show one barcode at a time.') {
      setState(() => message = 'Show one barcode at a time.');
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const UiText('Scan barcode')),
    body: SafeArea(
      child: Column(
        children: [
          if (!manual)
            Expanded(
              // The widget owns its controller: it pauses in the background and
              // releases the camera when this route closes or manual entry opens.
              child: MobileScanner(
                key: ValueKey(cameraAttempt),
                onDetect: detected,
                tapToFocus: true,
                errorBuilder: (_, error) => Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.no_photography_outlined, size: 48),
                        const SizedBox(height: 16),
                        const UiText(
                          'Camera unavailable. Allow camera access in your phone settings, or enter the code manually.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => setState(() => cameraAttempt++),
                          child: const UiText('Try again'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Flexible(
            flex: manual ? 1 : 0,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!manual)
                    const UiText(
                      'Point the camera at one product barcode. Scanning works offline.',
                      textAlign: TextAlign.center,
                    ),
                  if (manual) ...[
                    TextField(
                      controller: input,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: tr(context, 'Barcode / SKU'),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: accept,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => accept(input.text),
                      child: const UiText('Use code'),
                    ),
                  ],
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: UiText(
                        message!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  TextButton.icon(
                    icon: Icon(
                      manual ? Icons.qr_code_scanner : Icons.keyboard_outlined,
                    ),
                    label: UiText(
                      manual ? 'Use camera' : 'Enter code manually',
                    ),
                    onPressed: () => setState(() {
                      manual = !manual;
                      message = null;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
