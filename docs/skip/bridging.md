<!-- Source: https://skip.dev/docs/bridging/ -->
# Bridging Reference

## Overview

Skip provides technology for bridging between compiled Swift and transpiled Swift/Kotlin/Java. This reference details which Swift language features and types can be bridged, with capabilities being symmetrical unless noted.

## Language Features Support

**Object-Oriented Constructs:**
- Classes with inheritance up to 4 levels
- Structs with constructor, Equatable, and Hashable synthesis
- Protocols with inheritance, property/function requirements
- Protocol constructor and static requirements: NOT supported
- Enums (with and without associated values)
- Mutating enum properties/functions: NOT supported
- Nested types
- Extensions: concrete types fully supported; protocol extensions partially; cross-module Kotlin-to-Swift only

**Type System:**
- Generic types with significant limitations
- Typealiases
- Tuples up to 5 elements (not as collection elements or closure parameters)

**Properties:**
- Globals, members, static properties
- Stored and computed properties
- Throwing properties
- Lazy properties: NOT supported

**Functions:**
- Globals, members, static functions
- Overloading on types and parameter labels
- Return type overloading: NOT supported
- Default parameter values
- `inout`, variadic, `@autoclosure` parameters: NOT supported
- Throwing functions
- Generic functions with limitations

**Other Features:**
- Constructors and deconstructors
- Closures up to 5 parameters
- Concurrency: async functions/properties/closures, @MainActor, custom actors (partial)
- Operators: Equatable, Hashable, Comparable supported; subscripts and callAsFunction not supported
- Key paths: NOT supported

## Builtin Types Support

**Fully Supported:**
- `Any`, `AnyHashable`, `AnyObject`, `Bool`
- Numeric types (Int/UInt are 32-bit on JVM)
- `String`, Optionals
- `Array`, `Set`, `Dictionary`
- `AsyncStream`, `AsyncThrowingStream<*, Error>`
- `Data`, `Date`, `Error`
- `Result`, `URL`, `UUID`, `NSNumber`
- 2-Tuples and 3-Tuples

**Not Supported:**
- `Character`
- Compound types (e.g., `A & B`)
- `OptionSet`

Fully-qualified Kotlin/Java types translate to `AnyDynamicObject`. In `kotlincompat` mode, many types map to Kotlin equivalents.

## Special Topics

### Equality

Do not rely on object identity and `===` comparisons of bridged instances. Multiple wrapper instances around the same native object may exist. Kotlin/Java projections implement `equals` and `hashCode` so wrappers comparing the same native instance will be equal and hash identically.

### Errors

Custom `Error` types bridge to Kotlin's `Exception`, so bridged Swift `Error` types cannot be subclasses. Functions throwing non-bridged Error types require general catch blocks without specific error type catching.

### Generics

Fundamental incompatibilities exist between Swift's compile-time generics and Kotlin's erased generics. Key restrictions:

- Cannot bridge subclasses of generic types
- Limited static members on generic types
- Generic specializations via extensions cannot bridge
- Inner types on generic outer types unsupported
- Kotlin constructors cannot use generics beyond the defining type
- Kotlin typealiases cannot include generic constraints

**Kotlin-to-Swift Only:** Exact typing is lost when generic types are returned via `Any` or protocol types.

**Swift-to-Kotlin Only:** Cannot construct bridged generic instances from Kotlin. Static members similarly restricted. Global generic functions lose type information when called from Kotlin.

### Mutable Structs

Recommend bridging native mutable structs only when consumed by transpiled Swift, which maintains value semantics on the Kotlin side. Pure Kotlin/Java usage should use classes for reference semantics. Avoid bridging transpiled mutable structs to native Swift due to significant JVM object copying requirements.
