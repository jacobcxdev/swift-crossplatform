# AppStorage Value Type Bridging on Android

**Phase 4 Research — Deep Dive**
**Date:** 2026-02-22

---

## 1. AppStorageKey Type Dispatch Architecture

`AppStorageKey<Value>` (in `forks/swift-sharing/Sources/Sharing/SharedKeys/AppStorageKey.swift`) uses a **protocol-based strategy pattern** for type dispatch, not a type-erased lookup table.

### The Lookup Protocol

```swift
private protocol Lookup<Value>: Sendable {
    associatedtype Value: Sendable
    func loadValue(from store: UserDefaults, at key: String, default defaultValue: Value?) -> Value?
    func saveValue(_ newValue: Value, to store: UserDefaults, at key: String)
}
```

### Lookup Implementations

There are **five** concrete Lookup types:

| Lookup Struct | Purpose | Used By |
|---|---|---|
| `CastableLookup<Value>` | Direct cast via `store.object(forKey:) as? Value` + `store.set(_:forKey:)` | Bool, Int, Double, String, [String], Data, Date |
| `URLLookup` | Uses `store.url(forKey:)` + `store.set(_:forKey:)` | URL |
| `CodableLookup<Value>` | JSON encode/decode via `store.data(forKey:)` + `store.set(encoded, forKey:)` | Any `Codable` (disfavored overload) |
| `RawRepresentableLookup<Value, Base>` | Wraps a base Lookup, converts via `rawValue`/`init(rawValue:)` | RawRepresentable<Int>, RawRepresentable<String> |
| `OptionalLookup<Base>` | Wraps a base Lookup, handles nil via `store.removeObject(forKey:)` | All optional variants |

### How CastableLookup Works

```swift
// Load: cast from Any?
guard let value = store.object(forKey: key) as? Value else {
    // Write default value back to store on first access
    store.set(defaultValue, forKey: key)
    return nil
}
return value

// Save: generic set
store.set(newValue, forKey: key)
```

This is the critical path for Android. `CastableLookup` calls `store.set(newValue, forKey:)` where `newValue` is typed as the generic `Value`. On Apple platforms, `UserDefaults.set(_:forKey:)` accepts `Any?` and internally dispatches. On Android, the value hits `AndroidUserDefaults.set(_ value: Any?, forKey:)` which delegates to `UserDefaultsAccess.set(_ value: Any?, forKey:)` which delegates to `skip.foundation.UserDefaults.set(_ value: Any?, forKey:)`.

### How URLLookup Works

```swift
// Load: typed accessor
guard let value = store.url(forKey: key) else { ... }

// Save: generic set (NOT set(_ url: URL?, forKey:))
store.set(newValue, forKey: key)
```

Note: `URLLookup.saveValue` calls `store.set(newValue, forKey:)` where `newValue` is `URL`. This routes to the `set(_ value: Any?, forKey:)` overload, not `set(_ url: URL?, forKey:)`. On Android, Skip Foundation's `set(_ value: Any?, forKey:)` handles URL explicitly (see Section 5).

---

## 2. Supported Value Types — Complete List

### Non-Optional Types

| # | Type | Lookup | Init Overload |
|---|---|---|---|
| 1 | `Bool` | `CastableLookup` | `init(_:store:) where Value == Bool` |
| 2 | `Int` | `CastableLookup` | `init(_:store:) where Value == Int` |
| 3 | `Double` | `CastableLookup` | `init(_:store:) where Value == Double` |
| 4 | `String` | `CastableLookup` | `init(_:store:) where Value == String` |
| 5 | `[String]` | `CastableLookup` | `init(_:store:) where Value == [String]` |
| 6 | `URL` | `URLLookup` | `init(_:store:) where Value == URL` |
| 7 | `Data` | `CastableLookup` | `init(_:store:) where Value == Data` |
| 8 | `Date` | `CastableLookup` | `init(_:store:) where Value == Date` |
| 9 | `Codable` (generic) | `CodableLookup` | `init(_:store:) where Value: Codable` (@disfavoredOverload) |
| 10 | `RawRepresentable<Int>` | `RawRepresentableLookup(base: CastableLookup)` | `init(_:store:) where Value: RawRepresentable<Int>` |
| 11 | `RawRepresentable<String>` | `RawRepresentableLookup(base: CastableLookup)` | `init(_:store:) where Value: RawRepresentable<String>` |

