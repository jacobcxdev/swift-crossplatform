# P6 Branch Divergence Research: sqlite-data `flote/service-app` References

**Date:** 2026-02-22
**Investigator:** Claude (deep-dive researcher)
**Scope:** sqlite-data fork's Package.swift branch references and their implications for standalone builds, CI, and Phase 6 integration.

---

## Executive Summary

sqlite-data's `Package.swift` references `flote/service-app` branches on `jacobcxdev` GitHub forks for five dependencies. However, **none of those `jacobcxdev` forks actually have a `flote/service-app` branch on GitHub**. The `Package.resolved` file (which locked the build at some prior working state) pins to `flote-works` URLs instead — but the `flote-works` GitHub org itself now returns HTTP 404. The local fork submodules all have `dev/swift-crossplatform` as their canonical branch, which is **ahead** of the pinned resolved SHAs for four of the five dependencies. A standalone `swift build` inside `forks/sqlite-data/` would currently **fail** to resolve dependencies. The fuse-library context is unaffected because sqlite-data is commented out and not yet wired into fuse-library. **This must be fixed at the start of Phase 6, not deferred.**

---

## 1. sqlite-data Package.swift — All Branch References

File: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
    .package(url: "https://github.com/jacobcxdev/GRDB.swift", branch: "flote/service-app"),          // BRANCH REF
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.0.0"),
    .package(url: "https://github.com/jacobcxdev/swift-custom-dump", from: "1.3.3"),
    .package(url: "https://github.com/jacobcxdev/swift-dependencies", branch: "flote/service-app"),  // BRANCH REF
    .package(url: "https://github.com/jacobcxdev/swift-perception", branch: "flote/service-app"),    // BRANCH REF
    .package(url: "https://github.com/jacobcxdev/swift-sharing", branch: "flote/service-app"),       // BRANCH REF
    .package(url: "https://github.com/jacobcxdev/swift-snapshot-testing", from: "1.18.4"),
    .package(
        url: "https://github.com/jacobcxdev/swift-structured-queries",
        branch: "flote/service-app",                                                                  // BRANCH REF
        traits: [...]
    ),
    .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.5.0"),
]
// Android conditional additions use version ranges (skip-bridge, skip-android-bridge, swift-jni)
```

**Five dependencies use `branch: "flote/service-app"`:**
1. `jacobcxdev/GRDB.swift`
2. `jacobcxdev/swift-dependencies`
3. `jacobcxdev/swift-perception`
4. `jacobcxdev/swift-sharing`
5. `jacobcxdev/swift-structured-queries`

---

## 2. sqlite-data Commit History

```
c153312 Update dependency URLs from flote-works to jacobcxdev   ← HEAD (recent rename)
d45d155 Restore upstream platform minimums (iOS 13, macOS 10.15)
912e845 Add Category B DynamicProperty parity tests for Fetch/FetchAll/FetchOne
cd8a10b Un-guard DynamicProperty conformances for Android
db80603 Raise platform minimums to iOS 16/macOS 13 for SkipBridge compat
1278500 Add Category B parity tests for SQLiteData CRUD operations
...
01a896a Fix Package@swift-6.0.swift to use flote-works/swift-custom-dump
b453d02 Use flote-works forks for swift-custom-dump and swift-snapshot-testing
fd0daaa Point swift-perception to flote-works fork
```

The most recent commit (`c153312`) renamed all dependency URLs from `flote-works/` to `jacobcxdev/`. This is the correct direction — but the branch name `flote/service-app` was not updated at the same time, and that branch does not exist on `jacobcxdev` GitHub.

**sqlite-data branches:**
- Local: `dev/swift-crossplatform` (current), `main`
- Remote `origin` (`jacobcxdev/sqlite-data`): has `dev/swift-crossplatform`
- Remote `flote-works` (`flote-works/sqlite-data`): has `flote/service-app`, `main`

---

## 3. Dependency-by-Dependency Branch Status

### 3.1 GRDB.swift

| Item | Value |
|------|-------|
| sqlite-data Package.swift URL | `https://github.com/jacobcxdev/GRDB.swift` |
| sqlite-data branch ref | `flote/service-app` |
| Local fork path | `forks/GRDB.swift` |
| Local branch | `dev/swift-crossplatform` |
| `jacobcxdev/GRDB.swift` has `flote/service-app`? | **NO** (not present on remote) |
| `jacobcxdev/GRDB.swift` has `dev/swift-crossplatform`? | **YES** (`36dba72a8`) |
| `flote-works/GRDB.swift` has `flote/service-app`? | YES (locally cached as `remotes/flote-works/flote/service-app`) |
| Package.resolved pinned revision | `36dba72a8562d9b7aec10a95021836060831c9a5` |
| Package.resolved pinned URL | `https://github.com/flote-works/GRDB.swift` (outdated — pre-rename) |
| `dev/swift-crossplatform` commits ahead of resolved PIN | **0** (identical SHA) |
| Divergence from `flote-works/flote/service-app` | `dev/swift-crossplatform` IS `flote-works/flote/service-app` tip — same SHA |

