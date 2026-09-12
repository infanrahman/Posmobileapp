# Rihla POS

An offline mobile app for Saudi retail shops and van salespeople. One Flutter codebase targets Android and iOS. All operational data stays in SQLite on the current device; no server, login, cloud fonts or online API is used by the app.

## Implemented

- SAR prices and integer-halalah calculations; configurable tax-exclusive sales tax (starts at zero until configured).
- Products with unique SKUs, selling prices, purchase costs, editing, opening quantities, stock receipts and low-stock indicators.
- Separate shop and van quantities, with transfers in either direction.
- Cash/fully paid, partial-payment and credit sales. Credit requires a named customer.
- Transactional checkout: invoice, immutable line prices, stock movements and initial payment are committed together.
- Partial and complete sales returns, automatic stock restoration and customer refund calculation.
- Customer details, area/route notes, balances, sales history and payment collection.
- Sales ledger, on-device sales records, daily totals and seven-day chart.
- Suppliers with contact and VAT details, payable balances and supplier payment recording.
- Cash, partial and credit purchases that update stock and save the latest product cost.
- Shop and van expenses, plus reports for sales, tax, gross profit, operating profit, receivables, payables and stock value.
- Business-name and tax settings; data persists across app restarts.
- Automatic schema migration preserves existing version 1 app data.
- Manual backup and restore for every business table, with file preview, checksum validation and transactional rollback for invalid records.
- English and Arabic interface, right-to-left layouts and a saved language preference. Arabic fonts are bundled for offline use.
- Save and share invoice PDFs in English or Arabic, including recorded payments, returns, refunds and remaining balances.

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
13. Close and reopen the app. The saved records, language and quantities remain available without internet. **More** shows the installed app version; this release is **0.3.0 (build 3)**.

## Architecture

- `lib/store.dart`: schema, validation, money parsing and transactional database operations.
- `lib/main.dart`: app theme, dashboard, inventory, customer ledger, settings and forms.
- `lib/sale_screen.dart`: checkout and payment selection.
- `lib/operations_screens.dart`: suppliers, purchases, expenses, reports and sales return screens.
- `lib/backup.dart` and `lib/backup_screen.dart`: complete database snapshots, validation, atomic restore and native file selection.
- `lib/l10n.dart`: Arabic interface translations and dynamic labels; user-entered product and business names remain unchanged.
- `lib/invoice_pdf.dart`: offline invoice PDFs using bundled Amiri fonts.
- `test/store_test.dart`: calculations, rollback, purchases, returns, reports, migration, concurrency, credit collection, persistence and price snapshots.
- `test/widget_test.dart`: phone-sized navigation, complete checkout and reports with a real SQLite test database.
- `test/preview_test.dart`: optional render with isolated demo data. Enabled by `RIHLA_PREVIEW_FONT`, pointing to a local font file; the font is never copied into the app.

SQLite schema version 2 includes products, customers, suppliers, sales, returns, purchases, expenses, stock movements, payments and settings. Queries bind user input. Dynamic stock columns are restricted to the internal `shop`/`van` allowlist. Prices and tax totals use integer arithmetic; tax is rounded to the nearest halalah.

## Scope before live business use

This is an initial working version, not a complete Vyapar replacement or a Saudi e-invoicing solution.

- Saudi e-invoicing/ZATCA integration, compliant invoice output and applicable validation are not implemented. Sales records are explicitly labelled for testing.
- No multi-device sync or user accounts. Uninstalling the app can remove its data; keep manual backups outside the app. Restoring a backup replaces current records.
- Shop and van are two locations on **one device**, not shared real-time stock across different phones. No multiple-van identifiers or route scheduling yet.
- Purchase returns, sale cancellation, purchase orders, discounts and customer/supplier editing are not implemented.
- No barcode camera, thermal receipt printer or payment terminal integration. Recording a payment does not process a card transaction.
- The database is not encrypted; production device access controls and recovery policy remain to be designed.
- Native Android/iOS device validation, airplane-mode testing, accessibility checks and release signing are still required.

SQLite platform reference: https://docs.flutter.dev/cookbook/persistence/sqlite


## Validation on 12 September 2026

- `flutter analyze`: no issues.
- Automated tests cover database operations and migration, checkout navigation, backup round trips and rollback, native file flow with a test picker, Arabic persistence and PDF generation. The optional dashboard preview test requires a local preview font.
- English and Arabic invoice PDFs were rendered and visually inspected using sample records.
- GitHub Actions builds the Android APK and unsigned iOS IPA on Linux and macOS runners after each push.
- Android and iOS were not run on physical devices. A signed iOS IPA still requires an active paid Apple Developer Program team and repository signing secrets.
