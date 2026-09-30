<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.

## LifeTrack Health — project instructions

> **Reconstructed 29 Sep 2026.** The original repository (branch `phase-2-scaffold`, never
> pushed) and this file's original contents were lost around 23 Sep. The code was rebuilt from
> the v2 blueprint (`~/Downloads/LifeTrack_Health_v2.docx`), the published audit and mechanisms
> artifacts, and session memory. Invariant numbers below follow the ones the audit cited; wording
> is reconstructed, with the audit's six required amendments applied. Where the original text is
> unknown, this is a best reconstruction, not a quotation.

A patient-owned, local-first health record. Flutter app in `app/`; the design reference is
`Design/lifetrack-prototype.html` (a copy of the published prototype — its onboarding and restore
copy predate the claim fixes; the app's wording is authoritative).

### Architecture

- **Plane A** (`lib/src/ai/plane_a/`) — deterministic, on-device Tier 1 insights. Reads records
  only through `RecordAccess` under actor `agent:plane_a` and the patient's 24 h grant.
- **Plane B** (`lib/src/ai/plane_b/`) — photo capture → draft record. Interface only.
- **Plane C** (`lib/src/ai/plane_c/`) — Tier 2 cloud analysis. Dark until Phase 5
  (`DisabledTierPolicy`, `UnavailableCloudClient`). Only `lib/src/app/cloud_escalation_adapter.dart`
  imports it.
- **Consent** (`lib/src/consent/`) — `ConsentStore` is the single authority; `RecordAccess` is the
  only non-patient read path and audits every read and refusal.
- **Storage** — `FileByteStore` (atomic temp→flush→rename) → `SealedStore` (AES-256-GCM frame
  `'LT' ‖ version ‖ nonce ‖ mac ‖ ct`, `{schemaVersion, body}`) under a Keystore/Keychain device key.
- **Vault** (`lib/src/vault/`) — Argon2id → HKDF vault key + login verifier; data key wrapped by
  the vault key and split 2-of-3 (Shamir). Built and tested; **no server exists**, so it is not
  reachable from the UI.

### Invariants

1. Records never leave the phone except in three ways: a Plane C slice on a human tap, backup
   ciphertext, or a **clinical share** (approved by the founder, 30 Sep 2026, for phase 2):
   - 1a. A clinical share is built on the patient's phone, only after the patient approves a
     level for one doctor whose registry-signed device certificate verified on that phone.
   - 1b. It is encrypted to that doctor's device key alone (X25519 + AES-GCM). A relay may carry
     it but never holds a key that opens it, and deletes it after pickup or at grant expiry.
   - 1c. The `clinicalShare` audit entry is written before the bundle leaves (#13).
   - 1d. No screen promises the doctor "keeps no copy": the doctor keeps their own consult note
     and prescription; the app cannot stop a photo. Say "shared records close when access ends".
2. No UI string may assert unreconstructibility (that LifeTrack/the server/anyone cannot read,
   open or access the patient's data) until the offline-guessing oracle is closed by a PAKE or a
   system-generated passphrase. Enforced on claim *subject* by `ui_claims_test.dart`, not by a
   phrase list.
   - 2a. Test-only stand-ins must `throw` in release — never `assert`, which release strips — and
     the guard is checked by a derived test covering every file that mentions `kReleaseMode`.
3. Nothing in `lib/` may be socket-capable; the release manifest has no INTERNET permission.
   Both are tests, so adding either is a visible custody event. Phase 2's relay client will be
   the first exception; it lands with its own test change, in one reviewed commit.
4. Plane C crosses only on a fresh, unspent `HumanAction` bound to the disclosure the patient
   read; the tap is spent synchronously before any `await`.
5. An agent may never create, extend or exercise a grant it was not given. Nothing under
   `lib/src/ai/` calls `ConsentStore.issue`.
6. Personal notes and vitals are local-only by default; backup includes them only on opt-in.
7. The Emergency ID lives outside the vault, is edited only by the patient, holds fixed bounded
   fields, and every unauthenticated read is audited.
8. All patient-facing clinical output — **including the view layer** — goes through the
   `Insight` contract. Screens render Insights; they never compare values with ranges.
9. Tier 1 states position or movement and routes to a person. No diagnosis, no forecast
   (`banned_phrases.dart`); banned output is dropped, never rephrased.
   - 9a. A unit mismatch or missing range is "not checked", never "out of range". Open-ended
     bounds are `null`, never a sentinel.
   - 9b. An unchecked result is never rendered as reassurance; screens never claim more than
     the code does (e.g. the audit log is "never edited by the app", not "cannot be edited").
10. Adult reference intervals are never applied to a child or, where pregnancy shifts them, in
    pregnancy.
11. `authorize` resolves the **stored** grant by id and checks it: patient, grantee actor,
    purpose, scope, validity window, revoked, spent. The token's grantee and purpose must match
    the calling actor and plane.
    - 11a. Plane C holds its own one-time grant, minted at the tap.
    - 11b. A live grant cannot be re-issued with any difference (extension, grantee, scope); a
      finished grant is evicted so re-approval works.
12. No grant exceeds 48 h. Grant ids are patient-scoped. ABDM consent artefacts, when
    integrated (Phase 4), map in as a separate long-lived type with a bounded projection — do not
    widen `ConsentToken` for them.
13. Every read, change, grant, revocation, egress, restore and erasure is audited; the egress
    entry is written before the send.
    - 13a. The audit log is append-only **and durable** (sealed on disk).
14. Proxy consent only for legal dependents; `grantorId` records who granted. (Enforcement is
    P3 — no dependent profiles exist yet.)
15. No doctor capability (e.g. prescribing) before registry verification. On the patient's
    phone this means: no grant to a doctor, and no inbound prescription accepted, unless the
    doctor's device certificate verifies against the pinned registry key.
16. Access levels are presets over data classes plus an optional filter — Summary (default),
    All my reports, Family illnesses. A level never widens `authorize`; the patient may always
    grant less. Results show their age, never "valid" or "expired".

### Rules for working here

- A test whose outcome depends on wall-clock time is not an invariant test. Every clock is a
  parameter; `plane_boundary_test.dart` forbids `DateTime.now()` under `lib/src/ai/`.
- Source-scanning tests must strip comments first (`codeOf` in `test/invariants/source.dart`).
- Never use `google_fonts`; Poppins is bundled in `app/fonts/`.
- Visual direction: warm-grey medical dashboard (black pills, soft 22 px cards, black hero cards,
  lime accent) after a Dribbble reference the user supplied; components are native, in
  `lib/src/ui/widgets/parts.dart`. Lime means "selected / now" only — never a health status.
  Do not add the `shadcn_ui` package: it pulls in `http` and `extended_image` (network-capable).
- Semantic colours are CVD-checked (see `lib/src/ui/theme.dart`); re-measure before changing one.

### Project state (29 Sep 2026)

`flutter analyze` clean; `flutter test` 94 passing, 0 failing; release APK builds unsigned
(51 MB fat APK = 3 ABIs × ~17 MB). Not yet through the review chain.