**Status: GRDB is effectively identical.** The `dev/swift-crossplatform` branch tip (`36dba72a8`) is the same commit as `flote-works/flote/service-app`. The correct fix is to change the branch reference from `flote/service-app` to `dev/swift-crossplatform`.

### 3.2 swift-dependencies

| Item | Value |
|------|-------|
| sqlite-data Package.swift URL | `https://github.com/jacobcxdev/swift-dependencies` |
| sqlite-data branch ref | `flote/service-app` |
| `jacobcxdev/swift-dependencies` has `flote/service-app`? | **NO** |
| `jacobcxdev/swift-dependencies` has `dev/swift-crossplatform`? | **YES** (`3274961`) |
| `flote-works/flote/service-app` local tip SHA | `01f18e1036fecf44d18573228ee28144f61306e0` |
| Package.resolved pinned revision | `45992be553ea7bae99670939b54fd23c7f657ae0` |
| Package.resolved pinned URL | `https://github.com/flote-works/swift-dependencies` (outdated) |
| `dev/swift-crossplatform` commits ahead of resolved PIN | **3** |
| `dev/swift-crossplatform` commits ahead of `flote-works/flote/service-app` | **1** (`3274961 Update dependency URLs from flote-works to jacobcxdev`) |
| `flote-works/flote/service-app` ahead of `dev/swift-crossplatform` | **0** |

`dev/swift-crossplatform` commit log vs `flote-works/flote/service-app`:
```
3274961 Update dependency URLs from flote-works to jacobcxdev   ← only in dev/swift-crossplatform
01f18e1 Guard Apple-specific SwiftUI code with !os(Android)     ← merge base
```

**Status: DIVERGED, dev/swift-crossplatform is 1 commit ahead.** The extra commit is the URL rename (from `flote-works` to `jacobcxdev`). `dev/swift-crossplatform` is the canonical branch.

### 3.3 swift-perception

| Item | Value |
|------|-------|
| sqlite-data Package.swift URL | `https://github.com/jacobcxdev/swift-perception` |
| sqlite-data branch ref | `flote/service-app` |
| `jacobcxdev/swift-perception` has `flote/service-app`? | **NO** |
| `jacobcxdev/swift-perception` has `dev/swift-crossplatform`? | **YES** (`d65ffa2`) |
| `flote-works/flote/service-app` local tip SHA | `d65ffa23aed0ee771f3f78d44d60d0b4b3df0895` |
| Package.resolved pinned revision | `9d6298525bec6dbce4ae44e6e26b842a819932c9` |
| Package.resolved pinned URL | `https://github.com/flote-works/swift-perception` (outdated) |
| `dev/swift-crossplatform` commits ahead of resolved PIN | **12** |
| `dev/swift-crossplatform` vs `flote-works/flote/service-app` | **identical tip SHA** (`d65ffa2`) |

**Status: IDENTICAL TIP, just like GRDB.** `dev/swift-crossplatform` IS `flote-works/flote/service-app` — same SHA. 12 commits of work have been done since the Package.resolved was last updated.

### 3.4 swift-sharing

