<!-- Source: https://skip.dev/docs/swiftsupport/ -->
# Transpilation Reference

## Overview

Skip's Swift to Kotlin transpiler converts a substantial portion of Swift into Kotlin. The transpiler prioritizes three goals:

1. Avoid generating buggy code - errors or compilation failures are preferred over subtle behavioral differences
2. Enable natural Swift coding across its most common features
3. Generate idiomatic Kotlin output

## Key Language Features

### Fully Supported
- Classes with inheritance and Codable synthesis
- Structs with value semantics, constructor synthesis, protocol synthesis (Equatable, Hashable, Codable)
- Protocols with inheritance, property/function requirements
- Nested types (excluding types within functions)
- Extensions for concrete types and protocols
- Generic types (with some limitations)
- Tuples (labeled/unlabeled, arity 2-5)
- Properties: let, var, static, stored, computed, throwing, lazy, willSet, didSet
- SwiftUI property wrappers: @State, @Environment, etc.
- Functions with overloading on types and parameter labels
- Closures and trailing closures
- Enums with associated values, RawRepresentable, CaseIterable, Equatable, Hashable synthesis
- Error handling: throw, do/catch, try, try?, try!
- Concurrency: Task, async/await, AsyncSequence, AsyncStream, @MainActor, custom actors
- Control flow: if/guard with let/case, switch with pattern matching, for-in with where
- Operators: standard, optional chaining, range, Equatable, Hashable, Comparable, callAsFunction

### Not Supported
- Types defined within functions
- Custom property wrappers
- Function overloading on return type
- @autoclosure parameters
- Parameter packs
- Grand Central Dispatch
- Compound types (A & B)
- String mutation
- Custom operators (beyond listed ones)
- Macros (except @Observable and @ObservationIgnored)

## Special Topics

### Numeric Types
Kotlin Ints are 32 bits while Swift assumes 64-bit. Use Int64 for values exceeding 32-bit range. Float requires explicit specification.

### Strings
Strings are immutable and not Collections in Kotlin. New strings must be created rather than appending.

### Garbage Collection
Swift uses ARC; Kotlin uses garbage collection. On Android, deinit functions will be called at an indeterminate time. Skip ignores weak and unowned modifiers.

### Structs and Value Semantics
Skip uses its MutableStruct protocol to enable value semantics on the JVM. Transpiled code includes .sref() calls for struct reference copying. Use @nocopy for never-modified-after-initialization structs.

### Generics Limitations
Swift generics are first-class citizens; Kotlin generics don't exist at the JVM level. Limited support for static members of generic types, generic specialization, inner types on generic outer types.

Swift functions with `@inline(__always)` convert to Kotlin inline functions with reified generics.

### Concurrency
Skip doesn't support Grand Central Dispatch; use modern async/await. @MainActor isn't automatically inherited except for View.body.

### Conditional Compilation
```swift
func languageName() -> String {
    #if os(Android)
    "Kotlin"
    #else
    "Swift"
    #endif
}
```

### SKIP Comments
```swift
func languageName() -> String {
    // SKIP REPLACE: return "Kotlin"
    "Swift"
}
```
