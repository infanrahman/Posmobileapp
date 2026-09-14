# Rihla POS

An offline mobile app for Saudi retail shops and van salespeople. One Flutter codebase targets Android and iOS. All operational data stays in SQLite on the current device; no server, login, cloud fonts or online API is used by the app.

## Implemented

- SAR prices and integer-halalah calculations; configurable tax-exclusive sales tax (starts at zero until configured).
- Products with unique SKUs, selling prices, purchase costs, editing, opening quantities, stock receipts and configurable reorder levels.
- Camera barcode scanning in sales, purchases and inventory, with optional unique product barcodes separate from existing SKUs. Manual code entry remains available if camera access is denied. Recognition is bundled on Android for offline use from first launch; iOS uses native recognition.
- Separate shop and van quantities, with transfers in either direction. Damaged, expired and missing stock can be reduced with a required reason and adjustment history.
- Shop/van low-stock filters use each product's reorder level and export an offline replenishment CSV with suggested quantities and estimated cost.
- Cash/fully paid, partial-payment and credit sales. Credit requires a named customer.
- Cash, card and bank-transfer payment methods for sales, collections, purchases, supplier payments, expenses and refunds. Sales can split one payment between cash and card.
- Transactional checkout: invoice, immutable line prices, stock movements and initial payment are committed together.
- Partial and complete sales returns, automatic stock restoration and customer refund calculation.
- Audited sale cancellation with a required reason, full stock restoration and recorded refund method.
- Customer details, area/route notes, balances, sales history and payment collection.
- Customer and supplier statements with running balances and offline PDF/CSV export.
- Edit customer and supplier contact details while retaining names saved on earlier invoices.
- Sales ledger, on-device sales records, daily totals and seven-day chart.
- Suppliers with contact and VAT details, payable balances and supplier payment recording.
- Cash, partial and credit purchases that update stock and save the latest product cost.
- Partial/full purchase returns remove stock from the original location, reduce supplier debt and record refunds received. Confirm a cash refund only after receiving it from the supplier. Returns retain original costs and do not recalculate the current product cost.
- Fixed SAR or percentage invoice discounts plus item-level discounts before sales tax. Profit reports, PDFs and partial sales returns use the saved discounted amounts with integer rounding.
- Held carts can be resumed; quotations preserve quoted prices and convert to sales; purchase orders preserve costs and convert to purchases.
- Multiple van and salesperson profiles can be selected on van sales. The current on-device inventory continues to use one shared van stock pool.
- Shop and van expenses, plus reports for sales, tax, gross profit, operating profit, receivables, payables and stock value. Reports can be filtered by invoice date and shop/van, then exported as an offline CSV file.
- Separate shop and van cash sessions with opening cash, automatic cash-only flows, expected and actual closing totals, variance history and CSV export.
- Business-name and tax settings; data persists across app restarts.
- Automatic schema migration preserves existing version 1 app data.
- Manual backup and restore for every business table, with file preview, checksum validation and transactional rollback for invalid records.
- English and Arabic interface, right-to-left layouts and a saved language preference. Arabic fonts are bundled for offline use.
- Save and share invoice PDFs in English or Arabic, including recorded payments, returns, refunds and remaining balances. Print an 80 mm receipt through the phone's available print service.
- Saudi Phase 1 TLV QR codes are generated when a valid seller VAT number is configured. The status screen explains the credentials and online service still required for Phase 2.

The screenshots in `docs/` show isolated sample data. A fresh installation starts empty.

## Run

To build on GitHub's macOS runners without a local Mac, see [GitHub Actions and iPhone signing](docs/ios-github-actions.md). Automatic unsigned builds and a manual signed-IPA workflow are included in `.github/workflows/`.

Requires Flutter 3.44.4 / Dart 3.12.2 or a compatible newer SDK.

```sh
flutter pub get
flutter run
```

Connect an Android device with USB debugging or start an Android emulator. For iOS, run the same project on a Mac with Xcode and an iOS simulator/device. Building and signing iOS apps requires the Apple toolchain and appropriate signing setup: https://docs.flutter.dev/deployment/ios