### Optional Types

| # | Type | Lookup | Notes |
|---|---|---|---|
| 12 | `Bool?` | `OptionalLookup(base: CastableLookup)` | |
| 13 | `Int?` | `OptionalLookup(base: CastableLookup)` | |
| 14 | `Double?` | `OptionalLookup(base: CastableLookup)` | |
| 15 | `String?` | `OptionalLookup(base: CastableLookup)` | |
| 16 | `[String]?` | `OptionalLookup(base: CastableLookup)` | |
| 17 | `URL?` | `OptionalLookup(base: URLLookup)` | |
| 18 | `Data?` | `OptionalLookup(base: CastableLookup)` | |
| 19 | `Date?` | `OptionalLookup(base: CastableLookup)` | |
| 20 | `Codable?` (generic) | `OptionalLookup(base: CodableLookup)` | @disfavoredOverload |
| 21 | `RawRepresentable<Int>?` | `OptionalLookup(base: RawRepresentableLookup(base: CastableLookup))` | |
| 22 | `RawRepresentable<String>?` | `OptionalLookup(base: RawRepresentableLookup(base: CastableLookup))` | |

---

## 3. UserDefaults on Android via Skip — The Bridge Chain

### Architecture (3 layers)

```
Swift native code (AppStorageKey)
  --> AndroidUserDefaults (Swift, os(Android) || ROBOLECTRIC)
    --> UserDefaultsAccess (SKIP, Kotlin-side bridge)
      --> skip.foundation.UserDefaults (Kotlin, wraps SharedPreferences)
        --> android.content.SharedPreferences (Android platform)
```

### AndroidUserDefaults (Native Swift Subclass)

File: `forks/skip-android-bridge/Sources/SkipAndroidBridge/AndroidUserDefaults.swift`

Subclasses `Foundation.UserDefaults` and overrides all methods. Delegates to `UserDefaultsAccess` which runs on the Kotlin side.

**Available methods:**
- `object(forKey:)` -- works
- `set(_ value: Any?, forKey:)` -- works
- `removeObject(forKey:)` -- works
- `string(forKey:)` -- works
- `data(forKey:)` -- works
- `integer(forKey:)` -- works
- `float(forKey:)` -- works
- `double(forKey:)` -- works
- `bool(forKey:)` -- works
- `url(forKey:)` -- works
- `set(_ value: Int, forKey:)` -- works
- `set(_ value: Float, forKey:)` -- works
- `set(_ value: Double, forKey:)` -- works
- `set(_ value: Bool, forKey:)` -- works
- `set(_ url: URL?, forKey:)` -- works
- `register(defaults:)` -- works
- `dictionaryRepresentation()` -- works
- `synchronize()` -- returns true (no-op)

**Unavailable methods (marked `@available(*, unavailable)`):**
- `array(forKey:)` -- **PROBLEM for [String]**
- `dictionary(forKey:)` -- not used by AppStorageKey
- `stringArray(forKey:)` -- **PROBLEM for [String]**
- `addSuite(named:)` / `removeSuite(named:)` -- not used
- `volatileDomainNames` / `volatileDomain(forName:)` / `removeVolatileDomain(forName:)` -- not used
- `persistentDomain(forName:)` / `setPersistentDomain(_:forName:)` / `removePersistentDomain(forName:)` -- not used
- `objectIsForced(forKey:)` -- not used

### skip.foundation.UserDefaults (Kotlin Implementation)

File: `forks/skip-android-bridge/.build/checkouts/skip-foundation/Sources/SkipFoundation/UserDefaults.swift` (transpiled to Kotlin)

Wraps `android.content.SharedPreferences`. Uses `SharedPreferences.Editor` for writes with `apply()` (async commit).

**Storage strategy for types not natively supported by SharedPreferences:**

SharedPreferences natively supports: `Int`, `Float`, `Long`, `Boolean`, `String`, `Set<String>`. Everything else requires encoding.

Skip Foundation uses an **unrepresentable type tagging system**:
- Stores a companion key `__unrepresentable__:<key>` with an int type tag
- Tags: `double=1`, `date=2`, `data=3`, `url=4`

