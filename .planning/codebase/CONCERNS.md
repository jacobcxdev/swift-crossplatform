# Codebase Concerns

**Analysis Date:** 2026-02-20

## Critical Issues

### Infinite Recomposition Loop on Android (TCA + Skip Fuse Mode)

**Issue:** When using The Composable Architecture (TCA) with Skip's Fuse mode on Android, the app enters an infinite view body recomposition loop. The app works correctly on iOS.

**Files:**
- `forks/swift-composable-architecture/Sources/ComposableArchitecture/Store.swift` (lines 119-125)
- `forks/swift-composable-architecture/Sources/ComposableArchitecture/ObservationStateRegistrar.swift`
- `.build/plugins/outputs/service-app/ServiceApp/destination/skipstone/SkipBridgeGenerated/` (generated bridge code)
- `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`

**Root Cause:** The Skip build plugin generates `Swift_composableBody` JNI functions that evaluate view bodies **without any observation tracking wrapper**. On iOS, SwiftUI internally wraps body evaluation with `withObservationTracking { body() } onChange: { scheduleRerender() }` — firing once, then auto-canceling. On Android via Skip, there's no equivalent wrapper. The only recomposition driver is MutableStateBacking's integer counters from skip-model, which increment on every `withMutation()` call without deduplication. TCA's `@ObservableState` macro generates high-frequency `withMutation` calls (UUID-based `_$id` changes on every state assignment), causing thousands of counter increments → thousands of recompositions → infinite loop.

**Impact:**
- App is unusable on Android in Fuse mode
- Cannot add items or interact with the UI
- Blocks all Android development with TCA

**Workaround:** None currently implemented. Previous attempts to use app-level Observing wrapper were reverted per architectural decision (fix must be at bridge level, not app level).

**Fix Approach:**
1. Fork skip-android-bridge and/or skip-fuse-ui
2. Implement a Compose subscriber that wraps view body evaluation with `withObservationTracking` (or `withPerceptionTracking`)
3. Bridge onChange callbacks to Compose's MutableState counter (increment ONCE per observation cycle)
4. Update TCA Store.swift to use PerceptionRegistrar on Android instead of SkipAndroidBridge.Observation.ObservationRegistrar()
5. Verify on both iOS simulator and Android emulator

**Priority:** CRITICAL — blocks core functionality

**Related Docs:**
- `.planning/codebase/whats-next.md` — Full work plan with implementation steps
- `.planning/codebase/observation-bridge-analysis.md` — Deep technical analysis of root cause
- `.planning/codebase/observation-architecture-decision.md` — Architecture decision and implementation plan

---

## Architecture & Design Issues

### 12 Large Submodule Forks Create Maintenance Burden

**Issue:** The project depends on 12 forked Point-Free and GRDB dependencies as git submodules, creating significant maintenance overhead:
- `forks/swift-composable-architecture` (232 MB)
- `forks/GRDB.swift` (378 MB)
- `forks/swift-snapshot-testing` (50 MB)
- `forks/swift-navigation` (17 MB)
- `forks/sqlite-data` (6.8 MB)
- `forks/swift-structured-queries` (4.1 MB)
- `forks/swift-dependencies` (2.7 MB)
- `forks/swift-sharing` (1.7 MB)
- `forks/swift-perception` (1.1 MB)
- `forks/swift-clocks` (1.0 MB)
- `forks/combine-schedulers` (956 KB)
- Plus additional Skip framework forks: `skip-android-bridge`, `skip-ui`

**Files:** All of `forks/` directory

**Impact:**
- Large repository size (~700 MB of fork dependencies)
- Difficult to track upstream changes and security updates
- Complex dependency resolution when updates occur
- Long clone/build times
- Increased git history complexity
- Risk of diverging from upstream without clear change tracking

**Why Needed (Per Architecture Documents):**
- TCA requires Android support via modified ObservationStateRegistrar
- Point-Free packages require Skip/Android bridge compatibility adjustments
- swift-perception fork provides unified observation abstraction across iOS/Android

