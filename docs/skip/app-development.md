<!-- Source: https://skip.dev/docs/app-development/ -->

# App Development

## Overview

Skip enables sharing code between iOS and Android apps. The platform allows developers to write dual-platform applications while maintaining the ability to use platform-specific features when needed.

## Philosophy

A critical principle: build errors don't prohibit using iOS features. Skip was intentionally designed to handle multi-platform limitations by making it straightforward to exclude unsupported code from Android builds using compiler directives.

Key concepts:
- Any iOS feature can be used inline without architectural changes
- Android fallbacks or alternatives can be implemented separately
- Thousands of cross-platform modules are already supported
- Swift packages can be ported to Android when needed

## Building and Running

### Requirements

Android development requires either an emulator or physical device with developer mode enabled. Create an emulator using `skip android emulator create` and launch it with `skip android emulator launch`, or use Android Studio's Device Manager.

### Running on Android Devices

Enable USB debugging and pair devices via ADB. Only one device/emulator should run simultaneously, unless you specify the `ANDROID_SERIAL` variable in the project's `.xcconfig` file.

**Performance note:** Release builds perform significantly better than Debug builds on physical devices.

### Dual-Platform Development

Successful builds automatically attempt launching on the active Android emulator/device. The Xcode plugin handles this integration.

#### iOS-Only Development Workaround

Modify `AppName.xcconfig` to control Android build behavior:
- `SKIP_ACTION = launch` - builds and runs Android (default)
- `SKIP_ACTION = build` - builds Android without running
- `SKIP_ACTION = none` - skips Android build entirely

⚠️ **Caution:** Leaving `SKIP_ACTION = none` long-term may allow Android-specific errors to accumulate undetected.

### Separate iOS and Android Apps

Developers choosing separate apps build each in its respective IDE while sharing dual-platform Swift frameworks. The Project Types guide provides integration guidance.

### Framework Development

Building frameworks in Xcode compiles iOS code but doesn't perform Android builds due to plugin limitations. Run unit tests against macOS destinations to trigger Android compilation.

**Critical requirement:** Test frameworks against macOS destinations—iOS testing won't run Android tests.

## Coding

### Build Error Handling

The Skip build plugin provides early warnings before Android compilation begins. Errors map to Swift source code and appear both inline and in Xcode's issue navigator. Common errors include:

- Unsupported APIs on Android
- Missing or incorrect imports for cross-platform Swift
- Generated Kotlin compilation failures

### Runtime Errors and Debugging

See the Debugging chapter for accessing generated code, viewing logs, and debugging Android components.

## UI and View Model Development

### SwiftUI and Compose Integration

Skip translates SwiftUI subsets into Jetpack Compose, enabling cross-platform UI development. Developers can also write separate Compose interfaces or combine both approaches.

### Observable Integration

`@Observable` model types automatically participate in Compose state tracking, powering Android interfaces identically to iOS.

**Requirements for Compose integration:**
- Import SkipFuse in Observable Swift files
- Ensure Observables are bridged for Kotlin usage
- Add SwiftPM dependency on SkipModel for bespoke Compose UIs

**Note:** SkipModel inclusion is automatic when using SwiftUI interfaces.

### SwiftUI Best Practices

When writing cross-platform SwiftUI:
- Use default or public visibility for Views and their properties
- Private visibility is acceptable for non-SwiftUI members only
- Skip cannot access private SwiftUI components on Android

Example pattern:
```swift
import SwiftUI
struct MyView: View {
    @State var counter = 1  // Public/internal required
    private let title = "..."  // Private OK for non-SwiftUI
    var body: some View { ... }
}
```

Browse the [SkipUI documentation](/docs/modules/skip-ui/#supported-swiftui) for complete SwiftUI support details.

## Handling Unsupported iOS Features

### API Coverage

Unsupported iOS APIs generate unavailable or build errors. Solutions include:

1. **Check porting guides** - Some APIs work on Android with different imports
2. **Consult SkipUI documentation** - For SwiftUI coverage details
3. **Search Swift Package Index** - Find alternative cross-platform packages
4. **Implement platform-specific code** - Use compiler directives for separate implementations
5. **Contribute to libraries** - Augment existing Skip or community libraries

### Framework Alternatives

Skip Fuse supports thousands of third-party modules. When these don't suffice:
- Create custom dual-platform libraries
- Implement shared APIs across platforms
- Consider contributing community libraries

### iOS-Specific Features

App extensions and features without Android equivalents require platform-specific implementations. Use compiler directives to exclude iOS code from Android builds while providing native Android alternatives.

## Common Development Tasks

Advanced topics like localization, resource/image loading, and JSON coding are covered in the Common Topics section.

## Additional Resources

- [Cross-Platform Topics](/docs/platformcustomization/) - Platform integration techniques
- [Debugging Guide](/docs/debugging/) - Development troubleshooting
- [Porting Guide](/docs/porting/) - Cross-platform Swift considerations
- [Dependencies Documentation](/docs/dependencies/) - Using dual-platform and platform-specific libraries
