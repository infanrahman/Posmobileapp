# Build Rihla on GitHub Actions

GitHub's macOS runners can compile this Flutter app without a local Mac. The workflows in this repository provide automatic compile checks and a manual signed iOS build. Open the Actions tab to inspect the latest run.

## Automatic test builds

Push the project to the GitHub repository. **Actions → Mobile builds** runs on pushes, pull requests and manual dispatches:

1. Formatting, Flutter analysis, database/UI tests and signing-helper tests.
2. An Android debug APK, saved as `rihla-android-test-…`.
3. An unsigned iOS device compilation, saved as `rihla-ios-UNSIGNED-…`.

The unsigned artifact proves the app compiles. It is **not installable on your iPhone**. It is a ZIP of an unsigned `.app`, not a signed `.ipa`.

The workflows pin Flutter 3.44.4 and select Xcode 26.3 on `macos-15`. GitHub runner images change over time; check the [runner software list](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md) if the selected Xcode is later removed. macOS jobs use your GitHub Actions allowance according to the repository/account plan.

## Signed iPhone build

Use **Actions → Signed iOS IPA → Run workflow** after configuring Apple signing. This workflow only exports a signed IPA; it does not publish or upload the app to TestFlight.

You need an Apple Developer Program team, an explicit App ID, an Apple Distribution certificate with its private key exported as a password-protected `.p12`, and the matching provisioning profile.

In **GitHub repository → Settings → Secrets and variables → Actions**, add:

| Kind | Name | Value |
| --- | --- | --- |
| Variable | `IOS_BUNDLE_ID` | Your registered explicit App ID, e.g. `com.yourcompany.rihla` |
| Secret | `IOS_CERTIFICATE_BASE64` | Base64 of the distribution `.p12` file, including its private key |
| Secret | `IOS_CERTIFICATE_PASSWORD` | Password used to protect that `.p12` file |
| Secret | `IOS_PROFILE_BASE64` | Base64 of the matching `.mobileprovision` file |

Add these values directly to GitHub Secrets; do not put certificate contents or passwords in chat, source files or commits. The helper reads the team ID and profile UUID from the profile and validates its expiry, App ID and distribution type. The workflow uses a temporary keychain, cleans up signing material and saves only the IPA artifact.

The current source bundle ID is `com.rihla.rihlaPos`. The signed workflow overrides it with `IOS_BUNDLE_ID`; the Apple profile must match the configured value exactly.

Choose one distribution method:

- **`app-store-connect`**: Use an App Store Connect provisioning profile. The output can be uploaded to the matching App Store Connect app and distributed through TestFlight after Apple's processing. TestFlight upload automation can be added once the repository, app and App Store Connect access are available.
- **`release-testing`**: Use an Ad Hoc profile that includes your iPhone's UDID. Only registered devices can use this IPA. Installing it requires a suitable device-management/installation tool or an appropriately configured over-the-air installation service; opening the downloaded IPA in Safari alone will not install it.

The certificate must belong to the same team and be included in the selected profile. If Apple changes the certificate, App ID or registered devices, replace the GitHub secrets with the regenerated files. Build numbers use GitHub run number and attempt so reruns produce different versions.

## Validation and current limits

Local validation covers workflow syntax and the profile-validation helper. Native iOS compilation and code signing can only be verified after pushing and running on a macOS runner with the required configuration. No Apple credentials have been provided.

These are test builds of the initial app. Backup, Arabic, multi-device sync and Saudi e-invoicing are still pending; use sample business data.

References: [Flutter iOS release guide](https://docs.flutter.dev/deployment/ios), [GitHub signing certificates on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).