---

## 4. Data Type Handling

### How Data is Stored

**Write path:** `set(_ value: Any?, forKey:)` detects `Data` type and calls:
```swift
prefs.putString(defaultName, dataToString(v))
putUnrepresentableType(prefs, type: .data, forKey: defaultName)
```

**Encoding:** `dataToString` uses **base64 encoding**:
```swift
private func dataToString(_ data: Data) -> String {
    return data.base64EncodedString()
}
```

**Read path:** `data(forKey:)` and `object(forKey:)` both handle the reverse:
- `object(forKey:)` checks the unrepresentable type tag and calls `dataFromString`
- `data(forKey:)` also handles a legacy `__data__:` string prefix format
- `dataFromString` uses `Data(base64Encoded: string)`

**Android compatibility:** WORKS. Base64 encoding is platform-independent. The `CastableLookup` in AppStorageKey calls `store.set(data, forKey:)` which routes to `set(_ value: Any?, forKey:)` which handles `Data` correctly.

### Potential Issue

`CastableLookup.loadValue` does `store.object(forKey: key) as? Value` where `Value == Data`. The `object(forKey:)` on Android returns the decoded `Data` from `fromStoredRepresentation`, so the cast should work. However, if `fromStoredRepresentation` returns a `String` instead of `Data` (due to a missing type tag), the cast would fail and the default value would be written back. This is a **silent data loss risk** if type tags get corrupted.

---

## 5. URL Type Handling

### How URL is Stored

**Write path:** `set(_ value: Any?, forKey:)` detects `URL` type:
```swift
} else if let v = value as? URL {
    prefs.putString(defaultName, v.absoluteString)
    putUnrepresentableType(prefs, type: .url, forKey: defaultName)
}
```

**Stored as:** String (the absolute URL string) + unrepresentable type tag `.url`

**Read path:** `url(forKey:)`:
```swift
if let url = value as? URL { return url }
else if let string = value as? String { return URL(string: string) }
```

And `object(forKey:)` via `fromStoredRepresentation`:
```swift
case .url: return URL(string: string)
```

**Android compatibility:** WORKS. No `NSKeyedArchiver` is used. URLs are stored as plain strings. This is actually simpler and more reliable than Apple's `UserDefaults` which uses archiving for `set(_ url:)` but string storage for `set(_ value: Any?)` with a URL.

**Important note:** `URLLookup.saveValue` calls `store.set(newValue, forKey:)` where `newValue: URL`. On Android this routes through `AndroidUserDefaults.set(_ value: Any?, forKey:)` (not `set(_ url:, forKey:)`), which then goes to Skip Foundation's `set(_ value: Any?, forKey:)` which has the explicit URL branch. This works correctly.

`URLLookup.loadValue` calls `store.url(forKey:)` which is implemented in `AndroidUserDefaults` and delegates to `UserDefaultsAccess.url(forKey:)` -> `skip.foundation.UserDefaults.url(forKey:)`. This works correctly.

---

## 6. Date Type Handling

### How Date is Stored

**Write path:** `set(_ value: Any?, forKey:)` detects `Date` type:
```swift
} else if let v = value as? Date {
    prefs.putString(defaultName, dateToString(v))
    putUnrepresentableType(prefs, type: .date, forKey: defaultName)
}
```

**Encoding:** `dateToString` uses **ISO 8601 formatting**:
```swift
private func dateToString(_ date: Date) -> String {
    return date.ISO8601Format()
}
```

**Read path:** `object(forKey:)` via `fromStoredRepresentation`:
```swift
case .date: return dateFromString(string)
```
Uses `ISO8601DateFormatter().date(from:)`.

**Android compatibility:** WORKS with caveats.

**Caveats:**
1. ISO 8601 formatting loses sub-second precision (standard format is seconds-level). If a `Date` with millisecond precision is stored, the fractional seconds may be lost on round-trip. On Apple platforms, `Date` stored via `set(_ value: Any?, forKey:)` uses `TimeInterval` (Double) internally, preserving full precision. Android loses precision.
2. No dedicated `set(_ date:, forKey:)` typed overload exists in Skip Foundation. Dates must go through the `set(_ value: Any?, forKey:)` path.
3. `CastableLookup` is used for `Date`. On load, `store.object(forKey:) as? Date` requires that `fromStoredRepresentation` successfully converts the ISO 8601 string back to a `Date`. If the type tag is present, this works. If missing, it returns the raw String which fails the `as? Date` cast.

