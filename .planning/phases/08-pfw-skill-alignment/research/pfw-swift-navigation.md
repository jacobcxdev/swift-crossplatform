# SwiftNavigation Canonical Patterns & Phase 8 Alignment

**Generated:** 2026-02-23
**Phase:** 8 (PFW Skill Alignment)
**Skills Audited:** pfw-swift-navigation (1 HIGH, 3 MEDIUM findings)
**Scope:** Canonical patterns for @Dependency(\.dismiss), @Presents optional state, NavigationStack path binding, and Android implementation gaps.

---

## Canonical Patterns

### 1. @Dependency(\.dismiss) — Child Dismissal Pattern

**Canonical Usage:**

```swift
@Reducer
struct ChildFeature {
    @ObservableState
    struct State: Equatable {
        var data: String
    }

    enum Action {
        case closeButtonTapped
    }

    @Dependency(\.dismiss) var dismiss  // ← REQUIRED: always inject

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .closeButtonTapped:
                return .run { _ in await self.dismiss() }  // ← CANONICAL: async effect
            }
        }
    }
}
```

**Key Points:**
- `@Dependency(\.dismiss)` is injected in child reducers (not parent).
- Must be used in an async context via `.run { _ in await self.dismiss() }`.
- **NEVER** set parent state to nil directly in the child reducer.
- PresentationReducer automatically handles cancellation of child effects when dismissed.

**Why Not State Mutation:**
- Direct `parent.child = nil` bypasses PresentationReducer's effect lifecycle management.
- Cancellation token propagation fails, causing orphaned effects.
- Violates TCA unidirectional data flow (child should not mutate parent state).

---

### 2. @Presents Optional State — Sheet / Dialog Pattern

**Canonical Usage:**

```swift
@Reducer
struct ParentFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var sheet: SheetContent.State?  // ← CANONICAL: optional @Presents
        @Presents var dialog: DialogContent.State?
    }

    enum Action {
        case sheet(PresentationAction<SheetContent.Action>)
        case dialog(PresentationAction<DialogContent.Action>)
        case openSheet
        case openDialog
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .openSheet:
                state.sheet = SheetContent.State()  // ← Set state, not boolean
                return .none
            case .openDialog:
                state.dialog = DialogContent.State()
                return .none
            case .sheet, .dialog:
                return .none
            }
        }
        .ifLet(\.$sheet, action: \.sheet) {
            SheetContent()
        }
        .ifLet(\.$dialog, action: \.dialog) {
            DialogContent()
        }
    }
}
```

**Key Points:**
- `@Presents var optional: State?` automatically produces a key-path opening for `.ifLet()`.
- Dismissal is automatic: PresentationAction includes `.dismiss` case.
- **DO NOT** use boolean `showSheet` flags — use optional state directly.
- Multiple @Presents fields can coexist (sheets, dialogs, alerts, popover, etc.).

**Why Not Boolean State:**
- Boolean toggles lose state persistence (sheet content data is lost on close/reopen).
- PresentationReducer cannot manage child effects or lifecycle without optional state.
- No state symmetry: opening != closing, so boolean is asymmetric.

---

### 3. NavigationStack Path Binding — View-to-Reducer Sync

**Canonical Usage (iOS only):**

```swift
@Reducer
struct ContactsFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()  // ← CANONICAL: StackState generic
        @Presents var destination: Destination.State?
    }

    enum Action {
        case path(StackActionOf<Path>)       // ← CANONICAL: StackActionOf
        case destination(PresentationAction<Destination.Action>)
        case contactTapped(Contact)
    }

    @Reducer
    enum Path {
        case detail(ContactDetailFeature)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .contactTapped(contact):
                state.path.append(.detail(ContactDetailFeature.State(contact: contact)))
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)  // ← CANONICAL: forEach for stack
    }
}

// In View:
struct ContactsView: View {
    @Bindable var store: StoreOf<ContactsFeature>

    var body: some View {
        // ← CANONICAL iOS pattern:
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List { ... }
        } destination: { store in
            switch store.case {
            case let .detail(detailStore):
                ContactDetailView(store: detailStore)
            }
        }
    }
}
```