```sh
flutter analyze
flutter test
flutter build apk --debug
```

On Windows desktop app environments, Java may fail with `Unable to establish loopback connection` when its temporary socket directory is virtualized. For this project, use a socket directory inside the workspace:

```powershell
New-Item -ItemType Directory -Force -Path 'D:\POSMOBILE APPLICATION\build\java-sockets' | Out-Null
$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir="D:\POSMOBILE APPLICATION\build\java-sockets"'
flutter build apk --debug
```

This changes the environment of the current terminal only. The socket-directory workaround is described by OpenJDK: https://mail.openjdk.org/pipermail/nio-dev/2023-March/013297.html

Release signing and store distribution are not configured. The generated Android release configuration uses the Flutter template's debug signing key and must be replaced before release.

## Try the workflow

1. Open **More → Business profile** and enter your business name and intended tax rate.
2. Open **Stock → Add item**. Enter an item, unique SKU, SAR price and opening quantity.
3. Tap an item to edit its prices, receive stock or transfer shop stock to the van.
4. Open **More → Suppliers** to add a supplier, then **More → Purchases** to buy stock using cash, partial payment or credit.
5. Select **Van** to make a sale from the van's stock.
6. Add a customer before creating partial or credit sales.
7. Open **Sales → New sale**, choose the customer, add quantities and complete the sale.
8. Open a sale to inspect its saved record, return items or collect an outstanding payment.
9. Record operating costs under **More → Expenses** and view totals under **More → Reports**.
10. Open a sale and choose **Save PDF** or **Share PDF**.
11. Choose **More → Language → العربية** to use the Arabic interface.
12. Choose **More → Backup and restore → Save backup** to save a JSON file outside the app. Restore previews the backup and requires **Replace records**; it replaces all device records rather than merging them. Save the current records first if you need to keep them. Files are limited to 25 MB, are not encrypted and should be kept privately. Local folders work offline; cloud file providers may need internet.
13. Open a customer and choose **Edit customer**; tap a supplier to edit its details. Existing invoice names remain as originally saved.
14. Open a purchase and choose **Return purchase items**. Choose quantities, check the return value and refund, then confirm after any displayed supplier refund is received.
15. Enter **Discount (SAR)** in a new sale to reduce its tax-exclusive subtotal. Discounts must not exceed the items total.
16. Add or edit a stock item and fill **Barcode (optional)** by typing or using its scan button. Existing **SKU / barcode** values can also be matched. A barcode belongs to one product; ambiguous barcode/SKU matches are rejected.
17. Tap the scan icon in a new sale to add one unit. Tap it in a new purchase to open the item's quantity and cost form. Inventory scanning opens the matching item's actions. Unknown codes never create or modify products automatically. Show one barcode at a time; reopen the scanner to add another unit.
18. Tap an item under **Stock**, then choose **Stock adjustment**. Select damaged, expired or missing, enter the quantity and details, and review it later under **Adjustment history**.
19. Open **More → Reports** to select all dates or a date range and choose shop, van or both. **Export CSV** saves the displayed report through the device file picker.
20. Open **More → Daily cashbook**, choose shop or van and enter the opening drawer cash. Recorded sales, collections, refunds, expenses and supplier payments update the expected cash. Count and close the session to save its variance; closing history can be exported as CSV.
21. Choose cash, card or bank transfer when recording payments, expenses or refunds. In a new sale, choose **Split** and enter the cash and card portions. Reports show received totals by payment method, while the daily cashbook includes only cash.
22. Set a **Reorder level** when adding or editing an item. Under **Stock**, choose **Low stock only** for the selected shop/van location and export the replenishment CSV when ordering stock.
23. Close and reopen the app. The saved records, language and quantities remain available without internet. **More** shows the installed app version; this release is **1.0.0 (build 10)**.

## Architecture

