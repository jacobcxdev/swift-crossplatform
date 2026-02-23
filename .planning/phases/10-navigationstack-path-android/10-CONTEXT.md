# Phase 10: skip-fuse-ui Fork Integration & Cross-Fork Audit - Context

**Gathered:** 2026-02-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Resolve SPM dependency identity conflicts across the monorepo, perform a comprehensive audit of all fork modifications to identify missing skip-fuse-ui counterparts, fix all gaps found, and verify cross-platform parity on both macOS and Android for fuse-app and fuse-library. This phase absorbs the originally-proposed Phase 11 (SkipSwiftUI Audit).

The original Phase 10 scope (NavigationStack path binding on Android) is subsumed — NavigationStack was just the first gap discovered. The full scope is: SPM dependency resolution + skip-fuse-ui fork audit + cross-fork verification + CLAUDE.md/Makefile updates.

</domain>

<decisions>
## Implementation Decisions

### Audit Scope
- **Full diff audit** of every modified file in skip-ui against skip-fuse-ui — not just NavigationStack
- **Bidirectional**: check for missing counterparts in skip-fuse-ui AND evaluate whether some skip-ui code should live in skip-fuse-ui instead — if the audit determines code belongs in skip-fuse-ui, **execute the move** (not just document as recommendation)
- **Compare fork vs upstream** skip-fuse-ui to understand what upstream already provides vs what we've added vs what's still missing
- **Include `#if !SKIP_BRIDGE`-gated files** (~50+ files in skip-ui) — some may provide APIs that Fuse apps need but skip-fuse-ui doesn't yet expose
- **Include other fork guards** — audit `#if os(Android)` guards in TCA, swift-navigation, swift-sharing, swift-perception for correctness with skip-fuse-ui layer
- **Re-evaluate everything** including prior Phase 10 fixes (NavigationStack adapter, ModifiedContent fix) — earlier fixes were reactive; systematic audit may find issues
- **Evaluate prior Phase 10 commits** — audit whether each previous commit is still correct given expanded scope; revert if needed
- **Include BridgeSupport files** (StateSupport.swift, EnvironmentSupport.swift) — these underpin @State/@Environment bridging
- **Verify skip-android-bridge ↔ skip-fuse-ui integration** — audit handoff points between JNI exports and observation re-exports
- **Include Fuse-only types** (ComposeView, composeModifier, JavaBackedView) — our skip-ui changes could affect them
- **Trace view modifier bridging path** — verify full chain from Swift modifier application through SkipUIBridging to Compose
- **Verify Kotlin-generated code alignment** — check that `#if SKIP` markers (SKIP DECLARE, SKIP INSERT) align with what skip-fuse-ui's Swift wrappers expect
- **Evaluate new dependency edges** — check if any fork that touches UI or observation on Android needs skip-fuse-ui as a dependency but currently lacks it
- **Validate dependency graph** for cycles after SPM changes
- **Investigate JVM type erasure risk** — prior verification flagged `StackState<State>.Component` in `navigationDestination(for:)` as a runtime risk on Android. Gap report must specifically investigate and propose a solution before fixes

### Audit Output
- **Research produces a formal gap report** before any code changes; plans fix gaps
- **Document known limitations** for features that have no Fuse-mode support and can't easily be bridged — don't attempt to implement, don't block the phase
- **Correctness only** — no performance audit; optimisation is a future phase concern

### Priority & Structure
- **SPM conflicts first** — resolve dependency conflicts so builds work before auditing code gaps
- **CLAUDE.md + Makefile updates early** — so Claude has that knowledge for remaining plans
- **Separate plans per wave**: Plan 1 (CLAUDE.md + Makefile), Plan 2 (SPM resolution), Plan 3 (Gap audit/report), Plan 4+ (Gap fixes + tests), final plan (roadmap + cleanup)
- **SPM changes atomic** — convert all Package.swift files in one plan; partial conversion could leave dependency graph inconsistent

### Fork Strategy
- **Upstream-friendly, case-by-case** — maintain API stability for eventual upstreaming, but don't let that hold back genuinely new functionality or blockers for Point-Free tools on Android
- **Leave upstream skip-fuse-ui functionality intact** — don't remove upstream code; reduces merge conflicts when upstreaming
- **skip-fuse is stable** — not included in the audit

### Platform Conditionals
- **`#if os(Android)`** for new platform-specific code in skip-fuse-ui — not `#if SKIP_BRIDGE` (skip-fuse-ui IS the bridge)
- **No workarounds anywhere** — implementations must be correct and proper in fuse-app, fuse-library, TCA, and all forks
- **`#if os(Android)` used sparingly** — only when genuinely required

### Phase Administration
- **Phase 11 ("Presentation Dismiss on Android") absorbed into Phase 10** — the full audit will cover dismiss/presentation gaps alongside navigation and other gaps
- **Phase renamed** to reflect full scope (no longer just "NavigationStack Path Binding on Android")
- **Roadmap goal updated** to reflect SPM resolution + skip-fuse-ui audit + cross-fork verification; Phase 11 entry removed from ROADMAP
- **Both fuse-app and fuse-library** must work; lite examples deferred
- **New plans numbered 10-03, 10-04, etc.** — continuing Phase 10 sequence (existing 10-01, 10-02 are superseded by replan)
- **fuse-app should depend on fuse-library** — TCA modularised pattern; code lives in fuse-library, fuse-app packages it as an app. Investigate/validate this as part of SPM resolution

