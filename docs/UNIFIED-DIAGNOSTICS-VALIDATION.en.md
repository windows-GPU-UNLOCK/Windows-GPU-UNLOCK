# Unified diagnostics: implementation and validation

Date: 2026-11-02. User entry point: [Start-Capture.cmd](CAPTURE-SETUP.en.md).

This change joins the published PR112 launcher/USB picker, PR177 existing-data
assessment and PR178 graph-only engine. The PR188 command/GOP text readers are
selected automatically for relevant saved logs. Upstream main
`fd8bbea5b1db991805ffcd7ba84e73fa7867bd8a` was merged into the existing graph
branch before integration, preserving its later admission-envelope changes.

## User-visible contract

- Windows observation accepts unfamiliar boards and all observed display
  adapters. Optional, unavailable or inaccessible providers yield useful partial
  results. No compiler or Python is needed for this stage.
- Saved-file review detects capture sets and applicable readers automatically.
  Different capture directories never share image files.
- The session stores one public `report.json`. Paths, raw instance identities,
  partition/media identities and original captures remain local.
- Reopening the launcher rechecks saved bytes and analyzer source before
  reusing a cached report. Source/input/output drift invalidates reuse.
- Generic graph preparation depends on observed capabilities, not motherboard,
  CPU-model, BIOS or issue-number allowlists. Personalisation uses the existing
  packaged graph template; no user compiler installation is required.
- Explicit preparation records an attempt before copying. Completed or
  interrupted attempts are not silently staged again. Collection verifies the
  original source/media/image/receipt and handles an unambiguous drive-letter
  change.
- Collection receipt verification does not attest capture origin or prove the
  identity of the current collection host. Both are explicitly false.
- Python analysis has a 120-second deadline and a combined stdout/stderr
  limit. Timeout, overflow and cancellation clean up only the owned process.
- A reviewed or refused saved capture never dispatches profile generation,
  another hardware capture, a driver release or an unlock.

## Executed checks

All tests ran through Relayward on Windows using the existing toolchain.
PowerShell was Windows PowerShell 5.1.26100.9711. PowerShell 7 was unavailable
at the checked locations and is not claimed as tested.

| Check | Result and scope |
|---|---|
| Generic Windows inventory | 74 assertions; missing providers, mixed/unknown/duplicate adapters, opaque shared parents, import preservation |
| Existing PCI-parent self-test | 41 assertions retained |
| Generic graph handlers | 110 assertions; capabilities, source/inventory/ESP/media drift, cancellation, one attempt, changed drive letter and verified collection |
| Resumable session | 37 assertions; cache integrity, partial results, invalid inputs, atomic state replacement, concurrent-session exclusion and interrupted preparation |
| Bounded native subprocess runner | 40 actual-child assertions; Windows argument quoting, Unicode, simultaneous streams, limits, timeout, cancellation and unrelated-process preservation |
| Tools Python suite | 41 tests, including 27 unified analyzer fixtures |
| Profile Python suite | 143 tests, including saved command/GOP readers and current admission-envelope tests |
| Diagnostic C runner | Default 63 and graph-only 68 assertions; existing probe fixtures and negative compilation guards also passed |
| Three-child LOCAL native replay | 16 combinations across EDID mode, PCI command, bus and memory variants |
| Generated child-count mismatch | Valid three-child evidence with generated count 2 or 4 refused before EDID/NVIDIA stop, decode or claim |
| Compiled guard mutations | Skipped profile verification and removed generated-count verification detected |
| Family/card/firmware compilation | 12 tests |
| LOCAL profile/evidence intake | 354 checks, including 3/4-child EDID/no-EDID cases, aggregate/bounds/type refusals and stale-source receipts |
| Packaged graph template | Personalised bytes matched an independently compiled sample-GUID image |
| Nonboot fixture and source pins | Regenerated, pin/refusal tests passed; source ordering identical under en-US, ja-JP and tr-TR locales |
| Actual batch launcher | Windows observation and offline first-run/resume passed; spaces and Korean characters in paths preserved |
| Retained contributor inputs | Issue166 legacy wrapper and issue169's three refused captures reviewed with original byte hashes preserved; parser-source changes invalidated prior cache keys |

The native release replay explicitly uses synthetic buffers and mocked EFI
services. Its summary records `synthetic_only: true` and `hardware_access:
false`. The ordinary diagnostic C runner now includes the graph-only variant,
so its positive GOP regression is part of the standard invocation.

The retained issue166 log uses lowercase transaction and FINAL markers rather
than the newer command/GOPDIAG format. Its bounded legacy reader now reports
transaction, containment, SetMode and final-handoff observations separately.
It does not infer recovery, unlock or a cached-attribute cause. Unrecognised
text produces an explicit partial observation. Issue114's raw captures were
not present in the retained audit folder; no new raw-capture result is claimed
for that issue.

## Consistency defects resolved during integration

Graph-only observation now records absent or undersized GOP `Mode->Info`
without fabricating dimensions or framebuffer data. Null `Mode` remains an
explicit failure. Fixed-profile diagnostics retain their prior requirement.

The PR177 assessment could recognise nonaggregate three/four-child EDID
topologies while older fixture, compile-time and PowerShell intake gates
refused them. This integration carries the matching fixture/runtime changes
and corrects the remaining PowerShell gate. The actual child count must match
the generated profile; aggregate and out-of-range cases remain refused.
Changing the intake source invalidates prior LOCAL replay receipts.

The graph template and nonboot fixture were refreshed after the GOP change.
The subsequent LOCAL-profile consistency changes altered their source
manifests but produced byte-identical graph binaries:

| Artifact | SHA-256 |
|---|---|
| Graph template | `e7c31ff71ca3834791063d46fcbd5161da5fd6c2b603a2e8fc40d94c083466cb` |
| Nonboot fixture | `487f558711204faeb7fd9af599b1fcd31b98580529f6aee970f3220c91f76ab0` |

## Practical limits

No physical EFI boot, USB staging, GPU-register operation or unlock was
performed during this work. Host/parser/mock checks do not establish recovery
or hardware support on an additional machine.

The EFI route is x64 and requires a uniquely identified internal GPT Windows
ESP, observed firmware/encryption prerequisites and explicit USB selection.
Other hosts retain Windows/saved-file reporting. A policy block before
PowerShell starts cannot produce a session report; the launcher does not
bypass that policy. Native inventory and source hashes are observations,
not hardware attestation or write permission.
