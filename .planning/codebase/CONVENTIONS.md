# Coding Conventions

**Analysis Date:** 2026-02-20

## Naming Patterns

**Files:**
- Swift source files use PascalCase matching their primary type: `ContentView.swift`, `ViewModel.swift`, `FuseApp.swift`
- Test files use PascalCase with `Tests` suffix: `LiteAppTests.swift`, `FuseAppViewModelTests.swift`, `XCSkipTests.swift`
- Multiple views or types in single file are organized with type-per-section (e.g., `ContentView.swift` contains `ContentView`, `WelcomeView`, `ItemListView`, `ItemView`, `SettingsView`, `PlatformHeartView`)

**Functions:**
- Instance/static methods use camelCase: `makeViewModel()`, `testViewModelItemsObservation()`, `isUpdated(_:)`, `save(item:)`, `clear()`
- Test functions use `test` prefix in camelCase: `testLiteApp()`, `testDecodeType()`, `testViewModelClearObservation()`
- Observable tracking methods use `with` prefix: `withObservationTracking { } onChange: { }`

**Variables:**
- Properties use camelCase: `items`, `welcomeName`, `appearance`, `viewModel`, `heartBeating`
- State properties use `@State` or `@Observable` decorators
- App storage properties use `@AppStorage` with snake_case keys: `@AppStorage("tab")`, `@AppStorage("name")`
- Local variables in closures use camelCase: `offsets`, `fromOffsets`, `toOffset`, `modified`, `saved`

**Types:**
- Enums: PascalCase with raw values as lowercase: `enum ContentTab: String, Hashable { case welcome, home, settings }`
- Structs for SwiftUI Views: `struct ContentView: View`, `struct ItemListView: View`
- Classes for models/delegates: `class ViewModel`, `class FuseAppDelegate: Sendable`
- Test classes: `final class FuseAppViewModelTests: XCTestCase`

## Code Style

**Formatting:**
- 4-space indentation (Swift default)
- Opening braces on same line: `func testLiteApp() {`
- Closure syntax with trailing closure parameters: `.onChange { flag.value = true }`
- Long parameter lists wrapped with alignment

**Linting:**
- No detected SwiftLint or SwiftFormat configuration files
- Convention adherence follows Apple's official Swift style guide and Skip framework conventions

**License Headers:**
- All files include SPDX license header at top:
  - Primary code: `// Licensed under the GNU General Public License v3.0 or later` + `// SPDX-License-Identifier: GPL-3.0-or-later`
  - Library code: `// Licensed under the GNU General Public License v3.0 with Linking Exception` + `// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception`

## Import Organization

**Order:**
1. Framework imports (Foundation, SwiftUI, Observation, etc.)
2. Internal module imports (@testable imports for tests)
3. Skip-specific imports (SkipUI, SkipTest, SkipFuse, SkipBridge)

**Example from `LiteAppTests.swift`:**
```swift
import XCTest
import OSLog
import Foundation
@testable import LiteApp
```

**Example from `FuseAppViewModelTests.swift`:**
```swift
import XCTest
import Foundation
import Observation
@testable import FuseApp
```

**Path Aliases:**
- No path aliases detected; imports use full module names

## Error Handling

**Patterns:**
- Try-catch blocks wrap operations that can throw (file I/O, JSON decoding)
- Error objects logged using OSLog at appropriate levels: `.warning()`, `.error()`, `.info()`
- No error propagation up the stack; errors logged locally and safe defaults returned

**Example from `ViewModel.swift` (file loading):**
```swift
do {
    let start = Date.now
    let data = try Data(contentsOf: savePath)
    defer {
        let end = Date.now
        logger.info("loaded \(data.count) bytes from \(Self.savePath.path) in \(end.timeIntervalSince(start)) seconds")
    }
    return try JSONDecoder().decode([Item].self, from: data)
} catch {
    logger.warning("failed to load data from \(Self.savePath), using defaultItems: \(error)")
    let defaultItems = (1...365).map { Date(timeIntervalSinceNow: Double($0 * 60 * 60 * 24 * -1)) }
    return defaultItems.map({ Item(date: $0) })
}
```

## Logging

**Framework:** OSLog with Logger instance per module