**Key Points:**
- `StackState<Path.State>` is the reducer-level state container.
- `StackActionOf<Path>` is the reducer-level action wrapper.
- `.forEach(\.path, action: \.path)` applies reducers to stack elements.
- View binding: `$store.scope(state: \.path, action: \.path)` creates a `Binding<Store<...>>`.
- NavigationStack consumes the path binding and destination closure.
- **iOS ONLY:** Android has no NavigationStack.

---

### 4. Dismiss Action Pattern — Manual Pop Without Dependency

**When to use:** Parent receives signal from child (via delegate) and pops stack.

**Canonical Usage:**

```swift
@Reducer
struct ParentFeature {
    enum Action {
        case path(StackActionOf<Path>)
        case childDelegated(ChildAction)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .path(.element(let id, .detail(.delegate(.deleteRequest)))):
                // ← CANONICAL: Pop using StackAction.popFrom(id:)
                state.path.remove(id: id)
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
```

**Key Points:**
- Use `state.path.remove(id:)` to remove a specific stack element.
- **NEVER** use `state.path.popLast()` — it doesn't integrate with TCA's action system.
- Route via `.path(.element(...))` to intercept child delegate actions.

---

## Current State

### H13: Manual `state.path.popLast()` Bypasses Stack Action Mechanism

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/ContactsFeature.swift:48`

**Violation:**
```swift
case .path(.element(_, .detail(.delegate(.deleteContact(let id))))):
    state.contacts.remove(id: id)
    _ = state.path.popLast()  // ← WRONG: mutates internal stack directly
    return .none
```

**Problem:**
- `popLast()` is a direct mutation that bypasses the TCA reducer pipeline.
- Does not generate a StackAction for observers.
- Inconsistent with canonical `.remove(id:)` pattern used elsewhere in tests.

**Current Test Coverage:**
- `NavigationStackTests.swift:88-90` shows correct `.popFrom(id:)` pattern.
- `NavigationStackTests.swift:164-165` shows correct `.path(.popFrom(...))` pattern.
- `ContactsFeature.swift` demonstrates anti-pattern via direct `popLast()` call.

---

### M11: Boolean Sheet State Instead of Optional State

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-library/Tests/NavigationTests/UIPatternTests.swift:115`

**Violation:**
```swift
@Reducer
struct SheetToggleFeature {
    @ObservableState
    struct State: Equatable {
        var showSheet = false  // ← WRONG: boolean flag
        var sheetCount = 0
    }

    enum Action {
        case toggleSheet
        case incrementInSheet
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleSheet:
                state.showSheet.toggle()  // ← Toggle pattern is anti-pattern
                return .none
            case .incrementInSheet:
                state.sheetCount += 1
                return .none
            }
        }
    }
}
```

**Problem:**
- Boolean toggle pattern loses sheet content state on dismiss.
- PresentationReducer cannot manage effect lifecycle.
- Test validates wrong pattern, misleading developers.

**Current Test Coverage:**
- `UIPatternTests.swift:245-255` tests boolean toggle (validates wrong pattern).
- No test demonstrates canonical `@Presents var sheet: Content.State?` pattern.
- `NavigationTests.swift:248-282` shows correct @Presents pattern but in different test suite.

---

### M12: Manual `destination = nil` Skips PresentationReducer Effect Cancellation

**Files:**
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/ContactsFeature.swift:56`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/ContactsFeature.swift:165`

**Violation:**
```swift
case .destination(.presented(.addContact(.delegate(.saveContact(let contact))))):
    state.contacts.append(contact)
    state.destination = nil  // ← WRONG: direct mutation
    return .none

case .destination(.presented(.editSheet(.delegate(.save(let contact))))):
    state.contact = contact
    state.destination = nil  // ← WRONG: direct mutation
    return .none
```

**Problem:**
- Setting `destination = nil` directly bypasses PresentationReducer's dismissal pipeline.
- Child effects (via `@Dependency(\.dismiss)`) are not cancelled properly.
- PresentationAction includes automatic `.dismiss` case for this purpose.

