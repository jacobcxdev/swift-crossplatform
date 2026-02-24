# Phase 3: TCA Core - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

<domain>
## Phase Boundary

TCA Store, reducers, effects, and dependency injection work correctly on Android. This is the runtime engine of TCA — no UI, no bindings, no navigation, no shared state persistence. Pure state management: actions go in, state comes out, effects execute async work.

**In scope:** Store init/send/scope (TCA-01..TCA-09), Effects (TCA-10..TCA-16), Dependencies (DEP-01..DEP-12), MainSerialExecutor porting for test determinism.

**Out of scope:** @ObservableState macro/bindings (Phase 4), @Shared state persistence (Phase 4), navigation/presentation (Phase 5), TestStore infrastructure (Phase 7 — but MainSerialExecutor is in scope here because effects need deterministic testing).

</domain>

<decisions>
## Implementation Decisions

### Effect Execution Model

- **Validate and fix JNI thread attachment for effect threads.** TCA effects commonly run on background threads via `Task {}` and `Effect.run`. These threads may not be JNI-attached on Android. Write tests that exercise effects on background threads. If JNI attachment fails, fix it in this phase — don't defer.
- **Write cancellation-specific tests.** Don't trust that Swift Concurrency cancellation "just works" on Android. Explicitly test `Effect.cancellable(id:)` and `Effect.cancel(id:)` — cancellation is critical for navigation teardown and debouncing in later phases.
- **Port MainSerialExecutor for test determinism.** TCA's TestStore uses a custom serial executor to make async effects deterministic. This is needed on Android for reliable test execution. Port it in this phase even though TestStore itself is Phase 7 — the executor is a prerequisite for any effect testing.
- **Validate `send` from both main and background threads.** `Effect.run` closures capture `send` to dispatch actions back to the store. Effects commonly send from background threads (network responses, timers). Validate that `send` works correctly from both main thread and background threads on Android.

### Dependency Context Detection

- **Preview context is fatal on Android.** SwiftUI Previews don't exist on Android. If code somehow enters preview context on Android (attempts to resolve `previewValue`), it should crash with a clear error message. This is an impossible state — make it loud.
- **Validate @TaskLocal propagation with tests.** `@TaskLocal` is the mechanism for propagating dependency overrides through async contexts. Write tests that verify `@TaskLocal` values propagate through `withDependencies` closures and into effects on Android. Don't assume it works just because Swift Concurrency works.
- **Test dependency inheritance 3+ levels deep.** Parent -> child (2 levels) is the minimum. Test grandparent -> parent -> child to catch propagation bugs that only surface with deep nesting. The `@Dependency` property wrapper resolves lazily — deep nesting exercises the full resolution chain.
- **Test dependency override isolation between siblings.** Explicitly test that overriding a dependency in one reducer scope doesn't leak to sibling scopes. Override leaking would be a critical correctness bug. This is distinct from the nesting test — siblings share a parent but should have independent override contexts.
- **Validate ALL built-in dependency keys.** Don't just test the ones our code happens to use. Validate every `DependencyKey` that ships with TCA and swift-dependencies (uuid, date, continuousClock, mainQueue, etc.) on Android. Comprehensive coverage prevents surprises in later phases when navigation or shared state needs a dependency we didn't validate.

### @DependencyClient Macro Behavior

- **Identical fatal error for unimplemented dependencies.** When an `unimplemented` dependency endpoint is called in a production (non-test) context on Android, it must fatal-error identically to iOS. Fail-fast prevents silent bugs. No softer failure mode for Android.
- **Validate behavior, not macro expansion.** Macros are compile-time and run on the macOS host. If the code compiles for Android, the macro worked. Phase 3 tests the runtime behavior of the generated code (that `unimplemented` fatals, that closures route correctly), not the macro expansion itself.
- **Match existing @_spi usage patterns.** TCA itself already uses `@_spi(Internals)` from swift-dependencies. Follow the same pattern for any Android-specific code paths. Don't be more restrictive than upstream. Document any SPI dependencies clearly in fork change notes.

### Fork Change Philosophy (inherited from Phase 2)

- **Inline `#if` guards only.** Use `#if os(Android)` or `#if canImport(Framework)` inline. No separate platform files. Minimizes fork divergence.
- **Same branch for all work.** All changes go on `dev/swift-crossplatform` branch per fork.

### Test Strategy

- **Both macOS and Android validation.** Tests must pass on macOS (no iOS regressions) AND compile+run on Android. The fuse-library example project is the test host.
- **Per-domain test targets.** Separate test targets for Store/Reducer tests, Effect tests, and Dependency tests in fuse-library. Better failure isolation.

</decisions>

<specifics>
## Specific Ideas

- TCA's `Store` uses `@MainActor` isolation. Verify this works correctly on Android — the main actor must map to the correct thread.
- `Effect.run` internally creates `Task` instances. The `Task` -> action routing goes through `Send`, which uses `@MainActor`. Test that background-thread sends correctly hop to main actor.
- `swift-dependencies` uses `@TaskLocal` for `DependencyValues._current`. This is the core propagation mechanism — if `@TaskLocal` doesn't work on Android, nothing in the dependency system works.
- TCA's `Scope` reducer uses `CaseKeyPath` from CasePaths (validated in Phase 2). Verify the integration point — scoped reducers depend on case path extraction working correctly.
- `Effect.cancellable` uses `withTaskCancellationHandler` internally. This is a Swift Concurrency primitive that should work on Android, but the combination with TCA's cancellation ID tracking (dictionary-based) needs validation.
- The `_printChanges()` reducer modifier uses CustomDump (validated in Phase 2) to diff state. Verify the integration point on Android.

</specifics>

<deferred>
## Deferred Ideas

- **Perception bypass on Android.** `PerceptionRegistrar` delegates to native `ObservationRegistrar`, bypassing bridge `recordAccess` hooks. Raw `@Perceptible` views (without TCA) won't trigger Compose updates. Safe for TCA (uses bridge registrar directly). Verify no non-TCA code relies on Perception for view driving. (Carried from Phase 2 pending todos.)
- **Android-native dependency implementations.** Some built-in dependencies (e.g., `openURL`) may need Android-native implementations via JNI. Phase 3 validates they resolve without crashing; Phase 5+ provides real implementations if needed.
- **Effect performance profiling.** Stress-testing effect throughput (>1000 mutations/second) is Phase 7 (TEST-11). Phase 3 validates correctness only.
- **TestStore infrastructure.** TestStore init, send/receive assertions, exhaustivity — all Phase 7. Phase 3 only ports the MainSerialExecutor that TestStore depends on.

</deferred>

---

*Phase: 03-tca-core*
*Context gathered: 2026-02-22*