**Scaling Limit:** Future updates from upstream Point-Free packages will require manual cherry-picking of changes. Current branching strategy (v1.X.Y-N-ghash) makes tracking harder.

**Mitigation:**
- Document all fork changes with clear markers (e.g., `// SKIP ANDROID:` comments)
- Maintain a FORKS.md index listing what changed in each fork and why
- Consider moving fork changes upstream (TCA Android support, swift-perception integration)
- Set up automatic upstream change tracking

**Priority:** MEDIUM — manageable now, becomes critical as projects mature

---

### Lite Mode Observation Broken, Fuse Mode Workaround Needed

**Issue:** Skip's Lite mode (transpiled to Kotlin) has observation semantics incompatible with TCA's high-frequency mutations. The observation bridge (`skip-model`'s MutableStateBacking) uses counter-based tracking that cannot deduplicate updates, breaking TCA's assumption of value-based observation.

**Files:**
- `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` (JNI bridge to MutableStateBacking)
- `.build/checkouts/skip-model/Sources/SkipModel/MutableStateBacking.swift` (counter-based Kotlin-side state)
- `.build/checkouts/skip-model/Sources/SkipModel/StateTracking.swift` (deferred tracking, can lose initial mutations)

**Why It's Broken:**
- Counter approach is fundamentally incompatible with value-based observation
- skip-model explicitly documents: "Skip does not support calls to the generated `access(keyPath:)` and `withMutation(keyPath:_:)` functions"
- Deferred tracking via StateTracking can lose initial mutations during view construction

**Impact:**
- Cannot use Lite mode for TCA-based apps
- Fuse mode (native Swift compilation) is the only viable Android path
- Limits cross-platform code reuse for library packages

**Current Workaround:** Use Fuse mode exclusively for Android (native Swift compilation). This requires Android NDK/toolchain setup.

**Fix Approach (Upstream):**
1. Fix observation in skip-ui's Fuse mode via SKIP_BRIDGE conditional in Package.swift
2. Keep Lite mode unchanged (maintain upstream compatibility)
3. Ensure Fuse-mode fix gates behind SKIP_BRIDGE to not affect Lite

**Priority:** MEDIUM — not blocking current app (using Fuse mode), but limits future library support

---

## Dependency & Compatibility Issues

### Unimplemented XCTTODO Tests Throughout Forks

**Issue:** Several forked packages use `XCTTODO` markers for unimplemented tests, indicating incomplete porting to Android/Skip:

**Files:**
- `forks/swift-navigation/Examples/CaseStudiesTests/Internal/XCTTODO.swift`
- `forks/swift-dependencies/Tests/DependenciesTests/Internal/XCTTODO.swift`
- `forks/swift-composable-architecture/Tests/ComposableArchitectureTests/TestStore.swift` (TestStore has platform-specific complexity)

**Impact:**
- Test coverage gaps on Android
- Potential hidden bugs in less-tested code paths
- Integration tests may pass on iOS but fail on Android

**Risk:** Medium — these are typically compatibility/platform-specific features, not core functionality

**Fix Approach:**
1. Audit each XCTTODO to understand why it was marked
2. Implement or remove as appropriate for Android/Skip context
3. Add platform-specific test variants if needed

**Priority:** MEDIUM — should be addressed before shipping production app

---

### Skip Framework Fork State Unclear

**Issue:** Two Skip framework forks (`skip-android-bridge` and `skip-ui`) are submodules but show as modified in git status without clear documentation of changes.

**Files:**
- `forks/skip-android-bridge` (modified, no change documentation)
- `forks/skip-ui` (modified, no change documentation)

**Current State per git:**
```
 m forks/skip-android-bridge
 m forks/skip-ui
```

**Impact:**
- Unclear what changes were made to Skip framework
- Difficult to track fixes vs workarounds
- Hard to coordinate with Skip maintainers on upstream contributions
- Risk of changes being accidentally reverted

**Fix Approach:**
1. Document all changes in Skip forks with rationale
2. Create Pull Requests to skip-tools for upstream-compatible changes
3. Mark workarounds clearly in code comments
4. Maintain FORKS.md tracking doc

**Priority:** MEDIUM — needed for upstream coordination

---

## Scaling & Complexity Issues

### Repository Growth Not Bounded

**Issue:** The main git repository contains 12 large fork submodules totaling ~700 MB, plus example apps and documentation. As forks diverge from upstream, size and complexity will grow.

**Files:** Entire `forks/` directory structure

**Current Scale:**
- GRDB.swift fork: 378 MB (largest)
- swift-composable-architecture fork: 232 MB
- Total forks: ~700 MB uncompressed

**Scaling Problem:** With 12 forks, each with its own git history, cloning and updates become increasingly slow. New team members will wait 5-10 minutes just to clone.

**Mitigation Strategy:**
1. Consider monorepo tooling (if repo grows further)
2. Set up proper .gitignore for build artifacts (currently ignores .build/ correctly)
3. Monitor fork divergence from upstream (track commits-ahead count)
4. Archive or remove forks that are fully merged upstream

**Priority:** LOW now, becomes HIGH if adding more forks or if any fork exceeds 500 MB

---

## Testing & Coverage Gaps

### No Integration Tests for Android/Skip Specific Behavior

**Issue:** Test suite focuses on iOS/macOS. Android-specific behavior (Compose interop, observation bridging, JNI calls) has limited test coverage.

**Files:**
- `examples/lite-app/Tests/` — Tests for Lite app
- `examples/fuse-app/Tests/` — Tests for Fuse app (not yet created per examples directory state)
- `forks/swift-composable-architecture/Tests/ComposableArchitectureTests/AndroidParityTests.swift` — Only Android-specific test file found

**Coverage Gaps:**
- No tests for observation bridge behavior under high-frequency mutations
- No tests for Compose recomposition stability
- No tests for cross-platform state synchronization
- Missing integration tests for TCA + Skip Fuse specific scenarios

**Impact:**
- Android-specific bugs may escape to production
- Regressions in observation behavior only caught at runtime
- Hard to verify fix for infinite recomposition loop

**Fix Approach:**
1. Create comprehensive Android-specific test suite
2. Add recomposition stability tests
3. Add high-frequency mutation stress tests
4. Run tests on actual Android emulator/device (not just iOS)

**Priority:** HIGH — essential for shipping stable Android app

---

## Documentation Issues

### Skip Documentation Not Committed to Repository

**Issue:** While Skip framework documentation exists at `docs/skip/`, the analysis documents critical to understanding current blockers are not yet committed:
- `.claude/observation-bridge-analysis.md` (needs version control)
- `.claude/observation-architecture-decision.md` (needs version control)
- Work-in-progress notes in `whats-next.md` (long, unstructured)

**Files:**
- `docs/skip/` — Official Skip docs (committed)
- `.claude/` directory — Analysis docs (not in git, not tracked)
- `whats-next.md` — Active work log (332 lines, mixing analysis + tasks)

**Impact:**
- Critical architectural decisions exist only in `.claude/` (outside version control)
- New team members can't access full context
- Analysis of root causes not in git history
- whats-next.md is too long for quick reference

**Fix Approach:**
1. Commit `.claude/observation-bridge-analysis.md` and `.claude/observation-architecture-decision.md` to git
2. Create `docs/ANDROID_ARCHITECTURE.md` summarizing Android-specific architecture
3. Break whats-next.md into structured docs: IMMEDIATE_TASKS.md, ROADMAP.md, etc.
4. Update main README.md with links to key architecture docs

**Priority:** MEDIUM — affects onboarding and knowledge preservation

---

## Known Workarounds & Hacks

### Observation.swift.bak Contains Working Pattern (Not Integrated)

**Issue:** A working observation wrapper pattern exists in `Sources/ServiceApp/Observing.swift.bak` but was explicitly not integrated into the bridge layer per architectural review.

**Files:**
- `Sources/ServiceApp/Observing.swift.bak` (contains working withPerceptionTracking pattern)

**Current Status:**
- File backed up as .bak — NOT active
- Pattern demonstrates the fix approach (wrapping body eval with withPerceptionTracking)
- Changes were reverted per architectural decision: "fix must be at bridge level, not app level"

**Context:** This was an attempted app-level workaround. User correctly rejected it because the fix must be at the Skip bridge level (skip-android-bridge or skip-fuse-ui), not in TCA or app code, to maintain platform parity.

**Impact:** Medium-low — the backup file serves as reference for the eventual bridge-level fix implementation

**Priority:** LOW — this is documentation of a rejected approach, will be deleted once bridge-level fix is implemented

---

## Future Maintenance Risks

### Upstream Synchronization Strategy Undefined

**Issue:** No formal process exists for tracking, integrating, or rejecting upstream changes from the 12 forked packages. As upstream packages release updates, the forks will diverge over time.

**Files:** All fork packages in `forks/` directory

**Risk Scenario:**
1. upstream swift-composable-architecture releases v2.0 with major features
2. No process to evaluate whether fork should update
3. Fork falls further behind, security patches may be missed
4. Integration becomes increasingly expensive

**Current State:** Forks were created from specific versions (e.g., v1.23.1-38-gdda9b267ea for TCA) but no tracking doc exists showing:
- Original upstream version
- Current fork version
- Commits ahead/behind upstream
- Change rationale for each commit

**Mitigation:**
1. Create FORKS.md tracking each fork's:
   - Original upstream version
   - Current divergence (commits ahead)
   - Key changes and why they were made
   - Candidates for upstream PRs
2. Set up automated upstream tracking (GitHub Actions workflow checking for new releases)
3. Establish release schedule for evaluating upstream updates (quarterly?)
4. Document which forks are "keep temporarily" vs "maintain long-term"

**Priority:** LOW now, MEDIUM as forks age (6+ months)

---

## Build & Deployment Risks

### Android Build Process Not Fully Documented

**Issue:** The project uses Skip's Fuse mode to compile Swift natively for Android, but the build process has platform-specific complexity not yet documented in ARCHITECTURE.md or BUILD.md.

**Files:**
- Various `Package.swift` files with SKIP_BRIDGE conditionals
- `.build/` directory (git-ignored, rebuilt each time)
- Xcode project files in `examples/*/Darwin/`

**Knowledge Gaps:**
- How to set up local Skip dev environment (mentioned in whats-next.md but not in main docs)
- Android NDK/toolchain requirements
- How SKIP_BRIDGE env var gates Fuse-mode dependencies
- How the skipstone build plugin generates JNI bridge code
- Debugging workflow differences between iOS simulator and Android emulator

**Impact:**
- New developers can't easily set up build environment
- Onboarding is slow
- Hard to troubleshoot build failures

**Fix Approach:** Create `docs/BUILD.md` with:
1. System requirements (Xcode, Android NDK, Swift for Android SDK)
2. Local development setup steps
3. How to build for iOS simulator
4. How to build for Android emulator
5. Debugging commands for both platforms
6. Common build issues and solutions

**Priority:** MEDIUM — needed before adding team members

---

## Summary Table

| Concern | Severity | Impact | Fix Effort | Priority |
|---------|----------|--------|------------|----------|
| Infinite recomposition loop (Android TCA) | CRITICAL | App unusable | MEDIUM | CRITICAL |
| 12 large fork submodules | MEDIUM | Maintenance burden | HIGH | MEDIUM |
| Skip Lite mode observation broken | MEDIUM | Limits lib support | HIGH | MEDIUM |
| No Android integration tests | HIGH | Hidden bugs | MEDIUM | HIGH |
| Skip forks untracked/undocumented | MEDIUM | Upstream coordination | LOW | MEDIUM |
| Observation wrapper pattern not integrated | LOW | Reference only | N/A | LOW |
| Upstream sync strategy undefined | LOW | Future risk | MEDIUM | LOW |
| Android build process undocumented | MEDIUM | Onboarding slow | LOW | MEDIUM |
| XCTTODO tests unimplemented | MEDIUM | Coverage gaps | MEDIUM | MEDIUM |
| Repository size growth unbounded | LOW | Performance risk | MEDIUM | LOW |

---

*Concerns audit: 2026-02-20*
