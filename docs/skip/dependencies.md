<!-- Source: https://skip.dev/docs/dependencies/ -->

# Skip Dependencies Guide

## Overview

Skip projects support four types of dependencies:

1. A dependency on a dual-platform Skip package
2. Pure Swift Package Manager packages
3. Kotlin or Java packages for Android only
4. Separate iOS and Android libraries with common functionality

## Skip Package Dependencies

When adding external Skip SwiftPM packages via `Package.swift`, the system automatically detects the dependency's `Skip/skip.yml` file and creates corresponding Gradle dependencies for Android. This means SwiftPM dependencies automatically translate to Android dependencies.

### Critical Warning

**The Xcode 'Add Package Dependencies…' menu should _not_ be used to add Swift dependencies, as it will not update the `Package.swift` file that Skip needs to build the dependencies for Android.**

Instead, manually edit your `Package.swift` file to add dependencies. This ensures that both iOS and Android builds can properly resolve the dependencies.

## Pure SwiftPM Packages

Thousands of SwiftPM packages support both iOS and Android. The Swift Package Index tracks Android-compatible packages. To exclude iOS-only packages from Android builds, use conditional dependency syntax in `Package.swift`:

```swift
.product(name: "Lottie", package: "lottie-ios",
         condition: .when(platforms: [.macOS, .iOS]))
```

This conditional dependency approach allows you to specify which platforms should include specific dependencies, preventing iOS-only packages from being included in Android builds.

### Limitation for Skip Lite

**Skip Lite modules cannot use pure SwiftPM packages for Android** if the dependency lacks a `Skip/skip.yml` file. This is an important constraint to keep in mind when selecting dependencies for Skip Lite projects.

## Java/Kotlin Dependencies

Android-specific libraries are configured through `skip.yml`. For example, SkipScript depends on external `jsc-android` libraries on Android (while using native JavaScriptCore on iOS).

### Configuration in skip.yml

Dependencies are specified in the `skip.yml` build block:

```yaml
build:
  contents:
    - block: 'dependencies'
      contents:
        - 'implementation("org.webkit:android-jsc:r245459@aar")'
```

### Importing Java/Kotlin Packages

For Android-only code, import packages using conditional compilation:

```swift
#if SKIP
import com.xyz.__
#endif
```

This pattern allows you to import Android-specific packages only when compiling for Android, preventing import errors on iOS.

## Separate Platform Libraries Pattern

When leveraging distinct iOS and Android libraries without unified cross-platform alternatives, implement a wrapper using compiler directives:

### Implementation Pattern

```swift
#if !os(Android)
import SomeIOSLibrary
#else
import com.xyz.someandroidlibrary.__
#endif

public struct MyCommonAPI {
    public func myCommonAPIFunc() -> String {
        #if !os(Android)
        return libraryInstance.someIOSLibraryFunction()
        #else
        return libraryInstance.someAndroidLibraryFunction()
        #endif
    }
}
```

### Best Practices

Skip frameworks like SkipKeychain exemplify this pattern. Ideally, mirror the original iOS API to enable direct use without custom wrapper documentation. This approach:

- Provides a unified interface across platforms
- Hides platform-specific implementation details
- Allows consumers to use a consistent API regardless of target platform
- Simplifies maintenance by centralizing the platform abstraction logic

When designing your wrapper APIs, aim to maintain API compatibility with the iOS library where possible, so that existing iOS code can be more easily adapted for cross-platform use.
