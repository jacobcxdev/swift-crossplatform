<!-- Source: https://skip.dev/docs/platformcustomization/ -->

# Skip Platform Customization

## Overview

This section covers techniques for writing platform-specific code when developing with Skip. The documentation outlines methods for creating iOS-only or Android-only code paths, integrating Kotlin/Java APIs, mixing SwiftUI with Compose, and managing cross-platform development workflows.

## Compiler Directives

Skip supports conditional compilation using `os(Android)` conditions. Examples include:

```swift
#if os(Android)
print("Android")
#endif

#if !os(Android)
print("iOS")
#endif
```

These directives work within modifier chains and other Swift constructs.

## Calling Kotlin and Java APIs

### Core Mechanism

The `SKIP` conditional symbol enables calling native Kotlin and Java code. Code wrapped in `#if SKIP` blocks is transpiled to Kotlin during Android builds, allowing direct API access:

```swift
#if SKIP
func androidTimeString(milliseconds: Int64) -> String {
    let dateFormat = java.text.SimpleDateFormat(
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        java.util.Locale.getDefault()
    )
    dateFormat.timeZone = java.util.TimeZone.getTimeZone("GMT")
    return dateFormat.format(java.util.Date(milliseconds))
}
#endif
```

### Syntax Considerations

When embedding Kotlin in Swift `#if SKIP` blocks, observe these conventions:

- Named parameters use colons (`:`) in Swift, equals (`=`) in Kotlin
- Closures use `in` keyword in Swift, arrow (`->`) in Kotlin
- Import syntax uses `__` instead of `*` for wildcard imports

Example conversion from Kotlin to embedded Swift:

```swift
let start = 1
var result = 0
for i in 1..<10 {
    result += someFunction(value: start + i, block: { arg in arg + 1 })
}
```

### Complex Types

The `.kotlin()` function converts Skip's Swift types to equivalent Kotlin objects. This enables passing complex data between compiled Swift and transpiled code:

```swift
#if SKIP
extension Calendar: KotlinConverting<java.util.Calendar> {
    public func kotlin(nocopy: Bool = false) -> java.util.Calendar {
        return nocopy ? platformValue : platformValue.clone()
            as java.util.Calendar
    }
}
#endif
```

## Compose Integration

SwiftUI can embed pure Compose code through `ComposeView` and `ContentComposer`. This enables:

- Mixing SwiftUI and Compose components
- Accessing Android-specific UI elements
- Working around temporary Skip limitations

Example using Google Maps on Android and Apple Maps on iOS:

```swift
struct MapView : View {
    let latitude: Double
    let longitude: Double

    var body: some View {
        #if os(Android)
        ComposeView {
            MapComposer(latitude: latitude, longitude: longitude)
        }
        #else
        Map(initialPosition: .region(/*...*/))
        #endif
    }
}

#if SKIP
import com.google.maps.android.compose.__

struct MapComposer : ContentComposer {
    let latitude: Double
    let longitude: Double

    @Composable func Compose(context: ComposeContext) {
        GoogleMap(cameraPositionState: rememberCameraPositionState {
            position = CameraPosition.fromLatLngZoom(
                LatLng(latitude, longitude),
                Float(12.0)
            )
        })
    }
}
#endif
```

## Model Integration

Skip ensures `@Observable` types defined in shared Swift logic work seamlessly with Compose UI. In Skip Lite, `AsyncStream` provides deep Kotlin integration, allowing construction from Kotlin `Flow` objects and vice versa using `.kotlin()`.

## Android Context Access

### Skip Fuse

Retrieve Android references via extensions:

```swift
import SkipFuse

#if os(Android)
let applicationContext = ProcessInfo.processInfo
    .dynamicAndroidContext()
if let packageName: String = try? applicationContext.getPackageName() {
    // use packageName
}
#endif
```

### Skip Lite

Access Android objects in transpiled code:

```swift
import Foundation

#if SKIP
let applicationContext = ProcessInfo.processInfo.androidContext
let packageName = applicationContext.getPackageName()
#endif
```

## Skip Comments as Build Instructions

Special comments beginning with "SKIP" provide build instructions:

- `SKIP <Attributes>`: Apply Skip-specific attributes like `@bridge`, `@nocopy`, `@nodispatch`
- `SKIP DECLARE: <Kotlin>`: Replace declaration with custom Kotlin
- `SKIP INSERT: <Kotlin>`: Insert arbitrary Kotlin
- `SKIP REPLACE: <Kotlin>`: Replace entire statement with Kotlin
- `SKIP NOWARN`: Suppress warnings
- `SKIP SYMBOLFILE`: Mark file as header-only for symbols

Example:

```swift
// SKIP @bridge
struct S {
    // ...
}
```

## Kotlin and Java Files

Include native Kotlin/Java files by placing them in `Sources/<ModuleName>/Skip/` with `.kt` or `.java` extensions. These integrate directly into Android builds.

### Kotlin Package Names

Default transformation of Swift module names:

- `MyPackage` → `my.package`
- `MyHTTPLibrary` → `my.http.library`
- `Product` → `product.module` (minimum two segments required)

Customize in `skip.yml`:

```yaml
skip:
  package: 'org.example.mypackage'
```

## Android Studio Integration

### Setup

Point Android Studio to Xcode's `DerivedData` by editing `Android/settings.gradle.kts`:

```kotlin
System.setProperty("BUILT_PRODUCTS_DIR",
    "${System.getProperty("user.home")}/Library/Developer/Xcode/DerivedData/MyProject-xxxx/Build/Products/Debug-iphonesimulator"
)
```

### Opening Projects

For dual-platform apps, control-click `Android/settings.gradle.kts` and select "Open with External Editor," then sync in Android Studio.

### Unit Testing

Run tests in Xcode first to transpile, then open the test module's `settings.gradle.kts` in Android Studio for native debugging.

---

**Navigation**: [Previous: Common Topics](/docs/development-topics/) | [Next: Debugging](/docs/debugging/)
