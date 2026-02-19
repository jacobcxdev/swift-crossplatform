<!-- Source: https://skip.dev/docs/porting/ -->

# Porting Swift Packages to Android

## Overview

This guide teaches developers how to adapt Swift packages for Android compatibility. The process involves identifying build issues, applying conditional imports, and testing on Android platforms.

## Package Prerequisites

### Good Candidates for Android Porting

Packages with "general-purpose functionality" work best, including:

- Business logic and algorithms
- Generic data structures
- Networking utilities
- Web service and API clients
- Data persistence
- Parsers and formatters

### Poor Candidates

Packages with integral Apple-specific dependencies present challenges:

- Custom UIKit components
- HealthKit, CarPlay, Siri integrations
- Other *Kit library integrations

## Setup and Building

### Initial Testing

Verify the package works locally first:

```bash
swift build
swift test
```

### Installing Skip and Android SDK

```bash
brew install skiptools/skip/skip
skip android sdk install
cd MySwiftPackage/
skip android build
```

A successful build displays "Build complete!" confirming Android compatibility.

## Porting Your Swift Package

### Conditionally Importing Platform-Specific Modules

Use `#if canImport()` directives to exclude unavailable modules. For example, EventKit is iOS-only:

```swift
#if canImport(EventKit)
import EventKit

extension EKEvent: Event {
    var dateRange: Range<Date> { self.startDate..<self.endDate }
    var isConfirmed: Bool { self.status == .confirmed }
}
#endif
```

This technique allows "seamless exclusion of code unsupported by target platforms without restructuring packages."

### SkipFuse Module

The SkipFuse framework provides "cross-platform functionality" including logging via OSLog and Jetpack Compose UI integration for Kotlin @Observables. While optional for utility modules, it's essential for full compiled Swift apps on Android.

### Foundation Sub-Modules

Android separates Foundation functionality that Darwin bundles together:

- **FoundationEssentials**: Date, Calendar, URL, IndexSet
- **FoundationInternationalization**: DateFormatter, NumberFormatter
- **FoundationNetworking**: URLSession, URLCache
- **FoundationXML**: XMLParser

Conditional import solution:

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
```

### Android Module Import

Replace Darwin imports on Android:

```swift
#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#else
#error("Unknown platform")
#endif
```

### Low-Level C Issues

Some C library definitions differ between platforms. The FILE type doesn't exist on Android; use OpaquePointer instead:

```swift
#if os(Android)
typealias Descriptor = OpaquePointer
#else
typealias Descriptor = UnsafeMutablePointer<FILE>
#endif
```

Force-unwrap pointer addresses when calling C functions requiring non-optional pointers.

## Testing

### Running Tests on Android

After setting up an Android device or emulator:

```bash
skip android test
```

This command compiles tests, bundles resources, copies them to the device/emulator, and executes remotely.

The output shows test suite results, similar to local testing but executed on Android.

## Continuous Integration

### GitHub Actions Workflow

The `swift-android-action` automates Android testing. Example `.github/workflows/ci.yml`:

```yaml
name: swift package ci

on:
  push:
    branches: ['*']
  pull_request:
    branches: ['*']

jobs:
  linux-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: "Test Swift Package on Linux"
        run: swift test
      - name: "Test Swift Package on Android"
        uses: skiptools/swift-android-action@v2

  macos-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: "Test Swift Package on macOS"
        run: swift test
      - name: "Test Swift Package on iOS"
        run: xcodebuild test -sdk "iphonesimulator" ...
```

This ensures "packages continue working on all supported platforms."

## Recommended Porting Sequence

The recommended porting sequence involves six steps:

1. Install Skip
2. Attempt Android builds
3. Resolve conditional import issues
4. Test on Android devices/emulators
5. Identify test failures
6. Address platform differences

The guide notes thousands of Swift packages now support Android through this methodology.