| Item | Value |
|------|-------|
| sqlite-data Package.swift URL | `https://github.com/jacobcxdev/swift-sharing` |
| sqlite-data branch ref | `flote/service-app` |
| `jacobcxdev/swift-sharing` has `flote/service-app`? | **NO** |
| `jacobcxdev/swift-sharing` has `dev/swift-crossplatform`? | **YES** (`3e8a67a`) |
| `flote-works/flote/service-app` local tip SHA | `f503531a2fa0f6149547f742896b7bd23544fd66` |
| Package.resolved pinned revision | `7a31a71be81f618c45b8f5f35d1446d02bbda877` |
| Package.resolved pinned URL | `https://github.com/flote-works/swift-sharing` (outdated) |
| `dev/swift-crossplatform` commits ahead of resolved PIN | **25** |
| `dev/swift-crossplatform` commits ahead of `flote-works/flote/service-app` | **2** |
| `flote-works/flote/service-app` ahead of `dev/swift-crossplatform` | **0** |

`dev/swift-crossplatform` commits beyond `flote-works/flote/service-app`:
```
3e8a67a feat(android): enable FileStorageKey on Android with no-op file monitoring
c0b9bd0 Update dependency URLs from flote-works to jacobcxdev
f503531 Restore upstream platform minimums (...)  ← merge base (flote-works/flote/service-app tip)
```

**Status: DIVERGED, dev/swift-crossplatform is 2 commits ahead.** Includes the URL rename commit plus a substantive Android feature (`FileStorageKey` no-op monitoring). `dev/swift-crossplatform` is strictly ahead — no commits exclusive to `flote-works/flote/service-app`.

### 3.5 swift-structured-queries

| Item | Value |
|------|-------|
| sqlite-data Package.swift URL | `https://github.com/jacobcxdev/swift-structured-queries` |
| sqlite-data branch ref | `flote/service-app` |
| `jacobcxdev/swift-structured-queries` has `flote/service-app`? | **NO** |
| `jacobcxdev/swift-structured-queries` has `dev/swift-crossplatform`? | **YES** (`4975818`) |
| `flote-works/flote/service-app` local tip SHA | `f2f9ba068be53f4d0c9db808a9931543e48820e0` |
| Package.resolved pinned revision | `fb5cc61a4e621c36ae080a94b79fa992a04028f3` |
| Package.resolved pinned URL | `https://github.com/flote-works/swift-structured-queries` (outdated) |
| `dev/swift-crossplatform` commits ahead of resolved PIN | **3** |
| `dev/swift-crossplatform` commits ahead of `flote-works/flote/service-app` | **1** (`4975818 Update dependency URLs from flote-works to jacobcxdev`) |
| `flote-works/flote/service-app` ahead of `dev/swift-crossplatform` | **0** |

**Status: DIVERGED, dev/swift-crossplatform is 1 commit ahead.** Same pattern as swift-dependencies: the extra commit is the URL rename.

---

## 4. Package.resolved Analysis

The `Package.resolved` at `forks/sqlite-data/Package.resolved` pins branch-tracked dependencies to **`flote-works` URLs**, not `jacobcxdev` URLs:

```json
{
  "identity": "grdb.swift",
  "location": "https://github.com/flote-works/GRDB.swift",   ← stale URL
  "state": { "branch": "flote/service-app", "revision": "36dba72a..." }
},
{
  "identity": "swift-dependencies",
  "location": "https://github.com/flote-works/swift-dependencies",  ← stale URL
  "state": { "branch": "flote/service-app", "revision": "45992be..." }
},
{
  "identity": "swift-perception",
  "location": "https://github.com/flote-works/swift-perception",    ← stale URL
  "state": { "branch": "flote/service-app", "revision": "9d62985..." }
},
{
  "identity": "swift-sharing",
  "location": "https://github.com/flote-works/swift-sharing",       ← stale URL
  "state": { "branch": "flote/service-app", "revision": "7a31a71..." }
},
{
  "identity": "swift-structured-queries",
  "location": "https://github.com/flote-works/swift-structured-queries",  ← stale URL
  "state": { "branch": "flote/service-app", "revision": "fb5cc61..." }
}
```

**The `flote-works` GitHub org now returns HTTP 404.** The `flote-works` repositories are no longer publicly accessible. This means:

