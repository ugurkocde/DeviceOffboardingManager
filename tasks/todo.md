# v0.3 Release Plan

Branch: `feature/v0.3`
Previous version: 0.2.2

---

## Phase 1: Critical Bug Fixes

These are broken today and must be fixed before any new features.

- [x] **Fix export functions** — Replaced non-existent properties with actual `DeviceObject` class properties.
- [x] **Fix playbook download path** — Load from the module-bundled `DeviceOffboardingManager/Playbooks/` directory instead of downloading from GitHub.
- [x] **Fix BitLocker key retrieval** — Use `$keyIdResponse[0].id` to access first element.
- [x] **Fix Playbook_1 field name** — `lastContactDateTime` -> `lastContactedDateTime`.
- [x] **Fix `$deviceSuccess++` in PSCustomObject** — Extracted counter logic before PSCustomObject.
- [x] **Fix permission scopes** — `Device.ReadWrite.All`, added `BitlockerKey.Read.All`. Kept unused scopes for future phases.
- [x] **Fix stale `$script:parsedDevices`** — Clear on cancel button handler.
- [x] **Fix playbook result columns** — Dynamic column generation from playbook output schema.

---

## Phase 2: Safety & Identity (Core v0.3 Theme)

Addresses wrong-device deletion (Issues #47, #49) and audit requirements (#35).

- [x] **Strict device identity matching** — Replaced risky name-first correlation with Graph ID / exact serial correlation. Name-only fallback is used only when no safer identifier exists and exactly one object matches.
- [x] **Dry run / preview mode** — Before any delete, resolve Graph object IDs and display exact Entra object ID, Intune device ID, and Autopilot identity ID in the confirmation dialog.
- [x] **Search by Entra Device ID** — Added "Device ID" search option (Issue #54). Supports Entra object ID and Entra `deviceId`; delete operations use resolved IDs.
- [x] **Disable-before-delete option** — Added "Disable in Entra ID" action (`PATCH /devices/{id}` with `accountEnabled: false`) as an alternative to immediate deletion.
- [x] **Persistent audit logging** — Timestamped log filenames (e.g., `DOM_20260313_143022.log`). Logs admin UPN, device identifiers, Graph object IDs, actions, success/failure, and sensitive recovery values with `SENSITIVE` audit prefix.

---

## Phase 3: Graph API Improvements

- [x] **Add retry logic with backoff** — `Invoke-GraphRequestWithRetry` handles 429 throttling (reads Retry-After header), 5xx transient errors (exponential backoff), and network-level failures.
- [x] **Update `Get-GraphPagedResults`** — Uses retry wrapper, accepts optional `$Headers` parameter for `ConsistencyLevel: eventual`.
- [x] **Implement batch requests** — `Invoke-GraphBatchRequest` helper: auto-chunks >20 requests, retries failed sub-requests. Used for search (Entra+Intune), offboarding (Entra+Intune+Autopilot per device), and dashboard `$count`.
- [x] **Migrate all v1.0 endpoints to beta** — Zero v1.0 references remaining across main script and all 5 playbooks.
- [x] **Add `$select` to all GET calls** — Every GET endpoint now specifies only the properties accessed downstream.
- [x] **Add `$count` for dashboard statistics** — Single `$batch` call with 13 `$count` sub-requests replaces 3 full-collection fetches + client-side counting. Includes per-OS counts for pie chart. Falls back to full-fetch if `$count` fails.
- [x] **Batch search queries** — Devicename search batches Entra+Intune; serial search batches Intune+Autopilot. Autopilot full-fetch for devicename search hoisted out of per-term loop.
- [x] **Batch offboarding operations** — Per-device batch combines Entra+Intune+Autopilot operations into single `$batch` call.
- [x] **Implement bulk Autopilot deletion** — When 2+ devices selected, uses `deleteDevices` bulk endpoint. Falls back to individual deletion on failure.

---

## Phase 4: New Features

### Offboarding Actions
- [x] **Retire/Wipe before delete** — Added optional pre-offboarding actions: Retire (`POST .../retire`), Wipe (`POST .../wipe`), or Delete-only.
- [x] **Defender for Endpoint offboarding** — Added MDE as a fourth service checkbox (`POST /api/machines/{id}/offboard`). Requires Defender API permission / token support. (Issue #11)
- [x] **LAPS password retrieval** — Displays LAPS password in confirmation dialog alongside BitLocker/FileVault. Uses `GET /deviceLocalCredentials/{id}` with `DeviceLocalCredential.Read.All`. (Issue #13)
- [x] **Multi-Admin Approval awareness** — Detects protected-operation / MAA-style API responses and shows a summary notification when a second approval is required. (Issue #58)

### Search & Display
- [x] **Partial/wildcard search** — Added "Contains" search mode and partial serial support using `startsWith()` / `contains()` where supported, with client-side Autopilot filtering to avoid empty-displayName failures. (Issue #9)
- [x] **Device group membership display** — Shows Entra ID group memberships via `GET /devices/{id}/memberOf` for impact assessment before offboarding.
- [x] **Device compliance state** — Displays `complianceState` from managed device properties in results grid.

### Playbooks
- [x] **Implement Playbook 6: OS-Specific devices** — Filter by specific OS platform.
- [x] **Implement Playbook 7: Outdated OS devices** — Devices not running latest OS version.
- [x] **Implement Playbook 8: EOL OS devices** — Devices running end-of-life OS versions.
- [x] **Implement Playbook 9: BitLocker Key Report** — Audit report of all BitLocker recovery keys.
- [x] **Implement Playbook 10: FileVault Key Report** — Audit report of all FileVault recovery keys.
- [x] **Implement Playbook 11: Corporate Identifier Stale Report** — Lists imported corporate device identifiers and last contact state. (Issue #41)

---

## Phase 5: Code Quality & UX

- [x] **Load playbooks from local filesystem** — Uses the module-bundled `DeviceOffboardingManager/Playbooks/` directory instead of downloading from GitHub at runtime. Eliminates security risk of remote code execution without integrity verification.
- [x] **Full module migration** — Added module manifest, exported `Start-DeviceOffboardingManager`, split private/public source files, moved XAML resources and playbooks into the module package, and kept `DeviceOffboardingManager.ps1` as a compatibility launcher. (Issue #3)
- [x] **Module verification scripts** — Added cross-platform module/package checks and a Windows-only WPF resource smoke test for v0.3 validation.
- [x] **Fix dashboard threading** — Dashboard `$count` path no longer uses thread jobs; fallback full-fetch path runs in the active Graph context.
- [ ] **Fix dashboard card UI blocking** — Card click handlers run synchronous Graph calls. Move to background jobs with loading indicators.
- [x] **Fix search box Enter key** — Added `KeyDown` handler to submit on Enter.
- [x] **Make window resizable** — Main window uses `ResizeMode="CanResize"` with minimum size constraints.
- [ ] **Remove dead code** — Empty handlers / unused style cleanup still needs a final pass.
- [x] **Deduplicate utility functions** — Shared playbook helpers extracted into `PlaybookHelpers.ps1`.
- [x] **Clear client secret after use** — Clears `$AuthDetails.Secret` after `Connect-ToGraph` completes.

---

## Phase 6: Polish (If Time Permits)

- [x] Advanced grid filtering and shift-click range selection (Issue #33)
- [x] Offboarding report generation — HTML audit artifact
- [x] Saved authentication config for service principals (Issue #48)
- [x] Platform filtering on dashboard (Issue #40)
- [x] Autopilot group tag management (Issue #21)
- [ ] Localization / multi-language support (Issue #14)
- [x] Co-management awareness — Detect and warn about co-managed devices

---

## Remaining Product-Level Items

- [ ] **Localization / French translation framework** (Issue #14) — Needs a string-resource architecture before translation can be completed safely.
- [ ] **Signed / packaged distribution** (Issue #60) — Needs a packaging/signing pipeline or maintained signed release artifacts. v0.3 now ships as a module with bundled local playbooks, but the project still needs an official signing/distribution workflow.

---

## Notes

- All Graph API calls should use `beta` endpoints (not v1.0) for richer response data
- Run `feature-dev:code-reviewer` before marking any phase complete
- Each phase should be a separate PR or commit group for clean history