**Correct Pattern:**
- Return `.send(.destination(.dismiss))` to trigger PresentationReducer's effect cancellation.
- Or rely on child to call `@Dependency(\.dismiss)` (handles parent nilling automatically).
- Only manually set to nil if child has no effects (documented constraint).

**Current Test Coverage:**
- `NavigationTests.swift:257-260` shows correct `.dismiss` action pattern.
- `NavigationTests.swift:268-271` demonstrates auto-dismissal via PresentationAction.
- `ContactsFeature.swift` uses manual `= nil` pattern (violates rule).

---

### M13: Android Path Omits NavigationStack(path:) — StackState Silently Unused

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/ContactsFeature.swift:268-278`

**Violation:**
```swift
#if os(Android)
NavigationStack {
    contactsList
}
.sheet(...)
#else
NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
    contactsList
} destination: { store in
    switch store.case {
    case let .detail(detailStore):
        ContactDetailView(store: detailStore)
    }
}
.sheet(...)
#endif
```

**Problem:**
- Android: `NavigationStack` created without path binding.
- `state.path` (StackState) is defined but never used.
- All path actions (push/pop/detail mutations) are silently ignored.
- Contact detail navigation works only on iOS; Android has no drill-down.

**Why This Matters:**
- Asymmetric behavior: iOS supports full stack navigation; Android truncated to flat list.
- Path state pollution: reducer maintains StackState that view never consumes.
- Testing gap: StackState mutations (NavigationStackTests) don't affect Android rendering.

**Android Alternatives:**
1. **Option A (Recommended):** Implement platform-native navigation (Jetpack Navigation Compose).
   - Bind StackState to Compose navigation state machine.
   - Use `path` reducer actions to drive Compose NavController.

2. **Option B:** Remove StackState for Android, use sheet-only pattern.
   - Define `#if os(Android)` variant of State without path.
   - Reduces reducer complexity; sacrifices deep linking.

3. **Option C:** Sheet-based drill-down (current approach, undocumented).
   - Use only sheets/modals for nested views.
   - Incompatible with platform conventions.

---

## Required Changes

### PHASE 8 ACTION ITEMS

#### 1. Fix H13: Replace `popLast()` with `remove(id:)` (CRITICAL)

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/ContactsFeature.swift:48`

**Change:**
```swift
// BEFORE:
case .path(.element(_, .detail(.delegate(.deleteContact(let id))))):
    state.contacts.remove(id: id)
    _ = state.path.popLast()
    return .none

// AFTER:
case .path(.element(let stackID, .detail(.delegate(.deleteContact(let id))))):
    state.contacts.remove(id: id)
    state.path.remove(id: stackID)  // ← Use StackState API
    return .none
```

**Rationale:**
- `remove(id:)` is StackState's canonical mutation API.
- Generates StackAction internally for proper observer notification.
- Maintains TCA unidirectional data flow.

---

#### 2. Fix M11: Migrate SheetToggleFeature to @Presents Pattern (CRITICAL)

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-library/Tests/NavigationTests/UIPatternTests.swift:112-134`

**Change:**
```swift
// BEFORE:
@Reducer
struct SheetToggleFeature {
    @ObservableState
    struct State: Equatable {
        var showSheet = false
        var sheetCount = 0
    }

    enum Action {
        case toggleSheet
        case incrementInSheet
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleSheet:
                state.showSheet.toggle()
                return .none
            case .incrementInSheet:
                state.sheetCount += 1
                return .none
            }
        }
    }
}

// AFTER:
@Reducer
struct SheetToggleFeature {
    @Reducer
    enum Destination {
        case sheet(SheetContent)
    }

    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?
        var sheetCount = 0
    }

    enum Action {
        case destination(PresentationAction<Destination.Action>)
        case toggleSheet
        case incrementInSheet
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleSheet:
                if state.destination == nil {
                    state.destination = .sheet(SheetContent.State())
                } else {
                    state.destination = nil
                }
                return .none
            case .incrementInSheet:
                state.sheetCount += 1
                return .none
            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

@Reducer
struct SheetContent {
    @ObservableState
    struct State: Equatable {}
    enum Action {}
    var body: some ReducerOf<Self> { Reduce { _, _ in .none } }
}
```

