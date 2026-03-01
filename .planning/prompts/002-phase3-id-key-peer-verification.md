# Phase 3: Verify `.id()` ↔ `key()` Cooperates with Peer Remembering

<objective>
Verify that SwiftUI's `.id()` modifier (which maps to Compose's `key()` in skip-ui) correctly invalidates remembered Swift peers when explicit view identity changes. This is Phase 3 of the Compose View Identity Gap fix — a verification task, not a code generation change.

When `.id()` changes on a view with peer remembering (Phase 1 or Phase 2), Compose's `key()` should reset all `remember`'d values inside its scope — including the `SwiftPeerHandle`. This means the old peer is released and a new peer is retained. This matches SwiftUI's behaviour of discarding and recreating a view when explicit identity changes.
</objective>

<context>
Read `CLAUDE.md` for project conventions and build commands.

Key files to investigate:
- `docs/skip/compose-view-identity-gap.md` — full documentation of the fix, including Phase 3 section
- `forks/skip-ui/Sources/SkipUI/SkipUI/View/AdditionalViewModifiers.swift` — `.id()` → `key()` mapping (around line 1412-1413)
- `forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift` — peer remembering generation (Evaluate override, SwiftPeerHandle)
- `forks/skipstone/Tests/SkipSyntaxTests/BridgeToKotlinTests.swift` — existing Phase 1 and Phase 2 transpiler tests

Design principles (from CLAUDE.md "Skipstone Transpiler Design Principles"):
- Lean on Compose primitives — `remember`, `remember(key)`, `RememberObserver`
- Peer remembering uses one pattern with one variable: the `remember` key (absent for Phase 1, `Swift_inputsHash` for Phase 2)
- `Swift_inputsHash` runs on the Swift side — both bridgable and unbridged params are accessible
</context>

<research>
Before writing any tests, investigate empirically. Phase 1 and 2 revealed that assumptions about transpiler internals are often incorrect.

1. **How does `.id()` map to `key()` in skip-ui?**
   - Read the `.id()` implementation in `AdditionalViewModifiers.swift`
   - Understand how `key()` wraps the composable content
   - Determine: does `key()` scope include the `Evaluate` override where `remember`/`remember(key)` lives?

2. **How does Compose's `key()` interact with `remember`?**
   - When `key()` changes, Compose resets all `remember`'d state in its scope
   - Verify: does this mean `SwiftPeerHandle.onForgotten()` is called (releasing the old peer)?
   - Verify: is a new `SwiftPeerHandle` created (retaining the new peer)?

3. **What happens at the transpiler level?**
   - When a view has both `.id()` and peer remembering, what does the generated Kotlin look like?
   - Is `.id()` applied outside the `Evaluate` override (at the call site), or inside it?
   - This determines whether `key()` scope encloses the `remember` call

4. **Edge cases to consider:**
   - View with Phase 1 remembering + `.id()` that changes
   - View with Phase 2 remembering + `.id()` that changes (inputs unchanged but id changed)
   - View with Phase 2 remembering + `.id()` that changes AND inputs that change simultaneously
   - `.id()` with non-Hashable values (if possible)
</research>

<requirements>
Based on research findings, do ONE of:

**If `.id()` ↔ `key()` already cooperates correctly (expected case):**
1. Write transpiler tests in `BridgeToKotlinTests.swift` that document the correct behaviour
2. Add a test for Phase 1 view + `.id()` modifier — verify generated Kotlin has `key()` wrapping that encloses the `remember` block
3. Add a test for Phase 2 view + `.id()` modifier — same verification
4. Update `docs/skip/compose-view-identity-gap.md` Phase 3 section to mark as VERIFIED with evidence

**If `.id()` ↔ `key()` does NOT cooperate correctly:**
1. Document the exact failure mode discovered
2. Propose a fix (likely in skip-ui's `.id()` implementation or in the transpiler's Evaluate generation)
3. Implement the fix
4. Write tests proving the fix works
5. Update documentation

In either case:
- Follow the research-first approach — read code before writing tests
- All changes must stay within `forks/skipstone` and `forks/skip-ui` (if needed)
- Run `swift test --filter BridgeToKotlinTests` to verify all tests pass
- Run `just ios-build fuse-app` to verify no iOS regression
</requirements>

<constraints>
- Do NOT modify the peer remembering logic (Phase 1/Phase 2) unless research reveals a genuine bug
- Do NOT add `.id()` to the fuse-app demo views — this is a transpiler-level verification, not an app-level feature
- If writing tests, follow the existing test patterns in `BridgeToKotlinTests.swift` (use `check(expectMessages:supportingSwift:swiftBridge:kotlins:)`)
- The test Swift source should use `#if canImport(SkipFuseUI)` and `import SkipFuseUI` pattern matching existing bridge tests
</constraints>

<verification>
Before declaring complete:
1. All `BridgeToKotlinTests` pass: `cd forks/skipstone && swift test --filter "SkipSyntaxTests.BridgeToKotlinTests"`
2. iOS build passes: `just ios-build fuse-app`
3. `docs/skip/compose-view-identity-gap.md` Phase 3 row updated in the implementation roadmap table
4. Clear written explanation of WHY `.id()` ↔ `key()` cooperates (or doesn't) with peer remembering, grounded in the actual generated Kotlin code
</verification>

<success_criteria>
- Research completed with empirical evidence (actual code read, not assumptions)
- `.id()` ↔ `key()` ↔ peer remembering interaction is understood and documented
- At least 2 new transpiler tests covering the interaction
- Phase 3 marked as VERIFIED or FIXED in the roadmap
- All existing tests still pass
</success_criteria>