1. `Package.resolved` is currently stale — the pinned URLs are dead.
2. `Package.swift` references `jacobcxdev` URLs with `flote/service-app` branches that do not exist on GitHub.
3. A fresh `swift package resolve` or `swift build` inside `forks/sqlite-data/` would **fail immediately** with a network error (cannot find branch `flote/service-app` at `jacobcxdev`).

---

## 5. Transitive Dependency Analysis

The internal Package.swift files of the dependency forks also reference `flote/service-app` branches on `jacobcxdev`:

**swift-dependencies** (`dev/swift-crossplatform`'s Package.swift):
```swift
.package(url: "https://github.com/jacobcxdev/combine-schedulers", branch: "flote/service-app"),
.package(url: "https://github.com/jacobcxdev/swift-clocks", branch: "flote/service-app"),
```

**swift-sharing** (`dev/swift-crossplatform`'s Package.swift):
```swift
.package(url: "https://github.com/jacobcxdev/combine-schedulers", branch: "flote/service-app"),
.package(url: "https://github.com/jacobcxdev/swift-dependencies", branch: "flote/service-app"),
.package(url: "https://github.com/jacobcxdev/swift-perception", branch: "flote/service-app"),
```

**swift-structured-queries** (`dev/swift-crossplatform`'s Package.swift) — clean, uses version ranges only:
```swift
.package(url: "https://github.com/jacobcxdev/swift-custom-dump", from: "1.3.3"),
.package(url: "https://github.com/jacobcxdev/swift-dependencies", from: "1.8.1"),
```

**swift-perception** (`dev/swift-crossplatform`'s Package.swift) — clean, uses version ranges only.

The `flote/service-app` branch reference propagates transitively through swift-dependencies and swift-sharing into combine-schedulers and swift-clocks. If the top-level resolution fails, these transitive issues would compound it.

---

## 6. fuse-library Isolation Assessment

The fuse-library's Package.swift at `examples/fuse-library/Package.swift` currently has sqlite-data **commented out**:

```swift
// Deferred forks (not yet needed — add back when targets use them):
// .package(path: "../../forks/sqlite-data"),           // Phase 6 (database)
```

All five affected dependencies (GRDB, swift-dependencies, swift-perception, swift-sharing, swift-structured-queries) ARE wired into fuse-library as local path dependencies:

```swift
.package(path: "../../forks/swift-perception"),
.package(path: "../../forks/swift-dependencies"),
.package(path: "../../forks/swift-sharing"),
```

**Key implication:** When fuse-library resolves these packages, it uses the local filesystem path. It never touches sqlite-data's Package.swift or the remote `jacobcxdev`/`flote-works` URLs. The local path override completely bypasses any branch reference.

Therefore:
- `swift test` in `examples/fuse-library/` — **unaffected by this issue**
- `skip test` from repo root (which delegates to fuse-library) — **unaffected**
- `swift build` in `forks/sqlite-data/` standalone — **would fail**
- CI that builds sqlite-data standalone — **would fail**

---

## 7. Skip Test Relationship

`skip test` operates through the fuse-library example project. The Skip toolchain resolves packages through fuse-library's Package.swift, which uses local path dependencies. sqlite-data is not yet wired in. Therefore skip test currently has **zero dependency** on sqlite-data's internal Package.swift and its branch references.

Once Phase 6 wires sqlite-data into fuse-library (via `.package(path: "../../forks/sqlite-data")`), skip test will resolve sqlite-data through the local path. But sqlite-data's own Package.swift will still attempt to fetch its dependencies remotely using the branch references — and that is where resolution will break unless fixed first.

---

## 8. Summary Table

| Dependency | sqlite-data ref | Branch exists on jacobcxdev GitHub? | Local `dev/swift-crossplatform` vs `flote/service-app` | Package.resolved URL | Action Needed |
|---|---|---|---|---|---|
| GRDB.swift | `jacobcxdev/GRDB.swift@flote/service-app` | NO | Identical tip (same SHA) | `flote-works` (dead) | Change branch to `dev/swift-crossplatform` |
| swift-dependencies | `jacobcxdev/swift-dependencies@flote/service-app` | NO | +1 commit ahead | `flote-works` (dead) | Change branch to `dev/swift-crossplatform` |
| swift-perception | `jacobcxdev/swift-perception@flote/service-app` | NO | Identical tip (same SHA) | `flote-works` (dead) | Change branch to `dev/swift-crossplatform` |
| swift-sharing | `jacobcxdev/swift-sharing@flote/service-app` | NO | +2 commits ahead | `flote-works` (dead) | Change branch to `dev/swift-crossplatform` |
| swift-structured-queries | `jacobcxdev/swift-structured-queries@flote/service-app` | NO | +1 commit ahead | `flote-works` (dead) | Change branch to `dev/swift-crossplatform` |

---

## 9. Root Cause

The current state resulted from a two-step history:

1. **Original state:** sqlite-data's Package.swift referenced `flote-works` URLs with `flote/service-app` branches. The `flote-works` forks were the working forks. Package.resolved was locked to those.

2. **Rename commit (`c153312`):** `Update dependency URLs from flote-works to jacobcxdev`. This correctly updated the organization name in the URLs but did not update the branch name from `flote/service-app` to `dev/swift-crossplatform`. The `jacobcxdev` forks use `dev/swift-crossplatform` as their working branch — `flote/service-app` was never published on `jacobcxdev`.

3. **`flote-works` org went private/deleted:** The `flote-works` GitHub org (HTTP 404) is no longer accessible, making the stale Package.resolved completely non-functional for fresh resolves.

---

## 10. Recommendation

### Fix at Phase 6 Start — Do Not Defer

This is a **blocking issue for Phase 6** and must be fixed before any database work begins. The fix is mechanical and low-risk.

**Required changes to `forks/sqlite-data/Package.swift`:**

Change all five `branch: "flote/service-app"` references to `branch: "dev/swift-crossplatform"`:

```swift
// BEFORE
.package(url: "https://github.com/jacobcxdev/GRDB.swift", branch: "flote/service-app"),
.package(url: "https://github.com/jacobcxdev/swift-dependencies", branch: "flote/service-app"),
.package(url: "https://github.com/jacobcxdev/swift-perception", branch: "flote/service-app"),
.package(url: "https://github.com/jacobcxdev/swift-sharing", branch: "flote/service-app"),
.package(url: "https://github.com/jacobcxdev/swift-structured-queries", branch: "flote/service-app", ...),

// AFTER
.package(url: "https://github.com/jacobcxdev/GRDB.swift", branch: "dev/swift-crossplatform"),
.package(url: "https://github.com/jacobcxdev/swift-dependencies", branch: "dev/swift-crossplatform"),
.package(url: "https://github.com/jacobcxdev/swift-perception", branch: "dev/swift-crossplatform"),
.package(url: "https://github.com/jacobcxdev/swift-sharing", branch: "dev/swift-crossplatform"),
.package(url: "https://github.com/jacobcxdev/swift-structured-queries", branch: "dev/swift-crossplatform", ...),
```

**After updating Package.swift:** Run `swift package resolve` inside `forks/sqlite-data/` to regenerate `Package.resolved` with correct `jacobcxdev` URLs and `dev/swift-crossplatform` branch revisions. Commit both files.

**Also check transitive dependencies:** swift-dependencies and swift-sharing's own Package.swift files also reference `flote/service-app` for combine-schedulers and swift-clocks. Those forks' `dev/swift-crossplatform` branches need to be verified as having the correct branch references in their own Package.swift files as well (or local path overrides in fuse-library will paper over the issue for fuse-library builds, but standalone builds of those forks would also fail).

### Why Not Defer to Phase 7 Cleanup?

1. The `flote-works` org is already returning 404 — the Package.resolved is already broken for fresh checkouts.
2. Phase 6 will wire sqlite-data into fuse-library. A `swift package resolve` will be run, and it must succeed.
3. The fix is a five-line mechanical change with zero semantic risk — `dev/swift-crossplatform` is strictly ahead of `flote-works/flote/service-app` for all affected forks (no content is lost).
4. Deferring creates a trap: any engineer doing a fresh clone and attempting standalone sqlite-data development would hit an unresolvable dependency graph with no obvious fix.
