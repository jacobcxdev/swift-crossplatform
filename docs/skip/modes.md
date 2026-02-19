<!-- Source: https://skip.dev/docs/modes/ -->
# Lite and Fuse Modes

## Overview

Skip supports two deployment approaches for Swift-on-Android applications:

- **Fuse Mode** (Compiled): Native Swift compilation for Android using the Swift SDK
- **Lite Mode** (Transpiled): Swift source converted to equivalent Kotlin

These modes operate at the Swift module level, allowing mixed implementations within a single app. Bridging technology enables seamless interaction between compiled and transpiled components.

## Native Mode: Skip Fuse

Skip Fuse combines native Swift toolchain compilation with Android integration, bridging technology, and Xcode tooling for cross-platform development.

### Advantages

- **Full Language Support**: Unlike transpilation, native compilation handles all Swift language features without limitations.
- **Runtime Fidelity**: Swift's deterministic object deallocation cannot be replicated on the JVM, which uses indeterministic garbage collection to manage memory.
- **Complete Frameworks**: SkipLib and SkipFoundation provide extensive stdlib/Foundation coverage, though native Swift offers superior completeness.
- **Third-Party Ecosystem**: Thousands of Swift packages compile for Android, with porting often straightforward.
- **C/C++ Integration**: Native Swift unlocks superior C language interoperability versus the SkipFFI framework approach.
- **Performance**: Value types (structs, enums) enable stack allocation and faster bare-metal performance compared to garbage-collected runtimes.

### Disadvantages

- **App Size**: Bundling Swift standard library and Foundation adds approximately 60 megabytes to Android app bundles.
- **Kotlin/Java Bridging Overhead**: Data movement between compiled Swift and Kotlin/Java requires bridging configuration.
- **Debugging Complexity**: Debugging native code on Android is more difficult than debugging generated Kotlin.
- **Build Time**: Native compilation and native object packaging slower than transpilation.
- **Ejectability Loss**: If you eject Skip when using native mode, only your iOS app would remain fully intact.

## Transpiled Mode: Skip Lite

Transpilation converts Swift source into equivalent Kotlin for Android execution, combining a Swift-to-Kotlin transpiler with compatible libraries.

### Advantages

- **Android API Integration**: The primary benefit of transpilation is near-perfect integration with Android's Kotlin and Java APIs. Generated Kotlin code directly calls Android services.
- **Transparency**: Skip's Kotlin is fully human-readable and even overridable, enabling debugging visibility and insertion of literal Kotlin inline.
- **Ejectability**: Source code access preserves options for evolution as separate iOS/Android codebases. All free and open-source dependencies prevent vendor lock-in.
- **Smaller App Size**: Transpiled apps don't have to bundle anything but Skip's relatively slim compatibility libraries.
- **Faster Iteration**: The combination of Skip's transpiler and the Android Kotlin compiler is faster than building with the full native Swift toolchain.

### Disadvantages

- **Language Limitations**: Transpiler supports the vast majority of Swift syntax, but some features cannot map to Kotlin; runtime behavior differs on the JVM.
- **Framework Coverage**: SkipLib and SkipFoundation replicate significant stdlib/Foundation, but native Swift provides more complete coverage.
- **Library Scarcity**: Relatively few third-party transpiled libraries exist; native Swift boasts thousands of compatible packages.
- **C/C++ Integration**: SkipFFI enables interface creation but remains cumbersome compared to native Swift.
- **Performance Trade-offs**: Garbage collection and heap allocation create high memory watermark concerns versus native value types.

## Configuration

Every Skip module requires a `Skip/skip.yml` configuration file specifying the deployment mode:

```yaml
skip:
  mode: 'native'|'transpiled'
```

Default mode is `'transpiled'`. Projects support mixed native and transpiled modules.

### Package.swift Dependencies

Native app modules typically depend on:
- SkipFuse and SkipModel (model layer)
- SkipFuseUI (UI layer)

Transpiled modules depend on:
- SkipModel alone (model layer)
- SkipUI (UI layer)

## Bridging

Bridging enables transparent interaction between compiled Swift, transpiled Swift, and Kotlin/Java code through generated wrapper code, functioning similarly to Xcode bridging headers.

### Configuration

Add `// SKIP @bridge` comments to declarations you wish to expose:

```swift
// SKIP @bridge
public class Person {
    // SKIP @bridge
    public init() { ... }

    // SKIP @bridge
    public var firstName = ""

    public var age = 0  // Not bridged
}
```

### Bulk Bridging Configuration

Enable auto-bridging via `skip.yml`:

```yaml
skip:
  mode: 'native'
  bridging: true
```

When enabled, all public API bridges automatically. Use `// SKIP @nobridge` for exclusions:

```swift
public class Person {
    public init() { ... }

    // SKIP @nobridge
    public var age = 0
}
```

### Swift to Kotlin/Java Bridging

Native Swift modules with bridging enabled generate Kotlin wrapper delegates. Default wrappers optimize for transpiled Swift consumption using Skip library types (`skip.lib.Array`, `skip.foundation.URL`).

### Kotlin Compatibility Option

Configure `skip.yml` for direct Kotlin consumption:

```yaml
skip:
  mode: 'native'
  bridging:
    auto: true
    options: 'kotlincompat'
```

Generated Kotlin wrappers use standard types (`kotlin.collections.List`, `java.net.URI`) instead of Skip-specific types.

### Kotlin/Java to Swift Bridging

Enable bridging on transpiled modules to expose their Kotlin-calling capabilities to native Swift.

### AnyDynamicObject

`AnyDynamicObject` (from SkipFuse) represents any Kotlin/Java type, enabling dynamic property/function access through reflection:

```swift
import SkipFuse

let date = try AnyDynamicObject(className: "java.util.Date", 999)
let time1: Int64 = try date.getTime()!
let time2: Int64 = date.time!
date.time = 1001
let s: String = try date.instant!.toString()!
```

Static member access requires a special constructor:

```swift
let dateStatics = try AnyDynamicObject(forStaticsOfClassName: "java.util.Date")
let date: AnyDynamicObject? = try? dateStatics.parse(dateString)
```

### Dynamic Root Syntax Sugar

Configure `skip.yml` to enable namespace-based access:

```yaml
skip:
  mode: 'native'
  dynamicroot: 'D'
```

Enables intuitive type access:

```swift
let date = try D.java.util.Date(999)
let time: Int64 = date.time!

typealias JDate = D.java.util.Date
let d1 = JDate(999)
```

**Constraints**:
- Generated types have `internal` visibility (module-scoped)
- Types only generate for Android builds; guard with `#if os(Android)`

## Migrating Between Modes

Migrating between modes involves rewriting configuration files and adapting mode-specific code differences.

**Migration path**:
1. Update `skip.yml` and `Package.swift`
2. Address mode-specific behavioral differences
3. Reference Development and Cross-Platform Topics documentation

Native-to-transpiled migration may require removing unsupported Swift features; transpiled-to-native migration typically involves minimal refactoring due to native's broader capabilities.
