<objective>
Investigate and fix the root cause of Section 7's `LocalPeerStoreItemKey` never being propagated to child views.

The PeerSurvivalSetting tab attempts to provide a `LocalPeerStoreItemKey` to its children via `CompositionLocalProvider` inside a `#if SKIP` block. Despite two implementation attempts, `rememberViewPeer` always receives `itemKey=null`, causing views to fall back to composition-scoped `remember` instead of the PeerStore path — so counter values do not survive tab switches.

This issue has persisted through five rounds of UAT. Two attempted fixes used the same `#if SKIP` + `SKIP INSERT` approach inside the bridged view's `body`, and both produced identical null results. The root cause is NOT yet identified with certainty. Do not accept any hypothesis without verifiable evidence.
</objective>

<collaboration_protocol>
This investigation is a Claude + Codex pair-programming session. The workflow is:

1. **Claude performs independent research** using subagents (Explore, Read, Grep, etc.) to investigate the issue. Claude documents findings with evidence (file paths, line numbers, log excerpts, transpiled Kotlin).

2. **Claude sends findings to Codex** via the `codex-cli` MCP tool (`mcp__codex-cli__codex`), asking Codex to perform its own independent investigation of the same codebase. Codex receives context files and the issue description but NOT Claude's conclusions — Codex must form its own.

3. **Claude shares its research with Codex** via `mcp__codex-cli__codex-reply`, providing Claude's independent findings. Codex compares both investigations.

4. **Iterate**: If findings agree, proceed to fix design. If they disagree, both sides must provide evidence to support their position. Neither side dismisses the other without thorough justification. Neither side accepts the other's conclusions without verification.

5. **Implementation**: Claude implements fixes. After each change, Claude asks Codex to review the diff and verify correctness before proceeding.

6. **Verification**: Build, deploy to Android emulator, run scenario, capture logs, verify the fix. Share verification logs with Codex for independent confirmation.

Rules:
- Be vigilant and challenge everything. No rubber-stamping.
- Thoroughness, thought, reasoning, carefulness, and planning over speed.
- Do not fall for false root causes: identify what is ACTUALLY wrong.
- No sticking plasters, no workarounds. Find and fix the real bug.
- Continue working together throughout — do not diverge into independent paths.
- Always ask Codex to look over your shoulder during implementation.
</collaboration_protocol>

<context>
Read these files for full background:
- `docs/identity-issues-r5.md` — comprehensive issue documentation with symptoms, logs, code, and prior attempts
- `examples/fuse-app/HARNESS.md` — test harness extension guide with architecture, scenarios, and oracle patterns
- `forks/skip-ui/Sources/SkipUI/SkipUI/Compose/PeerStore.swift` — PeerStore, PeerCacheKey, `rememberViewPeer`, `LocalPeerStoreItemKey`
- `examples/fuse-app/.build/plugins/outputs/skip-ui/SkipUI/destination/skipstone/SkipUI/src/main/kotlin/skip/ui/PeerStore.kt` — transpiled PeerStore Kotlin
- `CLAUDE.md` — project architecture and conventions

Test harness source files (PeerSurvival setting exercises this issue):
- `examples/fuse-app/Sources/FuseApp/PeerSurvivalSetting.swift` — reducer + view: PeerRememberTestView and CounterCard with `#if SKIP` CompositionLocalProvider blocks
- `examples/fuse-app/Sources/FuseApp/IdentityComponents.swift` — shared: `idLog()`, `CardItem`, `CounterCard`, `PeerRememberTestView`
- `examples/fuse-app/Sources/FuseApp/ScenarioEngine.swift` — scenario primitives, runner, and registry (includes `peer-survival-tab-switch`)
- `examples/fuse-app/Sources/FuseApp/TestHarnessFeature.swift` — root TCA reducer: tab state, UICommand forwarding, child composition
- `examples/fuse-app/Sources/FuseApp/ControlPanelView.swift` — control panel: scenario runner UI
- `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` — TCA integration tests (20 tests across 4 suites)

Transpiled Kotlin (rebuild to regenerate after changes):
- `examples/fuse-app/.build/plugins/outputs/fuse-app/FuseApp/destination/skipstone/FuseApp/src/main/kotlin/fuse/app/PeerSurvivalSetting.kt` — transpiled PeerSurvivalSettingView Kotlin

Log files from UAT Round 5 reproductions:
- `/tmp/r5-tab-switch-logs.txt` — tab switch showing `itemKey=null` for PeerSurvival views
</context>