**Patterns:**
- Logger initialized per file: `let logger: Logger = Logger(subsystem: "LiteApp", category: "Tests")`
- Test loggers use subsystem matching module: `Logger(subsystem: "LiteLibrary", category: "Tests")`
- Logging levels used appropriately:
  - `.debug()` — lifecycle events (e.g., `logger.debug("onInit")`, `logger.debug("onResume")`)
  - `.info()` — normal operations with performance metrics (e.g., `logger.info("loaded \(data.count) bytes in \(duration) seconds")`)
  - `.warning()` — recoverable errors (e.g., `logger.warning("failed to load data..., using defaultItems: \(error)")`)
  - `.error()` — unrecoverable errors (e.g., `logger.error("error saving data: \(error)")`)

**Example from `FuseApp.swift`:**
```swift
let logger: Logger = Logger(subsystem: "dev.jacobcx.fuseApp", category: "FuseApp")
```

## Comments

**When to Comment:**
- Large conceptual sections use doc comments with `///`
- Purpose and behavior of complex types documented above their definition
- Skip-specific directives documented (e.g., `/* SKIP @bridge */`)
- Implementation notes for platform-specific code

**Doc Comments (/// style):**
```swift
/// The Observable ViewModel used by the application.
@Observable public class ViewModel {
```

```swift
/// An individual item held by the ViewModel
struct Item : Identifiable, Hashable, Codable {
```

```swift
/// Utilities for defaulting and persising the items in the list
extension ViewModel {
```

**Inline Comments (// style):**
```swift
// perhaps the first launch, or the data could not be read
// needed to load the compiled bridge from the transpiled tests
// Mix in Compose code!
```

## Function Design

**Size:**
- Most functions 5-20 lines
- Larger functions break down logic into helper methods or extensions
- View bodies split across multiple views for reusability

**Parameters:**
- Using parameter labels for clarity: `func save(item: Item)`, `func isUpdated(_ item: Item) -> Bool`
- Underscore prefix for unnamed parameters: `func isUpdated(_ item: Item)`
- Default parameter values used where sensible: `init(id: UUID = UUID(), date: Date = .now, ...)`

**Return Values:**
- Functions return computed values or void
- SwiftUI views return `some View`
- Observable classes track state with `didSet` callbacks
- Test functions return `Void` with `throws` for error cases

**Example of well-designed function:**
```swift
func isUpdated(_ item: Item) -> Bool {
    item != items.first { i in
        i.id == item.id
    }
}
```

## Module Design

**Exports:**
- Classes/structs marked `public` for cross-module use in Skip apps
- Internal implementation details use `fileprivate` or file-local scope
- Observable classes and data models exported; views internal to module

**Example from `ViewModel.swift`:**
```swift
@Observable public class ViewModel {
    var items: [Item] = loadItems() { didSet { saveItems() } }
    // ...
}

struct Item : Identifiable, Hashable, Codable {
    // ...
}

extension ViewModel {
    private static let savePath = URL.applicationSupportDirectory.appendingPathComponent("appdata.json")
    fileprivate static func loadItems() -> [Item] { ... }
    fileprivate func saveItems() { ... }
}
```

**Barrel Files:**
- No barrel files (index exports) detected
- Each file exports its primary type

## SwiftUI-Specific Conventions

**Property Wrappers:**
- `@State` for local view state: `@State var heartBeating = false`
- `@Binding` for two-way data flow: `@Binding var welcomeName: String`
- `@AppStorage` for persisted user preferences: `@AppStorage("tab") var tab = ContentTab.welcome`
- `@Observable` for shared view models: `@Observable public class ViewModel`
- `@Environment` for dependency injection: `@Environment(ViewModel.self) var viewModel`

**View Body Structure:**
- Views composed with small, single-responsibility types
- Navigation using `NavigationStack` and `navigationDestination(for:)`
- Toolbar items placed in `.toolbar` blocks
- Animations explicit with `withAnimation { ... }`

## Skip Framework Conventions

**Bridge Markers:**
- Public API exposed via Skip using `/* SKIP @bridge */` marker: `/* SKIP @bridge */public struct FuseAppRootView`
- Indicates code can be transpiled to Kotlin/Android

**Conditional Compilation:**
- Platform-specific code using `#if SKIP`, `#if os(Android)`, `#if canImport(OSLog)`
- Example: `PlatformHeartView` renders blue heart on iOS, green on Android

**Package Structure:**
- Primary Swift UI code in `Sources/{ModuleName}/`
- Platform-specific entry points in `{Platform}/Sources/` (e.g., `Darwin/Sources/Main.swift`)
- Tests in `Tests/{ModuleName}Tests/`

---

*Convention analysis: 2026-02-20*
