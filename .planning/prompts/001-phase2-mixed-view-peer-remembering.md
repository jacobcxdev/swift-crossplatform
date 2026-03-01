<objective>
Implement Phase 2 of the Compose View Identity Gap transpiler fix: input-change detection for "mixed views" — views that have BOTH constructor parameters (parent-provided) AND `let`-with-default properties.

Phase 1 (complete) handles the simple case: views with ONLY `let`-with-default properties and no constructor params. Phase 2 extends peer remembering to mixed views by detecting when parent-provided inputs change, so the remembered peer is invalidated (accepting fresh state) while `let`-with-default properties are still preserved across recompositions where inputs haven't changed.
</objective>

<context>
Read the project instructions first:
@CLAUDE.md

Then read the full design document — it contains the architecture, Phase 1 implementation details, and Phase 2 plan:
@docs/skip/compose-view-identity-gap.md

Key files to study:
- `forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift` — the transpiler visitor where Phase 1 lives (~lines 1588-1710)
- `forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinStatementTypes.swift` — `UnbridgedMember` enum (`letWithDefault`, `uninitializedStructProperty`)
- `forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinStructTransformer.swift` — struct transformation, `initializableVariableDeclarations`
- `forks/skipstone/Tests/SkipSyntaxTests/BridgeToKotlinTests.swift` — transpiler test expectations (Phase 1 tests at ~lines 9408, 9559)
- `forks/skipstone/Tests/SkipSyntaxTests/SwiftUITests.swift` — additional transpiler tests using `check(swift:, kotlin:)` pattern
</context>

<research_phase>
This task is research-heavy. Before writing any code, thoroughly investigate the following. Phase 1 taught us that assumptions about transpiler internals are often wrong — verify everything empirically.

**1. Identify constructor parameters at bridge stage**

The Phase 2 doc notes a key challenge: `initializableVariableDeclarations` is local to `KotlinStructTransformer` and not directly available in `KotlinBridgeToKotlinVisitor`. Research how to identify which properties are constructor parameters (parent-provided inputs) vs `let`-with-default (internal defaults) at the bridge visitor stage.

Approaches to investigate:
- Can constructor parameter names be derived from the **bridged constructor signatures** already generated at `KotlinBridgeToKotlinVisitor.swift:493-531`?
- Is there metadata on `KotlinClassDeclaration` that distinguishes constructor params from let-with-default?
- The `hasConstructorParams` logic (line ~1601) already identifies uninitialized struct properties — can this be extended to enumerate them by name?
- Could `KotlinStructTransformer` persist this metadata on `KotlinClassDeclaration.members` during transformation?

**2. Understand the `SwiftPeerHandle` pattern from Phase 1**

Phase 1 uses `SwiftPeerHandle` implementing `RememberObserver` for lifecycle-managed retain/release. Study this pattern deeply:
- How does `swapFrom` handle the retain/release accounting?
- What does `onAbandoned` vs `onForgotten` handle?
- Can `SwiftPeerHandle` be extended for Phase 2, or does the mixed-view case need a fundamentally different approach?

Phase 1 lesson: We originally used `DisposableEffect` (Option A) but switched to `RememberObserver` (Option B) because it handles `onAbandoned` (composition cancelled before commit) and bundles lifecycle into a single object. Apply this same elegance to Phase 2.

**3. Hash-based vs equality-based input change detection**

The doc proposes `Swift_inputsHash` using `Hasher`. Research alternatives:
- Hash collisions: `Hasher` is randomised per process — is `Int64` sufficient to avoid false negatives?
- Could we use per-property equality checks instead of hashing? (More JNI calls but no collision risk)
- Could we use a single `Swift_inputsChanged(oldPeer, newPeer) -> Bool` that compares constructor-param properties directly?
- What does Compose itself use for `key()` — hash or equality?

**4. Hashability constraints**

The doc notes constructor params must be `Hashable`. Research:
- What types commonly appear as View constructor params in Skip-bridged code? (Check fuse-app examples)
- Are `Binding<T>`, closures, or other non-Hashable types used as View constructor params?
- If a param isn't Hashable, should the transpiler: (a) emit a warning and skip peer remembering, (b) fall back to Phase 1 behaviour (always remember), or (c) exclude that property from the hash?

**5. Retain/release accounting for the mixed case**

