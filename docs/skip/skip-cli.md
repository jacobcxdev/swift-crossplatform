<!-- Source: https://skip.dev/docs/skip-cli/ -->
# Skip CLI Reference

## Overview

The Skip command-line interface is a terminal tool available on macOS, Linux, and Windows that enables developers to create new Skip projects, run tests, validate projects, and export built artifacts for publication.

## Installation

```
brew install skiptools/skip/skip
```

This includes the skip tool binary, gradle, and Android SDK dependencies. The Homebrew CLI installation is separate from the Skip Xcode plugin.

Note: Linux and Windows support is preliminary. macOS is required for full app project creation.

## Commands

### skip upgrade
Upgrades Skip to the latest version via Homebrew.

### skip checkup
Comprehensive system validation - runs all checks from `skip doctor` plus creates and builds a sample Skip app.

```
skip checkup
skip checkup --native
```

Key options: `--configuration`, `--double-check`, `--native`, `--fail-fast`, `--project-name`

### skip create
Creates new Skip projects through interactive prompts.

Key options: `--dir`, `--chain`, `--zero`, `--git-repo`, `--free`, `--configuration`, `--arch`, `--android-api-level`

### skip init
Initializes Skip app or library projects with explicit type.

```
skip init --native-app --appid=some.app.id app-project AppName
skip init --transpiled-app --appid=some.app.id app-project AppName
skip init --native-model lib-project ModuleName
```

Project types: `--native-app`, `--transpiled-app`, `--native-model`, `--transpiled-model`

Build options: `--build`, `--test`, `--verify`, `--apk`, `--ipa`, `--open-xcode`, `--open-gradle`

### skip doctor
Diagnoses development environment. Key options: `--native`, `--fail-fast`

### skip verify
Validates Skip project structure. Key options: `--project`, `--free`, `--fastlane`, `--fix`

### skip export
Builds and exports Skip modules as .aar, .apk, .adb files.

```
skip export --debug
skip export --module ModuleName
```

Key options: `--dir`, `--module`, `--release`/`--debug`, `--export-project`, `--ios`/`--android`

### skip test
Runs parity tests and generates reports.

Key options: `--filter`, `--xunit`, `--junit`, `--summary-file`

### skip icon
Creates and manages app icons for Darwin and Android.

```
skip icon app_icon.png
skip icon --open-preview --random-icon --random-background
skip icon --background #5C6BC0-#3B3F54 symbol.svg
```

Key options: `--dir`, `--open-preview`, `--android`/`--darwin`, `--foreground`/`--background`, `--inset`, `--shadow`

### skip devices
Lists all connected Android emulators, devices, iOS simulators, and devices.

### skip android
Parent command for native Android operations:

- `skip android build` - Build native project
- `skip android run` - Run on device/emulator
- `skip android test` - Test on device/emulator
- `skip android sdk` - Manage Swift Android SDK
- `skip android emulator` - Manage Android emulators
- `skip android toolchain` - Manage Swift Android Host Toolchain

### skip android emulator create
```
skip android emulator create
skip android emulator create --name 'pixel_7_api_36' --device-profile pixel_7 --android-api-level 36
```

### skip android emulator launch
```
skip android emulator launch
skip android emulator launch --name emulator-34-medium_phone --headless
```

### skip android sdk install
```
skip android sdk install
skip android sdk install --version nightly-6.3
```