<test_harness>
The fuse-app uses a test harness architecture for exercising identity bugs. Key concepts:

**Settings** are tab-based TCA reducer+view pairs. PeerSurvivalSetting exercises this issue with:
- Section 1: `PeerRememberTestView` — @State + let-with-default (no constructor params), tap count should survive tab switch
- Section 2: `CounterCard` (mixed view) — constructor params + let-with-default, counter state should survive tab switch
- Both wrapped in `#if SKIP` blocks with `CompositionLocalProvider(providedPeerItemKey)` to set `LocalPeerStoreItemKey`

**Scenarios** are automated step sequences run from the Control Panel tab. Available PeerSurvival scenario:
- `peer-survival-tab-switch` — navigate to Peer tab, switch to ForEach tab and back, verify peer survival

**Scenario runner**: Scenarios are defined in `ScenarioEngine.swift` and run from `ControlPanelView`. They use `PRE_`/`POST_` checkpoint brackets around mutations for log-based oracle analysis.

Auto-run on launch: set `LaunchConfig.autoRunScenario` in `ScenarioEngine.swift` to a scenario ID (e.g. `"peer-survival-tab-switch"`).
</test_harness>

<issue_summary>
`PeerSurvivalSettingView` is a bridged view (`SwiftPeerBridged`). Its `body()` is evaluated on the Swift side via JNI (`Swift_composableBody(Swift_peer)`).

The view attempts to set `LocalPeerStoreItemKey` using a `#if SKIP` block containing `SKIP INSERT` + `CompositionLocalProvider`. However:

1. On the Swift side, `#if SKIP` evaluates to **false** — the entire block is dead code.
2. On the Kotlin side, the transpiled `body()` calls through JNI to the Swift side — so the `#if SKIP` content is never reached either.
3. Grepping the transpiled Kotlin for `LocalPeerStoreItemKey`, `providedPeerItemKey`, `peerRememberItemKey`, and `CompositionLocalProvider` returns **zero matches** in the transpiled view output.

Evidence from logs:
```
[rememberViewPeer] store=true itemKey=null itemKeyType=nil namespace=1 slotKey=PeerSurvivalSettingView
[rememberViewPeer] store=true itemKey=null itemKeyType=nil namespace=1 slotKey=PeerRememberTestView
[rememberViewPeer] store=true itemKey=null itemKeyType=nil namespace=1 slotKey=CounterCard
```

`store=true` confirms a PeerStore exists (from TabView), but `itemKey=null` means `rememberViewPeer` falls through to the `remember`-based fallback path.

The transpiled Kotlin for `PeerSurvivalSettingView._ComposeContent`:
```kotlin
override fun _ComposeContent(context: skip.ui.ComposeContext) {
    val currentHash = Swift_inputsHash(Swift_peer)
    Swift_peer = skip.ui.rememberViewPeer(slotKey = "PeerSurvivalSettingView", ...)
    skip.ui.ViewObservation.startRecording?.invoke()
    skip.model.StateTracking.pushBody()
    val renderables = body().Evaluate(context = context, options = 0)
    // ...
}
```

Where `body()` calls through JNI:
```kotlin
override fun body(): skip.ui.View {
    return skip.ui.ComposeBuilder { composectx ->
        Swift_composableBody(Swift_peer)?.Compose(composectx) ?: skip.ui.ComposeResult.ok
    }
}
```
</issue_summary>

<what_has_been_tried>
| Plan | What was done | Result |
|------|--------------|--------|
| Plan 14 | Raw Kotlin string literals in `SKIP INSERT` inside `#if SKIP` body block | `itemKey=null` — code is dead (never reached) |
| Plan 17 | Swift-typed `let` variables before `SKIP INSERT` inside `#if SKIP` body block | `itemKey=null` — same dead code path |

Both approaches modified code inside the same `#if SKIP` block within the view's `body`. The fundamental problem is that bridged views evaluate their body on the Swift side via JNI, where `#if SKIP` is false.
</what_has_been_tried>

<research_phase>
Use subagents to prevent context bloat. Spawn `Explore` or `general-purpose` agents for each research task.

Research areas (non-exhaustive — follow the evidence):

1. **Understand the bridged view rendering pipeline**: How does a `SwiftPeerBridged` view's body get rendered? Trace from `_ComposeContent` → `body()` → JNI → Swift → back to Kotlin composition. At what point can Compose CompositionLocals be provided?

