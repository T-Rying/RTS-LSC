# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RTS-LSC is a mobile companion app for **LS Central** (built on Business Central), targeting Android and iOS. Built with Flutter/Dart. Package: `com.rts.lsc`, project name: `rts_lsc`.

The app has three modules on the home page:
- **POS** — authenticates with username/password
- **Mobile Inventory** — authenticates via API connection (OAuth client credentials for SaaS, or server connection for on-premise)
- **Hospitality** — same API connection as Mobile Inventory

## Architecture

```
lib/
  main.dart                          # App entry, MyApp widget, HomePage with 3 module buttons
  models/environment_config.dart     # EnvironmentConfig model (On-Premise vs SaaS), JSON serialization
  services/environment_service.dart  # Persistence layer using SharedPreferences (single connection)
  pages/
    settings_page.dart               # Settings UI with two sections: API Connection + POS Login
    qr_scanner_page.dart             # QR code scanner (mobile_scanner) to auto-fill settings
```

### Connection model

Only one connection exists at a time. `EnvironmentConfig` has a `ConnectionType` enum (`onPremise` / `saas`):
- **On-Premise**: serverUrl, port (default 7048), instance, company
- **SaaS**: tenant, clientId, clientSecret, company
- **POS credentials** (shared): posUsername, posPassword

Settings are persisted via `shared_preferences` as JSON in a single key.

### QR Code format

The QR scanner expects a JSON string matching the `EnvironmentConfig.fromJson` format. See README.md for full field reference.

## Development Setup

- Flutter SDK: `C:/flutter/flutter/bin` (must be on PATH)
- IDE: VS Code with `dart-code.flutter` extension
- GitHub: `T-Rying/RTS-LSC` on master branch
- Android emulator: `Medium_Phone_API_36.1`

## Common Commands

```bash
export PATH="$PATH:/c/flutter/flutter/bin"  # ensure Flutter is on PATH

flutter run                  # run on connected device/emulator
flutter test                 # run all tests
flutter test test/widget_test.dart  # run a single test
flutter pub get              # fetch dependencies
flutter pub add <package>    # add a dependency
flutter analyze              # static analysis
flutter emulators --launch Medium_Phone_API_36.1  # start Android emulator
```

## Key Dependencies

- `shared_preferences` — persisting connection settings
- `mobile_scanner` — QR code scanning for setup
- `cupertino_icons` — iOS-style icons

## SoftPay Developer information

- https://developer.softpay.io/softpay/?p=introduction#introduction

## LS Central Source Code
Used for finding how to receive the payment request from LS Central. LS Central uses ###LSAPPSHELL to indicate if a hardware station uses the app. 