**Rationale:**
- Demonstrates canonical `@Presents` pattern for tests to follow.
- Enables proper sheet content state management.
- PresentationReducer handles dismissal lifecycle.

---

#### 3. Fix M12: Replace Manual `destination = nil` with Delegate Pattern (HIGH)

**Files:**
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/ContactsFeature.swift:56`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/ContactsFeature.swift:165`

**Change Strategy:**
Implement delegate action pattern so child can trigger dismissal via @Dependency(\.dismiss):

```swift
// In child (EditContactFeature):
case .saveButtonTapped:
    return .send(.delegate(.save(state.contact)))  // ← Send delegate action

case .delegate:
    return .none

// In parent (ContactDetailFeature) body:
case .destination(.presented(.editSheet(.delegate(.save(let contact))))):
    state.contact = contact
    return .send(.destination(.dismiss))  // ← Use PresentationAction.dismiss, not nil
```

**Rationale:**
- `.destination(.dismiss)` triggers PresentationReducer's effect cancellation.
- Child receives cancellation signal automatically.
- Symmetric with child's ability to call `await dismiss()`.

**Alternative (If Child Has No Effects):**
If EditContactFeature has zero async effects (pure state mutation):
```swift
// Document the constraint:
/// EditContactFeature has no async effects; manual dismissal is side-effect-free.
case .destination(.presented(.editSheet(.delegate(.save(let contact))))):
    state.contact = contact
    state.destination = nil  // ← Document: no child effects to cancel
    return .none
```

---

#### 4. Fix M13: Implement Android NavigationStack Path Binding (COMPLEX)

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/ContactsFeature.swift:268-278`

**Option A (Recommended): Compose Navigation Integration**

Replace Android conditional with proper navigation binding:

```swift
#if os(Android)
// Use Skip's Compose navigation bridge (requires skip-navigation extension)
ComposeNavigationStack(
    path: $store.scope(state: \.path, action: \.path),
    root: {
        contactsList
    },
    destination: { store in
        switch store.case {
        case let .detail(detailStore):
            ContactDetailView(store: detailStore)
        }
    }
)
.sheet(...)

#else
NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
    contactsList
} destination: { store in
    switch store.case {
    case let .detail(detailStore):
        ContactDetailView(store: detailStore)
    }
}
.sheet(...)
#endif
```

**Option B (Interim): Accept Asymmetry, Document It**

If Compose navigation is unavailable:
```swift
#if os(Android)
// KNOWN LIMITATION: Android uses sheet-only navigation.
// Stack state is maintained for iOS compatibility but not consumed on Android.
// TODO: Implement Jetpack Navigation Compose binding in Phase 9.
NavigationStack {
    contactsList
}
.sheet(...)