---

## 7. RawRepresentable Enum Handling

### Architecture

`RawRepresentableLookup` wraps a `CastableLookup` for the raw value type:

```swift
private struct RawRepresentableLookup<Value: RawRepresentable & Sendable, Base: Lookup>: Lookup
where Value.RawValue == Base.Value {
    let base: Base
    func loadValue(...) -> Value? {
        base.loadValue(from: store, at: key, default: defaultValue?.rawValue)
            .flatMap(Value.init(rawValue:))
    }
    func saveValue(_ newValue: Value, ...) {
        base.saveValue(newValue.rawValue, to: store, at: key)
    }
}
```

**For `RawRepresentable<Int>`:** Stores/loads the `Int` raw value via `CastableLookup<Int>`. The Int is stored as `putInt` in SharedPreferences. On load, `object(forKey:)` returns the Int, cast to `Int` succeeds, then `Value.init(rawValue:)` reconstructs the enum.

**For `RawRepresentable<String>`:** Stores/loads the `String` raw value via `CastableLookup<String>`. The String is stored as `putString` in SharedPreferences. Same reconstruction pattern.

**Android compatibility:** WORKS. Both Int and String are native SharedPreferences types. No encoding/tagging needed. Raw values are stored directly and reconstructed correctly.

---

## 8. Optional Handling

### Architecture

`OptionalLookup` wraps any base Lookup:

```swift
private struct OptionalLookup<Base: Lookup>: Lookup {
    let base: Base
    func loadValue(...) -> Base.Value?? {
        base.loadValue(from: store, at: key, default: defaultValue ?? nil)
            .flatMap(Optional.some) ?? .none
    }
    func saveValue(_ newValue: Base.Value?, ...) {
        if let newValue {
            base.saveValue(newValue, to: store, at: key)
        } else {
            store.removeObject(forKey: key)
        }
    }
}
```

**Nil storage:** Calls `store.removeObject(forKey:)`.

**Android compatibility:** WORKS. `AndroidUserDefaults.removeObject(forKey:)` is implemented and delegates to `UserDefaultsAccess.removeObject(forKey:)` -> `skip.foundation.UserDefaults.removeObject(forKey:)` which calls:
```swift
let prefs = platformValue.edit()
prefs.remove(defaultName)
prefs.remove("__unrepresentable__:\(defaultName)")
prefs.apply()
```

Both the value and its type tag are cleaned up correctly.

---

## 9. Concurrent Access / Thread Safety

### Apple Platforms
`UserDefaults` is thread-safe on Apple platforms. KVO notifications are delivered on the thread that made the change. `AppStorageKey` uses `SharedAppStorageLocals.$isSetting` (a `@TaskLocal`) to prevent re-entrant notification loops.

### Android via Skip
- **SharedPreferences reads** (`getAll()`, `getInt()`, etc.) are thread-safe by Android platform guarantee.
- **SharedPreferences writes** use `Editor.apply()` which is async and thread-safe by Android platform guarantee. Writes are committed to memory immediately and flushed to disk asynchronously.
- **No KVO/notification support:** `AppStorageKey.subscribe()` returns a no-op `SharedSubscription` on Android. This means external changes (from other processes or direct SharedPreferences access) are NOT observed. Values are only read on explicit `load()`.
- **`SharedAppStorageLocals.$isSetting`** (`@TaskLocal`) still functions on Android for re-entrancy protection.
- **`didChangeNotification`** is marked `@available(*, unavailable)` in Skip Foundation. The notification-based observation path in `AppStorageKey.subscribe()` is correctly guarded by `#if os(Android)`.

**Verdict:** Thread-safe for read/write. No observation of external changes. TCA's `Observing` wrapper handles Compose recomposition independently.

---

## 10. Android-Specific Patches Already Present

### In AppStorageKey.swift (`forks/swift-sharing`)