### SPM Dependency Resolution
- **Fork anything that depends on a forked package** — otherwise SPM conflicts between fork and remote. Fork pointfreeco + skip packages. GRDB.swift already forked (SPM resolution only, no code audit). Skip toolchain (`skip.git`, `skip-model`, `skip-unit`) should stay remote if possible — researcher determines whether they're leaf dependencies or need forking
- **Researcher traces full transitive dependency graph** to produce exhaustive list of packages needing forks
- **Convert to local sibling paths** (../package-name) — no version range normalisation needed (local paths use HEAD)
- **Include skip-fuse in SPM path conversion** — skip-fuse is stable (no code audit) but if it depends on any forked package, its Package.swift still needs local paths
- **Keep Android conditionals** (`android ? [deps] : []`) — no need to pull Skip packages on macOS/iOS builds
- **Leave skip-ui's SKIP_BRIDGE conditional** in its Package.swift as-is (different semantic purpose)
- **New forks follow established pattern**: dev/swift-crossplatform branch, added as submodules in forks/, .gitmodules updated
- **Package.resolved**: follow upstream example per package; commit for apps, gitignore for libraries
- **Remove unused dependency declarations** from both fuse-app and fuse-library Package.swift — they cause warnings and will become errors in future SwiftPM
- **Update fuse-library Package.swift** if the audit moves APIs from skip-ui to skip-fuse-ui, add skip-fuse-ui dependency as needed
- **Verify**: `swift package resolve` with zero warnings + full builds (macOS + Android) on both fuse-library and fuse-app

### SkipSwiftUI Adaptation Strategy
- **Match SwiftUI API exactly** — same generic signatures, parameter names, and behavior as Apple's SwiftUI (TCA and Point-Free tools expect this)
- **Follow existing pattern exactly**: struct conforming to View + SkipUIBridging extension providing Java_view
- **Type-erase at bridge boundary** — convert generic View types to `any View` when crossing SkipUIBridging boundary
- **Use existing StateSupport/EnvironmentSupport** classes for state bridging
- **Proactively check ALL existing wrappers** for generic/constraint issues (ModifiedContent issue suggests a pattern)
- **Full SwiftUI signature with no-op for unsupported params** — source compatibility; unsupported parameters silently ignored on Android
- **Extend SkipUIBridging protocol** when new bridge capabilities are needed — keep the contract centralised
- **Modify skip-ui's Compose layer if needed** — Claude's discretion per case based on complexity
- **Update both layers** when Compose-side changes affect the bridge contract
- **Follow existing test location pattern** for new wrapper tests

### Verification & Testing
- **Sequential verification**: macOS build → macOS tests → Android build → Android tests (catch basic issues on faster platform first)
- **Use Makefile targets** — update Makefile so `make build` and `make test` cover both platforms by default (smart defaults)
- **Clean builds only after dependency changes** — incremental builds for code-only changes
- **Android test pass is a hard gate** — non-negotiable for cross-platform parity
- **Tests per gap** — each significant gap fix gets at least one test proving the bridging works
- **Full test suite after each plan** — catch regressions early
- **macOS tests sufficient for iOS compatibility** (exercises SwiftUI code paths)
- **Swift 6 concurrency**: handle reactively as build errors, not proactive audit
- **One commit per logical fix** within fork submodules — easier to review, revert, and upstream individually
- **SPM plan commit strategy**: one commit per fork submodule for its Package.swift change; parent repo updates all submodule pointers in a single commit

### CLAUDE.md & Makefile Updates
- **Add new gotchas**: Android builds can pass even when running fails; test execution is the real verification gate; clean builds required after dependency changes
- **Document all Makefile commands** so Claude knows how to work with the project
- **Document environment variables**: map TARGET_OS_ANDROID, SKIP_BRIDGE, os(Android) to their effects
- **Update Makefile** for smart defaults: `make build` = both examples (fuse-library + fuse-app) on both platforms (macOS + Android), `make test` = same. EXAMPLE= override still works for targeting a single example

### Phase Completion Criteria
- Zero SPM identity conflict warnings on `swift package resolve`
- All audit gaps addressed (counterparts created or documented as known limitation)
- Full test suite green on both macOS and Android for both fuse-app and fuse-library
- No workarounds — proper implementations with `#if os(Android)` only where required
- CLAUDE.md updated with gotchas, Makefile commands, env var documentation
- Makefile updated with smart defaults
- Presentation dismiss (`@Dependency(\.dismiss)`) working on Android (absorbed from Phase 11)
- Roadmap updated with new phase name, goal, and success criteria; Phase 11 entry removed

### Claude's Discretion
- Whether to modify skip-ui's Compose layer for missing bridge constructors (evaluate per case)
- Commit granularity beyond "one per logical fix" for trivial changes

</decisions>

<specifics>
## Specific Ideas

- NavigationStack was the canary — the broader pattern is that skip-fuse-ui was never forked before, so ALL skip-ui modifications potentially lack their Fuse-mode counterparts
- The ModifiedContent protocol conformance fix (#10989) suggests a class of issues where existing skip-fuse-ui wrappers have incorrect generic constraints
- Changes WILL be upstreamed at some point — maintain API stability, judge each change on its own merits
- The user is jacobcxdev — the fork owner. Only fork pointfreeco and skip packages

</specifics>

<deferred>
## Deferred Ideas

- Performance audit of bridging overhead (JNI call frequency, SkipUIBridging delegation cost) — future phase
- Architecture documentation of the two-tier bridging design — housekeeping task
- Lite example support — explicitly deferred
- Re-export verification (SkipFuseUI umbrella imports) — trust current exports

</deferred>

---

*Phase: 10-navigationstack-path-android*
*Context gathered: 2026-02-23*
