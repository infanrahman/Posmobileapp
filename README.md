# Rihla POS

An initial offline mobile app for Saudi retail shops and van salespeople. One Flutter codebase targets Android and iOS. All operational data stays in SQLite on the current device; no server, login, cloud fonts or online API is used by the app.

## Implemented

- SAR prices and integer-halalah calculations; configurable tax-exclusive sales tax (starts at zero until configured).
- Products with unique SKUs, opening quantities, stock receipts and low-stock indicators.
- Separate shop and van quantities, with transfers in either direction.
- Cash/fully paid, partial-payment and credit sales. Credit requires a named customer.
- Transactional checkout: invoice, immutable line prices, stock movements and initial payment are committed together.
- Customer details, area/route notes, balances, sales history and payment collection.
- Sales ledger, on-device sales records, daily totals and seven-day chart.
- Business-name and tax settings; data persists across app restarts.

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
3. Tap an item to receive more stock or transfer shop stock to the van.
4. Select **Van** to make a sale from the van's stock.
5. Add a customer before creating partial or credit sales.
6. Open **Sales → New sale**, choose the customer, add quantities and complete the sale.
7. Open a sale to inspect its saved record or collect an outstanding payment.
8. Close and reopen the app. The saved records and remaining quantities should remain available without internet.

## Architecture

- `lib/store.dart`: schema, validation, money parsing and transactional database operations.
- `lib/main.dart`: app theme, dashboard, inventory, customer ledger, settings and forms.
- `lib/sale_screen.dart`: checkout and payment selection.
- `test/store_test.dart`: calculations, rollback, location separation, concurrent overselling, credit collection, persistence and price snapshots.
- `test/widget_test.dart`: phone-sized navigation and complete checkout with a real SQLite test database.
- `test/preview_test.dart`: optional render with isolated demo data. Enabled by `RIHLA_PREVIEW_FONT`, pointing to a local font file; the font is never copied into the app.

SQLite schema version 1 includes products, customers, sales, sale lines, stock movements, payments and settings. Queries bind user input. Dynamic stock columns are restricted to the internal `shop`/`van` allowlist. Prices and tax totals use integer arithmetic; tax is rounded once per invoice to the nearest halalah.

## Scope before live business use

This is an initial working version, not a complete Vyapar replacement or a Saudi e-invoicing solution.

- Saudi e-invoicing/ZATCA integration, compliant invoice output and applicable validation are not implemented. Sales records are explicitly labelled for testing.
- Arabic translation and right-to-left layouts are not implemented.
- No backup/restore, multi-device sync, user accounts or device recovery. Uninstalling the app can remove its data. Use test data at this stage.
- Shop and van are two locations on **one device**, not shared real-time stock across different phones. No multiple-van identifiers or route scheduling yet.
- Returns, cancellations, purchase orders, suppliers, expenses, discounts and product/customer editing are not implemented.
- No barcode camera, PDF export, receipt printer or payment terminal integration. Recording a payment does not process a card transaction.
- The database is not encrypted; production device access controls and recovery policy remain to be designed.
- Native Android/iOS device validation, airplane-mode testing, accessibility checks and release signing are still required.

SQLite platform reference: https://docs.flutter.dev/cookbook/persistence/sqlite


## Validation on 10 September 2026

- `flutter analyze`: no issues.
- Automated tests: 11 passed with the optional preview enabled (9 database tests, 1 checkout UI test, 1 preview render).
- Debug Android APK built successfully: `build/app/outputs/flutter-apk/app-debug.apk`.
- Android and iOS were not run on physical devices. iOS compilation was not attempted on this Windows machine.
