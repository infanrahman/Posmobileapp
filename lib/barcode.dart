// Keep codes as text: leading zeroes are significant. UPC-A may be reported
// as a zero-prefixed EAN-13 by a camera, so both representations share a key.
String normalizeBarcode(String value) {
  final code = value.trim();
  if (code.length > 128 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(code)) {
    throw const FormatException(
      'Enter a barcode with up to 128 characters on one line.',
    );
  }
  return RegExp(r'^0\d{12}$').hasMatch(code) ? code.substring(1) : code;
}

Map<String, Object?> productForBarcode(
  Iterable<Map<String, Object?>> products,
  String raw,
) {
  final code = normalizeBarcode(raw);
  if (code.isEmpty) throw const FormatException('Enter or scan a barcode.');
  final matches = products.where((product) {
    final barcode = normalizeBarcode((product['barcode'] as String?) ?? '');
    final storedSku = (product['sku'] as String).trim();
    final sku = RegExp(r'^0\d{12}$').hasMatch(storedSku)
        ? storedSku.substring(1)
        : storedSku;
    return (barcode.isNotEmpty && barcode == code) ||
        sku.toUpperCase() == code.toUpperCase();
  }).toList();
  if (matches.isEmpty) {
    throw const FormatException(
      'No product matches this code. Add its barcode in Stock first.',
    );
  }
  if (matches.length > 1) {
    throw const FormatException(
      'This code matches multiple products. Check their barcodes and SKUs in Stock.',
    );
  }
  return matches.single;
}