| Line(s) | Guard | Purpose |
|---|---|---|
| 1 | `#if canImport(AppKit) \|\| canImport(UIKit) \|\| canImport(WatchKit) \|\| os(Android)` | Enables the entire file on Android |
| 315 | `#if DEBUG && !os(Android)` | Skips suite identity debug check (uses `Selector`/ObjC runtime, unavailable on Android) |
| 457-461 | `#if os(Android)` | Returns no-op subscription (no KVO on Android) |
| 462 | `#else` | Apple KVO/notification observation path |
| 536 | `#endif` | End of subscribe method platform split |
| 547-563 | `#if !os(Android)` | Excludes `Observer` NSObject subclass (KVO observer, uses ObjC runtime) |
| 631-632 | `#if os(Android)` | Simplified `inMemory` suite name (no `NSTemporaryDirectory`, no iOS 16 workaround) |
| 778 | `#if DEBUG && !os(Android)` | Excludes `suites` mutex (debug-only suite identity tracking) |

### In Other swift-sharing Files

| File | Line | Guard | Purpose |
|---|---|---|---|
| `Shared.swift` | 497 | `#if !os(Android)` | Excludes `DynamicProperty.update()` (uses SwiftUI state subscription) |
| `SharedReader.swift` | 358 | `#if !os(Android)` | Excludes `DynamicProperty.update()` |

---

## 11. Type Compatibility Matrix

### Legend
- **OK** = Works correctly on Android
- **RISK** = Works but with caveats
- **BROKEN** = Known to fail

| Type | Store Method | Load Method | Android Status | Notes |
|---|---|---|---|---|
| `Bool` | `set(_ value: Any?)` -> `putBoolean` | `object(forKey:)` -> `as? Bool` | **OK** | Native SharedPreferences type |
| `Int` | `set(_ value: Any?)` -> `putInt` | `object(forKey:)` -> `as? Int` | **OK** | Native SharedPreferences type |
| `Double` | `set(_ value: Any?)` -> `putLong(toRawBits())` | `object(forKey:)` -> type tag -> `Double.fromBits` | **RISK** | Stored as Long via raw bits + type tag; `as? Double` cast depends on `fromStoredRepresentation` returning a `Double` |
| `String` | `set(_ value: Any?)` -> `putString` | `object(forKey:)` -> `as? String` | **OK** | Native SharedPreferences type |
| `[String]` | `set(_ value: Any?)` | `object(forKey:)` -> `as? [String]` | **BROKEN** | `array(forKey:)` and `stringArray(forKey:)` are `@available(*, unavailable)` in AndroidUserDefaults. `set(_ value: Any?, forKey:)` has no branch for arrays. Array is silently ignored (hits the `else { return }` branch) |
| `URL` | `set(_ value: Any?)` -> `putString(absoluteString)` + tag | `url(forKey:)` -> `URL(string:)` | **OK** | Stored as string, reconstructed via URL(string:) |
| `Data` | `set(_ value: Any?)` -> `putString(base64)` + tag | `object(forKey:)` -> tag -> `Data(base64Encoded:)` | **OK** | Base64 encoding is portable |
| `Date` | `set(_ value: Any?)` -> `putString(ISO8601)` + tag | `object(forKey:)` -> tag -> `ISO8601DateFormatter` | **RISK** | Loses sub-second precision on round-trip |
| `Codable` (generic) | `JSONEncoder` -> `set(encoded, forKey:)` -> `putString(base64)` + tag | `data(forKey:)` -> `JSONDecoder` | **OK** | JSON encoding is portable; stored as Data which is base64 |
| `RawRepresentable<Int>` | stores raw `Int` via `CastableLookup` | loads `Int`, calls `init(rawValue:)` | **OK** | Int is native SharedPreferences type |
| `RawRepresentable<String>` | stores raw `String` via `CastableLookup` | loads `String`, calls `init(rawValue:)` | **OK** | String is native SharedPreferences type |
| `Bool?` | same as Bool / `removeObject` for nil | same as Bool | **OK** | |
| `Int?` | same as Int / `removeObject` for nil | same as Int | **OK** | |
| `Double?` | same as Double / `removeObject` for nil | same as Double | **RISK** | Same Double caveat |
| `String?` | same as String / `removeObject` for nil | same as String | **OK** | |
| `[String]?` | same as [String] / `removeObject` for nil | same as [String] | **BROKEN** | Same [String] problem |
| `URL?` | same as URL / `removeObject` for nil | same as URL | **OK** | |
| `Data?` | same as Data / `removeObject` for nil | same as Data | **OK** | |
| `Date?` | same as Date / `removeObject` for nil | same as Date | **RISK** | Same Date precision caveat |
| `Codable?` | same as Codable / `removeObject` for nil | same as Codable | **OK** | |
| `RawRepresentable<Int>?` | same as RawRep<Int> / `removeObject` for nil | same as RawRep<Int> | **OK** | |
| `RawRepresentable<String>?` | same as RawRep<String> / `removeObject` for nil | same as RawRep<String> | **OK** | |

