<objective>
Investigate and fix the root cause of ForEach namespace UUID instability in the PeerStore identity system.

The ForEach container in skip-ui uses a `rememberSaveable { UUID }` to scope its PeerStore namespace. Despite `rememberSaveable`, the UUID changes across data mutations (add/delete card) and tab switches, causing all cached peers to become unreachable and counters to reset to 0.

This issue has persisted through five rounds of UAT. Three attempted fixes addressed adjacent problems (cleanup key normalisation, structural equality) but none resolved the core namespace instability. The root cause is NOT yet identified with certainty. Do not accept any hypothesis without verifiable evidence.
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
- `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ForEach.swift` — Swift source (lines 30, 97-108, 260-296)
- `forks/skip-ui/Sources/SkipUI/SkipUI/Compose/PeerStore.swift` — PeerStore, PeerCacheKey, PeerStoreNamespaceModifier, rememberViewPeer
- `examples/fuse-app/.build/plugins/outputs/skip-ui/SkipUI/destination/skipstone/SkipUI/src/main/kotlin/skip/ui/ForEach.kt` — transpiled Kotlin (ground truth of what runs on Android)
- `examples/fuse-app/.build/plugins/outputs/skip-ui/SkipUI/destination/skipstone/SkipUI/src/main/kotlin/skip/ui/PeerStore.kt` — transpiled PeerStore Kotlin
- `CLAUDE.md` — project architecture and conventions

Test harness source files (ForEach namespace setting exercises this issue):
- `examples/fuse-app/Sources/FuseApp/ForEachNamespaceSetting.swift` — reducer + view: cards with ForEach, add/delete/deleteFirst/deleteLast actions
- `examples/fuse-app/Sources/FuseApp/IdentityComponents.swift` — shared: `idLog()`, `CardItem`, `CounterCard`, `PeerRememberTestView`
- `examples/fuse-app/Sources/FuseApp/ScenarioEngine.swift` — scenario primitives, runner, and registry (6 scenarios including 4 ForEach-specific)
- `examples/fuse-app/Sources/FuseApp/TestHarnessFeature.swift` — root TCA reducer: tab state, UICommand forwarding, child composition
- `examples/fuse-app/Sources/FuseApp/ControlPanelView.swift` — control panel: scenario runner UI
- `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` — TCA integration tests (20 tests across 4 suites)

Log files from UAT Round 5 reproductions:
- `/tmp/r5-tab-switch-logs.txt` — tab switch namespace change
- `/tmp/r5-add-card-logs.txt` — add card namespace change
- `/tmp/r5-delete-card-logs.txt` — delete card namespace change
</context>

<test_harness>
The fuse-app uses a test harness architecture for exercising identity bugs. Key concepts:

**Settings** are tab-based TCA reducer+view pairs. ForEachNamespaceSetting exercises this issue with:
- Cards displayed in a `ForEach` inside a `List`
- Actions: addCard, deleteCard(id), deleteFirstCard, deleteLastCard
- UICommand support: scrollToTop, scrollToBottom (for scroll identity testing)

**Scenarios** are automated step sequences run from the Control Panel tab. Available ForEach scenarios:
- `foreach-ns-tab-switch` — switch tabs and back, verify namespace stability
- `foreach-ns-scroll` — add 5 cards, scroll bottom/top, verify peer survival
- `foreach-ns-add-card` — add a card, verify namespace + peer stability
- `foreach-ns-delete-card` — delete last card, verify namespace + peer stability
- `foreach-ns-compound` — add + delete + tab switch compound mutation

All scenarios use `PRE_`/`POST_` checkpoint brackets around mutations for log-based oracle analysis.

**Oracle pattern** for detecting namespace instability from logs:
1. Clear logcat: `adb logcat -c`
2. Run scenario (from Control Panel or auto-run)
3. Dump: `adb logcat -d -s fuse.app/Identity:D ComposeIdentity:D > /tmp/identity-logs.txt`
4. Extract between checkpoints: `sed -n '/CHECKPOINT PRE_ADD_CARD/,/CHECKPOINT POST_ADD_CARD/p' /tmp/identity-logs.txt`
5. Count unique namespace UUIDs: `... | grep -oP 'ns=\K[0-9a-f-]+' | sort -u | wc -l`
6. Result: 1 = stable, >1 = namespace instability detected

Auto-run on launch: set `LaunchConfig.autoRunScenario` in `ScenarioEngine.swift` to a scenario ID (e.g. `"foreach-ns-add-card"`).
</test_harness>

<issue_summary>
ForEach.swift line 30 declares `var peerStoreNamespace: AnyHashable?` as an instance property. Lines 97-108 set it via `rememberSaveable { UUID }` inside the `@Composable Evaluate()` function when a PeerStore is available.

The namespace is used as part of `PeerCacheKey(namespace:itemKey:viewSlotKey:)` to scope peers within a shared PeerStore.

Evidence from logs:
- Tab switch: namespace changes from `1/2a464f1d-...` to `1/5045b3f4-...` after switching away and back
- Add card: namespace changes from `1/0a968fe9-...` to `1/abc4930f-...` after adding a card
- Delete card: three different namespace UUIDs observed in one session

Item keys (card UUIDs) remain stable. Only the namespace changes.

