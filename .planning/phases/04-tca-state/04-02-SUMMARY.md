# Phase 4 Wave 2 (04-02) — FileStorageKey Android + SharedPersistence Tests

## Fork Changes

### `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift`

1. **Outer guard expanded** — Added `|| os(Android)` to the `#if` guard on line 1 so the entire `FileStorageKey` compilation unit is available on Android.

2. **DispatchSource.FileSystemEvent polyfill** — Added a minimal `OptionSet` polyfill inside `#if os(Android)` after the import block. Android lacks `DispatchSource.FileSystemEvent`, so this stub provides `.write`, `.delete`, and `.rename` cases to satisfy the `FileStorage` struct's type signature.

3. **Android-specific `FileStorage.fileSystem`** — Wrapped the existing Darwin `fileSystem` static property in `#if os(Android) ... #else ... #endif`. The Android version:
   - Uses `DispatchQueue.main` for async scheduling (same as Darwin)
   - Returns a no-op `SharedSubscription` from `fileSystemSource` (no `DispatchSource` file monitoring on Android)
   - Uses simple `Data(contentsOf:)` for load (no `.stub` check needed)
   - The existing Darwin implementation is preserved unchanged in the `#else` branch

## Tests Written

### `SharedPersistenceTests` (17 tests, all passing)

| Test | Requirement | What it validates |
|------|------------|-------------------|
| `testAppStorageBool` | SHR-01 | Bool round-trip via AppStorage |
| `testAppStorageInt` | SHR-01 | Int round-trip |
| `testAppStorageDouble` | SHR-01 | Double round-trip (accuracy check) |
| `testAppStorageString` | SHR-01 | String round-trip |
| `testAppStorageData` | SHR-01 | Data round-trip |
| `testAppStorageURL` | SHR-01 | URL round-trip |
| `testAppStorageDate` | SHR-01 | Date round-trip (timeInterval accuracy) |
| `testAppStorageRawRepresentable` | SHR-01 | RawRepresentable enum (String-backed) |
| `testAppStorageOptionalNil` | SHR-01 | Optional Int: nil -> non-nil -> nil |
| `testAppStorageLargeData` | SHR-01 edge | 1 MB Data blob round-trip |
| `testAppStorageUnicodeString` | SHR-01 edge | Unicode/emoji string round-trip |
| `testAppStorageConcurrentAccess` | SHR-01 edge | Sequential mutations (10 increments) |
| `testFileStorageRoundTrip` | SHR-02 | Codable struct via fileStorage (temp file) |
| `testInMemorySharing` | SHR-03 | Two refs to same inMemory key see same value |
| `testInMemoryCrossFeature` | SHR-03 | Cross-feature inMemory sharing |
| `testSharedKeyDefaultValue` | SHR-04 | Default value returned for unset key |
| `testCustomSharedKeyCompiles` | SHR-14 | Custom key pattern compiles (inMemory proxy) |

## Issues Encountered

- None. All APIs matched expected signatures. The `@Shared` property wrapper's `$value.withLock { $0 = newValue }` pattern worked as documented.

## Final Results

- **Build**: Clean (warnings only from pre-existing dependency identity conflicts)
- **SharedPersistenceTests**: 17/17 passed, 0 failures
- **Full test suite**: All existing tests continue to pass (no regressions)