Phase 1's accounting is clean because the remembered peer never changes. Phase 2 introduces peer replacement when inputs change. Trace through the retain/release lifecycle carefully:
- When inputs change: old remembered peer must be released, new peer retained
- When inputs haven't changed: stale recomposition peer released, remembered peer retained (same as Phase 1)
- GC finalizer thread race: Phase 1 solved this with `RememberObserver` — verify the mixed-case extension doesn't reintroduce it
- Draw a retain/release accounting table like the one in Section 6 of the doc

**6. Test infrastructure**

Study existing Phase 1 tests in `BridgeToKotlinTests.swift` to understand:
- The `check(swift:, kotlin:)` test pattern
- How multi-property views are tested
- Where to add Phase 2 test cases (mixed views with constructor params + let-with-default)

Write test cases FIRST (TDD) — define expected transpiler output before implementing.
</research_phase>

<requirements>
Based on research findings, implement Phase 2:

1. **Enumerate constructor parameter names** at bridge stage — determine which properties are parent-provided inputs vs internal defaults

2. **Generate `Swift_inputsHash` (or equivalent)** JNI function that hashes/compares only the constructor-provided property values on the Swift peer

3. **Extend `Evaluate` override** for mixed views with input-change detection:
   - Remember the peer (like Phase 1)
   - On each recomposition, check if inputs changed
   - If inputs changed → accept the new peer, release the old one
   - If inputs unchanged → restore the remembered peer (same as Phase 1)

4. **Retain/release correctness** — the `SwiftPeerHandle` or equivalent must handle:
   - `onForgotten` (composable leaves tree)
   - `onAbandoned` (composition cancelled before commit)
   - Input-change peer swaps (release old, retain new)
   - GC finalizer thread safety

5. **Transpiler tests** — add test cases for mixed views in `BridgeToKotlinTests.swift`:
   - View with one constructor param + one let-with-default
   - View with multiple constructor params + multiple let-with-defaults
   - View with constructor param that's a Binding
   - Edge case: view with only constructor params (no let-with-default) — should NOT get peer remembering

6. **Graceful degradation** — if a constructor param type isn't Hashable, the transpiler should handle this gracefully (emit warning, fall back, or skip)
</requirements>

<constraints>
- Do NOT modify Phase 1 behaviour — views with only `let`-with-default and no constructor params must continue using the existing `SwiftPeerHandle` pattern unchanged
- Follow the `canRememberPeer` guard pattern — introduce a new condition (e.g. `canRememberPeerWithInputCheck`) for mixed views
- All changes confined to `forks/skipstone/` — no changes to skip-ui, skip-android-bridge, or example apps
- Retain/release accounting must be provably correct — document the lifecycle trace
- The `SwiftPeerHandle` class is generated per-view as a nested private class — if extending it, keep it self-contained
- Gate behind the existing `hasLetWithDefault` condition — only views with `let`-with-default properties get any peer remembering
- Follow existing code patterns: `KotlinRawStatement`, `CDeclFunction`, `ClassType` dispatch on `.generic`/`.reference`/default
</constraints>

<implementation_guidance>
The doc's Phase 2 plan (Section 7, Steps 5-6) is a starting point but was written before Phase 1 was implemented. The actual Phase 1 implementation uses `SwiftPeerHandle` with `RememberObserver` — Phase 2 should build on this pattern, not the older `mutableStateOf`/`DisposableEffect` sketch in the doc.

Consider whether `SwiftPeerHandle` can be extended with an `inputsHash` field and an `updateIfInputsChanged(newPeer, newHash)` method, keeping the `RememberObserver` lifecycle management intact. This would be more elegant than the `mutableStateOf` approach in the doc.

The key insight from Phase 1: **body evaluation runs on the Swift side** via `Swift_composableBody(Swift_peer)`. The Kotlin `Evaluate` override is the only interception point before `super.Evaluate()` calls into Swift. All input-change detection must happen in this narrow window.
</implementation_guidance>

<verification>
Before declaring complete:
1. Run transpiler tests: `cd forks/skipstone && swift test --filter BridgeToKotlin`
2. Verify Phase 1 tests still pass (no regression)
3. New Phase 2 tests pass with expected Kotlin output
4. Build fuse-app for Android: `just android-build fuse-app` (verifies generated code compiles)
5. Retain/release accounting documented for all lifecycle paths
</verification>

<success_criteria>
- Mixed views (constructor params + let-with-default) get peer remembering with input-change detection
- Phase 1 behaviour unchanged for simple views (no constructor params)
- Views with only constructor params (no let-with-default) are unaffected
- All transpiler tests pass (old + new)
- fuse-app Android build succeeds
- Retain/release lifecycle is provably correct with no leaks or use-after-free
</success_criteria>