The transpiled Kotlin shows:
- `peerStoreNamespace` has a custom getter with `sref()`: `get() = field.sref({ this.peerStoreNamespace = it })`
- `rememberSaveable` is called inside `LocalPeerStore.current.sref()?.let { store -> ... }`
- ForEach is a View class — new Kotlin instances are created on each composition pass
</issue_summary>

<what_has_been_tried>
| Plan | What was done | Result |
|------|--------------|--------|
| Plan 10 | Added `rememberSaveable { UUID }` for namespace | UUID still changes across mutations/tab switches |
| Plan 15 | Normalised cleanup keys via `composeBundleNormalizedKey()` | Fixed cleanup evictions (0 spurious evicts), namespace instability unchanged |
| Plan 16 | Replaced `PeerNamespacePath` struct with String concatenation | Fixed structural equality within a single lifecycle (HITs during scroll), UUID regeneration unchanged |
</what_has_been_tried>

<research_phase>
Use subagents to prevent context bloat. Spawn `Explore` or `general-purpose` agents for each research task.

Research areas (non-exhaustive — follow the evidence):

1. **Understand the ForEach lifecycle on Kotlin side**: How is ForEach instantiated? Is it a new Kotlin object on each recomposition? What happens to `peerStoreNamespace` on the old instance? How does `sref()` interact with this?

2. **Understand `rememberSaveable` slot allocation**: At what composition position is `rememberSaveable` called? Does calling it inside `?.let { store -> ... }` affect slot stability? What happens to the slot when the composition is disposed and restored?

3. **Trace the actual UUID generation**: Add logging INSIDE the `rememberSaveable` lambda to determine whether it's being re-executed (new slot) or returning the saved value. This is the critical diagnostic.

4. **Understand Skip's `sref()` property wrapper**: What does `get() = field.sref({ this.peerStoreNamespace = it })` actually do? Could it interfere with value retention?

5. **Compare with other `rememberSaveable` usage in skip-ui**: Do other `rememberSaveable` calls in skip-ui survive recomposition correctly? What's different about this one?

6. **Check parent composition context**: What creates the PeerStore that Section 6's ForEach sees? Does the PeerStore itself get recreated (which would change the composition tree)?

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
# In ScenarioEngine.swift, set LaunchConfig.autoRunScenario = "foreach-ns-add-card"

# Capture identity logs (after scenario run)
adb logcat -c                    # clear buffer BEFORE running scenario
# ... run scenario ...
adb logcat -d -s fuse.app/Identity:D ComposeIdentity:D > /tmp/identity-logs.txt

# Oracle: check for namespace instability between checkpoints
sed -n '/CHECKPOINT PRE_ADD_CARD/,/CHECKPOINT POST_ADD_CARD/p' /tmp/identity-logs.txt \
    | grep -oP 'ns=\K[0-9a-f-]+' | sort -u | wc -l
# 1 = stable, >1 = namespace instability

# Key log patterns to check:
# - namespace= / ns= values (should be stable across mutations)
# - HIT vs MISS (should be HIT on revisit)
# - releaseAll (PeerStore disposal)
# - insert (new peer creation — should not happen on revisit)
```

Android builds take ~5 minutes. Use `run_in_background` for the build/export step.
</build_and_test>

<implementation_protocol>
When implementing fixes:

1. Make the change in Swift source (e.g., `ForEach.swift`, `PeerStore.swift`)
2. Verify iOS build: `just ios-build fuse-app`
3. Run TCA tests: `just ios-test fuse-app` (all 20 must pass)
4. Ask Codex to review the diff before proceeding to Android build
5. Set `LaunchConfig.autoRunScenario = "foreach-ns-compound"` for comprehensive verification
6. Build and deploy to Android: `just android-run fuse-app`
7. Capture and analyse logs using the oracle pattern
8. Share logs with Codex for independent verification
9. If fix doesn't work, return to research — do NOT stack another guess on top
</implementation_protocol>

<constraints>
- All changes must be in `forks/skip-ui/` (the skip-ui fork). Do not modify the skipstone transpiler.
- Changes must not break iOS behaviour — gate Android-specific code with `#if SKIP` where needed.
- No changes to upstream-identical files (`skip/Package.swift`, `skipstone/Package.swift`).
- Commit within the fork submodule, not the parent repo.
- Use existing diagnostic logging (tag `ComposeIdentity`) for verification.
</constraints>

<success_criteria>
- ForEach namespace UUID is stable across:
  - Tab switches (ForEach NS tab → other tab → back) — verify with `foreach-ns-tab-switch` scenario
  - Data mutations (add card, delete card) — verify with `foreach-ns-add-card` and `foreach-ns-delete-card` scenarios
  - Compound mutations (add + delete + tab switch) — verify with `foreach-ns-compound` scenario
  - Scroll off-screen and back — verify with `foreach-ns-scroll` scenario
- PeerStore lookups show HITs (not MISSes) after all scenarios
- CounterCard counters retain their values after all scenarios
- Oracle pattern shows exactly 1 unique namespace UUID between each PRE_/POST_ checkpoint pair
- iOS build passes and all 20 TCA tests pass
- Both Claude and Codex independently confirm the fix is correct and addresses the actual root cause
</success_criteria>
