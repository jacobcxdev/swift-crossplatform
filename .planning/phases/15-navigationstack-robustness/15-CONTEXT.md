# Phase 15: NavigationStack Android Robustness - Context

**Gathered:** 2026-02-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix three P2 NavigationStack bugs on Android — binding-driven push, JVM type erasure for multi-destination, and dismiss JNI timing — replacing `withKnownIssue` wrappers with passing tests. Strengthens NAV-02 and TCA-32 from reducer-driven-only to full binding-driven push support.

</domain>

<decisions>
## Implementation Decisions

### Fix priority & ordering
- Claude determines optimal fix order based on code dependency analysis
- One plan per bug — each fix gets its own plan with isolated fix + test, verified independently
- All three bugs must be fixed in this phase — no deferral even if one proves significantly harder
- Fixes should target the root cause, going as deep as needed (skip-fuse-ui, skip-android-bridge, etc.) rather than patching at the TCA layer

### Workaround removal policy
- Remove `withKnownIssue` wrappers immediately when each fix lands, in the same plan
- Also clean up related workarounds (e.g., `#if os(Android)` guards, Effect.send workaround) that become redundant after a fix
- Revert the Effect.send workaround (Just publisher → run effect switch) back to the upstream Just publisher pattern if the dismiss timing root cause fix makes it unnecessary — minimise fork divergence
- Fork divergence policy: balance case-by-case — small divergence is acceptable, large divergence prefers upstream alignment

### Test evidence scope
- Comprehensive tests for each fix: happy path + edge cases + regression guards
- Tests live in existing `examples/fuse-library/Tests/` target alongside other cross-platform tests
- Tests must pass on both Darwin (`swift test`) and Android (`skip android test`) — no platform-only test gates
- Use TCA `TestStore` where possible for action/state exhaustivity; fall back to direct `Store` only if TestStore has Android issues

### Breaking change tolerance
- skip-fuse-ui API surface changes are acceptable if needed (SwiftUI-facing API should stay the same)
- No limit on how many forks a single fix can touch — fix it right across whatever forks the root cause requires
- Update the fuse-app example if fixes change navigation behaviour — demonstrate end-to-end functionality
- New files/modules in forks are fine — clean architecture over minimising file count

### Claude's Discretion
- Exact fix ordering across the three bugs
- Technical approach per bug (type tokens vs generics workaround, JNI timing strategy, etc.)
- Test naming and organisation within the existing test target
- Whether to inline small helpers or extract to new files

</decisions>

<specifics>
## Specific Ideas

- The Effect.send workaround from today (switching Just publisher to run effects in Effect.swift) is a known candidate for reversion if dismiss timing is root-cause fixed
- The existing `withKnownIssue` wrappers in the test suite mark exactly which tests need to be converted to passing
- Canonical patterns from `/pfw-composable-architecture` (NavigationStack path binding, PresentationAction.dismiss) and `/pfw-swift-navigation` (path-driven navigation, dismiss dependency) should guide the expected behaviour

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 15-navigationstack-robustness*
*Context gathered: 2026-02-24*
