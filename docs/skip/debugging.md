<!-- Source: https://skip.dev/docs/debugging/ -->
# Debugging

## Overview
Skip generates fully native applications for iOS and Android, enabling developers to leverage each platform's native debugging tools for troubleshooting issues specific to their respective ecosystems.

## Using the Debugger

For bugs in shared or iOS-specific Swift code, Xcode's debugging tools work as they would for standard iOS apps. Fixes to shared Swift logic automatically resolve the same bugs in Android builds. Android-specific problems can be debugged directly in Android Studio using its native debugging capabilities.

## Compiled Swift

When native Swift code crashes on Android, the error appears similar to Kotlin or Java exceptions, but stack traces show mangled function names rather than detailed line numbers. These mangled names are close enough to actual Swift identifiers to help locate the offending function.

A crash from `fatalError("CRASHME")` produces output like:
```
HelloSwiftModel.ViewModel.(saveItems in _AA1DA8893D92B109DC6527A80C9D3046)()
```

To decode mangled names, use: `echo '[mangled_name]' | xcrun swift-demangle`

**Note:** Skip collaborates with the Swift on Android Working Group to enhance debugging experiences on Android.

## Logging

Standard `print` statements don't appear in Android logs. Instead, use the `OSLog.Logger` API for dual-platform logging:

```swift
import SkipFuse
let logger = Logger(subsystem: "my.subsystem", category: "MyCategory")
logger.info("My message")
```

For Skip Lite, import `OSLog` instead. Swift-side messages appear in Xcode's console, while Android implementations forward to Logcat, viewable through Android Studio's Logcat tab or terminal via `adb logcat`.

## Accessing Generated Source

### Dual-Platform Apps
Xcode stores generated source in `DerivedData/plugins`, surfaced as the `SkipStone/plugins` group in projects. If the group won't expand initially, restart Xcode or manually set the group type to "Folder" in Xcode's inspector panel.

### Frameworks
Use the `Create SkipLink` command plugin by control-clicking your package or accessing `File → Packages`. This creates a `SkipLink` group providing access to Android projects and generated source.

### Jumping to Generated Source
After linking generated files, use `Open Quickly (cmd-shift-O)` to navigate to generated files, which share names with Swift counterparts but use `_Bridge.swift` suffixes or `.kt` extensions. Note that Skip moves extension code into declaring Kotlin classes, potentially placing it in different files than their Swift originals.

Build errors from Android compilers appear as Xcode errors, allowing direct navigation to problematic bridging or Kotlin code.
