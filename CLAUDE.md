# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RTS-LSC is a cross-platform mobile app (Android/iOS) built with Flutter/Dart. Package name: `com.rts.lsc`, project name: `rts_lsc`.

## Development Setup

- Flutter SDK location: `C:/flutter/flutter/bin` (must be on PATH)
- IDE: VS Code with `dart-code.flutter` and `alexisvt.flutter-snippets` extensions
- GitHub: repo at `T-Rying/RTS-LSC`

## Common Commands

```bash
export PATH="$PATH:/c/flutter/flutter/bin"  # ensure Flutter is on PATH

flutter run                  # run the app (requires connected device/emulator)
flutter build apk            # build Android APK
flutter build ios            # build iOS (requires macOS)
flutter test                 # run all tests
flutter test test/widget_test.dart  # run a single test file
flutter pub get              # fetch dependencies
flutter pub add <package>    # add a dependency
flutter analyze              # run static analysis (uses analysis_options.yaml)
flutter doctor               # check environment setup
```

## Architecture

Standard Flutter project structure:
- `lib/main.dart` — app entry point
- `test/` — widget and unit tests
- `pubspec.yaml` — dependencies and project metadata
- `analysis_options.yaml` — lint rules (uses `flutter_lints`)
- Platform-specific code: `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/`