---

## 12. Issues Requiring Action

### BROKEN: `[String]` Array Storage

**Severity:** High
**Impact:** `AppStorageKey<[String]>` and `AppStorageKey<[String]?>` will silently fail to persist on Android.

**Root cause:** Skip Foundation's `set(_ value: Any?, forKey:)` has no branch for arrays. The value hits the `else { return }` fallback and is silently discarded. Both `array(forKey:)` and `stringArray(forKey:)` are marked `@available(*, unavailable)`.

**Fix options:**
1. Add `[String]` support to Skip Foundation's `set(_ value: Any?, forKey:)` using JSON serialization or a `Set<String>` (SharedPreferences supports `Set<String>` natively via `putStringSet`)
2. Add `set(_ value: [String], forKey:)` typed overload to `UserDefaultsAccess` and `AndroidUserDefaults`
3. In `AppStorageKey`, use a different Lookup for `[String]` on Android (e.g., `CodableLookup` since `[String]` is `Codable`)

**Recommended fix:** Option 3 is the least invasive -- change `[String]` and `[String]?` to use `CodableLookup` on Android. This stores the array as JSON-encoded Data (base64 in SharedPreferences), avoiding the need to modify Skip Foundation.

### RISK: Double Precision / Cast Behavior

**Severity:** Medium
**Impact:** `Double` is stored as `Long` (raw bits) in SharedPreferences. The `object(forKey:)` path uses `fromStoredRepresentation` to decode the Long back to Double using the type tag. If `CastableLookup` does `store.object(forKey:) as? Double` and `fromStoredRepresentation` already returns a `Double`, this works. But if the type tag is missing or corrupted, the raw `Long` value would be returned, and `as? Double` would fail.

**Mitigation:** The type tag system is reliable for values written through Skip Foundation. Risk only exists for pre-existing values or values written by external code.

### RISK: Date Precision Loss

**Severity:** Low (for TCA use cases)
**Impact:** Dates lose sub-second precision when round-tripped through ISO 8601 format. Standard `ISO8601DateFormatter` output is `2026-02-22T12:34:56Z` (no fractional seconds).

**Mitigation:** Most app-level Date storage does not require sub-second precision. If needed, store as `Double` (TimeInterval) or use `Codable` which would go through JSON encoding.

### INFO: No Change Observation

**Severity:** Acknowledged (already handled)
**Impact:** `subscribe()` returns a no-op on Android. External changes to SharedPreferences are not observed.

**Status:** Already patched in the fork. The comment in the code explains the rationale: TCA's `Observing` wrapper handles Compose recomposition. Skip Foundation does have `registerOnSharedPreferenceChangeListener` available if observation is ever needed.

---

## 13. Summary

The AppStorage bridging is **mostly functional** on Android with 3 layers of delegation (AndroidUserDefaults -> UserDefaultsAccess -> skip.foundation.UserDefaults -> SharedPreferences). The type dispatch through the Lookup protocol works correctly for all types except `[String]` arrays.

**Action items for Phase 4:**
1. Fix `[String]` storage (BROKEN) -- either patch Skip Foundation or use CodableLookup on Android
2. Add integration tests for all value types on Android (especially Double round-trip, Date round-trip, Data round-trip)
3. Consider whether Date precision loss matters for any TCA state being persisted
4. Document the observation limitation for developers using `@Shared(.appStorage(...))` on Android
