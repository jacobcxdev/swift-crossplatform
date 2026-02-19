<!-- Source: https://skip.dev/docs/testing/ -->

# Skip Testing Documentation

## Overview

Skip automatically transpiles XCTest unit tests into JUnit tests for Android, enabling cross-platform testing of transpiled Swift code. Tests involving unbridged types should be excluded from Android testing using conditional compilation.

## Unit Testing

### Key Principle

"Skip always transpiles your XCTest unit tests into JUnit tests for Android. This means that you can only perform Android tests on compiled Swift that has been bridged to Kotlin/Java."

### Excluding Unbridged Code

Developers should wrap Android-incompatible tests:

```swift
#if !os(Android)
func testSomeUnbridgedSwift() { ... }
#endif
```

**Note:** Skip Lite projects don't require this limitation since all code is transpiled.

### Robolectric Testing

The SkipUnit module enables testing in a simulated Android environment on your Mac, offering faster feedback than emulators.

**Important caveat:** `#if os(Android)` checks evaluate to false in Robolectric. Instead, use `#if os(Android) || ROBOLECTRIC` to properly execute Android code paths during testing.

### Android Emulator/Device Testing

Set the `ANDROID_SERIAL` environment variable in Xcode scheme settings to direct tests toward specific devices. Common identifiers include "emulator-5554" for default emulators; use `adb devices` to list connected hardware.

While slower than Robolectric, device and emulator testing provides more realistic behavior validation. The SkipFuse samples repository demonstrates CI/CD integration for automated emulator testing.

## Non-Skip Packages

Native Swift packages supporting both iOS and Android (without `skip.yml`) follow testing guidance in the Porting Guide.

## Performance Testing

Always conduct performance evaluations using Release builds on actual devices, as Debug and Release performance on Android varies significantly.