#else
NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
    contactsList
} destination: { store in
    switch store.case {
    case let .detail(detailStore):
        ContactDetailView(store: detailStore)
    }
}
.sheet(...)
#endif
```

**Rationale:**
- Option A: Proper cross-platform parity; requires Compose navigation skill.
- Option B: Documents asymmetry; unblocks other fixes; defers implementation.

---

## Android NavigationStack Gap — M13 Deep Dive

### Architecture Problem

**On iOS:**
```
ContactsFeature.State {
  path: StackState<Path.State>  // ← Consumed by NavigationStack(path:)
  @Presents destination        // ← Consumed by .sheet()
}
```
- NavigationStack reads path, renders destination closure for each element.
- Actions route via `.path(.element(...))` into child reducers.

**On Android (Current):**
```
ContactsFeature.State {
  path: StackState<Path.State>  // ← UNUSED, dead code
  @Presents destination        // ← Consumed by .sheet()
}
```
- NavigationStack() created without path binding.
- path StackState exists but is never read by view layer.
- Reducer sends `.path(.element(...))` actions that are consumed by `.forEach()` but never render anything.

### Why Not Simple Fix

**Naive Approach (Won't Work):**
```swift
#if os(Android)
NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
    contactsList
} destination: { store in
    switch store.case { ... }
}
#endif
```

**Problem:**
- SwiftUI `NavigationStack` uses iOS semantics (backstack, animation, transitions).
- Skip's Android codegen does not support full NavigationStack lifecycle on Android.
- Will compile but render incorrectly or crash at runtime.

### Solution Architecture (Phase 9+)

**Phase 8 Action:** Document the gap and defer implementation.

**Phase 9+ Path:**
1. Create `skip-navigation` fork bridging Jetpack Navigation to SwiftUI.
2. Define `ComposeNavigationStack` modifier with path binding.
3. Update ContactsFeature to use platform-conditional wrapper.
4. Add NavigationStack tests for Android (requires skip test framework).

### Current Interim State

**Acceptable M13 Resolution for Phase 8:**
- Document in ContactsFeature that Android uses sheet-only pattern.
- Leave StackState defined (no code duplication).
- Reducer processes path actions (they're no-ops on Android rendering layer).
- Add TODO comment with Phase 9 reference.

**Test Coverage Implications:**
- NavigationStackTests pass on iOS, are skipped/no-op on Android.
- ContactDetailFeature navigation works only on iOS.
- Feature is still functionally complete (users can add contacts and view info).

---

## Ordering Dependencies

### Execution Order for Phase 8

**Wave 1 (Blocking):**
1. **H13 Fix** (popLast → remove): 1 file change, ~5 lines. No dependencies.
2. **M11 Fix** (SheetToggleFeature): 1 test file, ~40 lines. Tests only, no app impact.

**Wave 2 (High):**
3. **M12 Fix** (Manual nil → .dismiss): 2 file changes, ~10 lines total. Depends on Wave 1 completion (same feature, related pattern).

**Wave 3 (Complex, Deferrable):**
4. **M13 Fix** (Android path binding): Requires skip-navigation fork + Compose bridge. Defer to Phase 9 with interim documentation.

### Dependency Graph

```
H13 (popLast)
  └─ No dependencies

M11 (SheetToggleFeature)
  └─ No dependencies (test-only)

M12 (Manual nil)
  └─ Depends on H13 being understood (both are ContactsFeature patterns)
  └─ Not blocked by H13 fix, but good to do both together

M13 (Android NavigationStack)
  └─ Blocked by skip-navigation fork readiness
  └─ Not needed for Phase 8 completion
  └─ Defer with documented TODO
```

### Testing Strategy

**After H13, M11, M12 fixes:**
```bash
make test-filter FILTER=NavigationTests          # Verify StackState mutations
make test-filter FILTER=NavigationStackTests     # Verify path binding
make test-filter FILTER=UIPatternTests           # Verify @Presents pattern
make skip-test                                   # Verify cross-platform parity
```

**M13 Testing (Phase 9+):**
- Add Android-specific navigation tests when skip-navigation is ready.
- Test through Android emulator with logcat tracking.

---

## Key Canonical Rules Summary

| Pattern | DO | DON'T |
|---------|----|----|
| **Stack Pop** | Use `state.path.remove(id:)` | Use `state.path.popLast()` or `_ = state.path.popLast()` |
| **Sheet/Dialog** | Use `@Presents var state: Content.State?` | Use `var showSheet: Bool` toggle |
| **Dismissal** | Return `.send(.destination(.dismiss))` or use `@Dependency(\.dismiss)` | Set state to nil manually |
| **Child Close** | Child calls `await dismiss()`; parent handles via delegate | Child manipulates parent state directly |
| **Path Binding** | Bind `$store.scope(state: \.path, action: \.path)` to NavigationStack | Use binding directly or platform-specific nav |

---

## References

- **pfw-swift-navigation** Skill: SwiftNavigation canonical APIs and patterns.
- **NavigationTests.swift**: Reference test suite demonstrating all canonical patterns.
- **ContactsFeature.swift**: Current app implementation (contains violations and gaps).
- **PFW-AUDIT-RESULTS.md**: Full audit findings (findings H13, M11, M12, M13).
- **ROADMAP.md**: Phase 8 deliverables and success criteria.