- `lib/store.dart`: schema, validation, money parsing and transactional database operations.
- `lib/main.dart`: app theme, dashboard, inventory, customer ledger, settings and forms.
- `lib/sale_screen.dart`: checkout and payment selection.
- `lib/operations_screens.dart`: suppliers, purchases, expenses, daily cashbook, reports and sales return screens.
- `lib/backup.dart` and `lib/backup_screen.dart`: complete database snapshots, validation, atomic restore and native file selection.
- `lib/l10n.dart`: Arabic interface translations and dynamic labels; user-entered product and business names remain unchanged.
- `lib/invoice_pdf.dart`: offline invoice PDFs using bundled Amiri fonts.
- `lib/advanced_screens.dart` and `lib/statement_export.dart`: saved documents, account statements, van profiles and ZATCA readiness.
- `lib/barcode.dart` and `lib/barcode_screen.dart`: code matching, single-result camera capture, lifecycle management and manual entry.
- `test/store_test.dart`: calculations, rollback, purchases, returns, reports, migration, concurrency, credit collection, persistence and price snapshots.
- `test/widget_test.dart`: phone-sized navigation, complete checkout and reports with a real SQLite test database.
- `test/preview_test.dart`: optional render with isolated demo data. Enabled by `RIHLA_PREVIEW_FONT`, pointing to a local font file; the font is never copied into the app.

SQLite schema version 8 adds saved documents, cancellation audit records, van profiles and invoice identity fields. Upgrades from versions 1 through 7 preserve existing records. Backups from schemas 2 through 7 can still be restored; new backups include every schema 8 table. Queries bind user input. Dynamic stock columns are restricted to the internal `shop`/`van` allowlist. Prices, discounts and tax totals use integer arithmetic; tax is rounded to the nearest halalah.

Barcodes remain text, preserving leading zeroes. UPC-A and its zero-prefixed EAN-13 representation share a key for matching across devices. Barcode values are case-sensitive; SKU matching is case-insensitive. Camera frames are not saved or uploaded by this app. The scanner requests camera access only when opened. See the [scanner package documentation](https://pub.dev/packages/mobile_scanner) for native format support.

## Scope before live business use

This remains an offline POS release rather than a complete cloud ERP or Saudi Phase 2 e-invoicing service.

- Phase 1 QR output is available. Phase 2 requires ZATCA onboarding credentials, cryptographic invoice signing, UBL XML and online reporting or clearance; those production services are not active.
- No multi-device sync or user accounts. Uninstalling the app can remove its data; keep manual backups outside the app. Restoring a backup replaces current records.
- Shop and van are two stock pools on **one device**, not shared real-time stock across different phones. Multiple van identities share the van stock pool; route scheduling and stock per vehicle are not included.
- Thermal receipts use the iOS/Android print service and require a compatible printer or printer driver. Card and bank transfer choices record how money was received; they do not process the transaction.
- The database is not encrypted; production device access controls and recovery policy remain to be designed.
- Native Android/iOS device validation, airplane-mode testing, accessibility checks and release signing are still required.

SQLite platform reference: https://docs.flutter.dev/cookbook/persistence/sqlite


## Validation on 14 September 2026

- `flutter analyze`: no issues.
- Automated tests cover database operations and migration, checkout navigation, backup round trips and rollback, native file flow with a test picker, Arabic persistence and PDF generation. The optional dashboard preview test requires a local preview font.
- English and Arabic invoice PDFs were rendered and visually inspected using sample records.
- Trading regression tests cover saved contact snapshots, discounts and split returns, supplier refunds, stock rollback, schema 2 migration and legacy backup restore.
- Scanner tests use a simulated native camera to check duplicate events, multiple visible codes, background/resume behavior, unknown codes, stock limits, permission denial and manual entry. Barcode migration and legacy backup compatibility are tested. Real camera focus, physical label recognition and permission prompts still require iPhone/Android device checks, including airplane mode.
- GitHub Actions builds the Android APK and unsigned iOS IPA on Linux and macOS runners after each push.
- Android and iOS were not run on physical devices. A signed iOS IPA still requires an active paid Apple Developer Program team and repository signing secrets.