2. **Understand `#if SKIP` vs `#if SKIP_BRIDGE` semantics**: Which conditional is true where? `#if SKIP` is true in transpiled Kotlin only. `#if SKIP_BRIDGE` is true in Swift bridge code. Neither is true inside a bridged view's `body()` on the Swift side. What other mechanisms exist?

3. **Find how other CompositionLocals are provided in bridged views**: Search the codebase for any bridged view that successfully provides a `CompositionLocal` to its children. How do they do it? Are there any at all?

4. **Understand the `_ComposeContent` override point**: Could `LocalPeerStoreItemKey` be provided from `_ComposeContent` rather than from `body()`? What's the difference in composition scope?

5. **Examine how ForEach provides its item key**: ForEach successfully provides `LocalPeerStoreItemKey` for its items. How does it do it? Is it through a modifier, through `_ComposeContent`, or through another mechanism? Can PeerSurvivalSetting use the same approach?

6. **Explore alternative approaches**: Could the item key be set via a view modifier (like `PeerStoreNamespaceModifier`)? Could it be set from the Kotlin side of the bridged view (in `_ComposeContent`) rather than from the Swift body?

Do NOT limit yourself to these areas. Follow the evidence wherever it leads.
</research_phase>

<build_and_test>
Use justfile recipes from the project root. The test harness provides automated scenarios for verification.

```bash
# Build for iOS (quick syntax check)
just ios-build fuse-app

# Run TCA integration tests (20 tests across 4 suites)
just ios-test fuse-app

# Clean + build + install + launch on Android emulator + stream logcat
just android-run fuse-app

# Or individual steps:
just clean fuse-app              # clean build artifacts
just android-build fuse-app      # build Android APK (uses local skipstone)
just android-run fuse-app        # build + install + launch + logcat

# Set auto-run scenario for hands-free verification:
# In ScenarioEngine.swift, set LaunchConfig.autoRunScenario = "peer-survival-tab-switch"

# Capture identity logs (after scenario run)
adb logcat -c                    # clear buffer BEFORE running scenario
# ... run scenario ...
adb logcat -d -s fuse.app/Identity:D ComposeIdentity:D > /tmp/identity-logs.txt

# Key log patterns to check:
# - itemKey= values (should NOT be null for PeerSurvival views)
# - store=true itemKey=<value> (should show PeerStore path, not fallback)
# - HIT vs MISS (should be HIT on revisit after tab switch)
# - slotKey=PeerRememberTestView and slotKey=CounterCard entries
```

Android builds take ~5 minutes. Use `run_in_background` for the build/export step.
</build_and_test>

<implementation_protocol>
When implementing fixes:

1. Make the change in Swift source (e.g., `PeerSurvivalSetting.swift`, `PeerStore.swift`, or skip-ui framework files)
2. Verify iOS build: `just ios-build fuse-app`
3. Run TCA tests: `just ios-test fuse-app` (all 20 must pass)
4. Ask Codex to review the diff before proceeding to Android build
5. Set `LaunchConfig.autoRunScenario = "peer-survival-tab-switch"` for verification
6. Build and deploy to Android: `just android-run fuse-app`
7. Capture and analyse logs
8. Share logs with Codex for independent verification
9. If fix doesn't work, return to research — do NOT stack another guess on top
</implementation_protocol>

<constraints>
- Changes to `forks/skip-ui/` are preferred but app-level changes in `examples/fuse-app/` are acceptable if the fix requires a different approach to providing CompositionLocals from bridged views.
- Changes must not break iOS behaviour — gate Android-specific code with `#if SKIP` or `#if os(Android)` where needed.
- No changes to upstream-identical files (`skip/Package.swift`, `skipstone/Package.swift`).
- Commit fork changes within the fork submodule, app changes within the parent repo.
- Use existing diagnostic logging (tag `ComposeIdentity`) for verification.
</constraints>

<success_criteria>
- PeerSurvival `rememberViewPeer` logs show `itemKey=<non-null value>` for `PeerRememberTestView` and `CounterCard`
- PeerSurvival views take the PeerStore path (not the fallback `remember` path)
- PeerSurvival CounterCard counters retain their values after tab switches — verify with `peer-survival-tab-switch` scenario
- PeerStore lookups show HITs (not MISSes) for PeerSurvival views after tab switch return
- iOS build passes and all 20 TCA tests pass
- Both Claude and Codex independently confirm the fix is correct and addresses the actual root cause
</success_criteria>
