# Portability design and validation gates

[English README](../README.md) | [한국어 README](../README.ko.md)

This is a staged design, **not a declaration of expanded EFI support**. The present implementation and successful-case binaries remain exact-machine profiles. Universal execution across all GPUs or firmware cannot be promised from the available evidence. The product direction is to make discovery and evidence collection broadly usable, then enable unlock only for exact configurations that pass their own gates.

## Separate host portability from GPU support

The original `unlock/port.*` transaction was shaped around a specific RTX 3090 and AMD-display route. This repository has since added several exact profiles and a bounded LOCAL discovery/generation path, but those are distinct layers and evidence classes; the older transaction example below is not a complete inventory of current profile behavior. An ASUS motherboard or AMD CPU is not inherently the unlock algorithm. Intel hosts, other motherboard vendors and additional display topologies can be investigated independently of the GPU transaction. AMD Radeon and Intel discrete targets would need separate unlock implementations; this repository's write path remains NVIDIA-profile-specific.

| Portability layer | Example legacy binding | Capability to develop | Evidence required |
|---|---|---|---|
| Device discovery | GPU BDF `01:00.0` in `GuCheckConfig` and `GuTargetConfig` | Enumerate PCI candidates and require one explicit, unambiguous match | Different segments/BDFs, duplicate candidates and read failures |
| BAR access | `GU_BAR0_BASE`, `BarCheck` descriptor/base checks | Validate descriptor type, size, bounds and alignment; latch the discovered resource | 32/64-bit descriptors, overflow, truncation, relocation and identity rechecks |
| Display isolation | `GuDisplayPath`, `AmdGopParent`, `DisplayCheck` pin one AMD path | Resolve GOP ancestry to the actual PCI device; prove it is separate from the target | Intel/AMD GOPs, console forwarding, malformed paths and target-owned display rejection |
| GPU policy | PCI/subsystem/revision, chip/VRAM/PROM and firmware identities | Reviewed device profiles with fixed provenance and state/selector rules | Identity, PROM, firmware, memory/WPR layout and cold-state mismatch rejection |
| Transaction containment | Ownership, decode restoration, BME, DMA, FLR and cleanup | Preserve guards and bind every phase to the same latched device/profile | Fault injection, timeouts, cleanup failure, retained resources and no retry in the same boot |
| Windows handoff | Return to ASUS firmware, manual no-reset Boot Override | Document verified firmware routes; investigate direct chainload separately | No-reset behavior, failure handling and Windows driver recovery on each platform |

The executable sources are [`port.h`](../unlock/port.h), [`port.c`](../unlock/port.c), [`checks.c`](../unlock/checks.c), [`app.c`](../unlock/app.c), [`ownership.c`](../unlock/ownership.c) and [`vendor/unlock_610.c`](../unlock/vendor/unlock_610.c). In particular, `ConfigCheck` pins additional PCI dwords, while `ColdCheck` and `PromCheck` impose independent state and identity requirements. Removing AMD IDs or changing BDF/PROM constants would leave these other assumptions unresolved.

## Implementation maturity snapshot

This section describes what exists today; it is not a recommended execution sequence. Follow the [integrated work plan](#integrated-work-plan) below for dependency order.

1. **Inventory and international documentation — implemented.** English/Korean entry points, a public Windows inventory, an offline checker for existing captures, a manual compatibility form and explicit evidence limits. These inputs do not authorize unlock.
2. **Generic pre-boot diagnostic discovery — partly implemented.** The profile-less generic read-only probe (`-DGU_PROBE_GENERIC`, [new-machine pipeline](NEW-MACHINE.en.md)) can record NVIDIA display inventory, console graph, PROM and driver images for its bounded observation scope. The Windows inventory, offline checker and generic EFI probe are distinct routes; no single route establishes identity, provenance, recovery or unlock eligibility by itself. Close the contributor gap with an explicitly capture-only, beginner-guided flow, clearer prerequisites/refusals and a safe way to stop after captures without entering profile/package work. Preserve read-only PCI/GOP observation; do not release drivers, change PCI/MMIO, enable bus mastering, allocate DMA or reset a device in this stage. The generic diagnostic still has machine/firmware limitations and may fail to return from EFI.
3. **Per-machine LOCAL profile generation — implemented within a narrow envelope.** `make-profile.py` accepts only coupled GPU/VRAM/driver-code tuples in `research/profile/proven.json`, complete matching captures, and supported console/topology constraints. Generated headers are local and are not reviewed profiles or hardware qualifications. A write-enabled LOCAL build additionally requires the current source-bound host test evidence. Keep discovery/resource observations separate from GPU identity, layout and firmware policy; unknown or ambiguous profiles remain refused. Latch device/resource identity for the transaction and recheck it after ownership changes. A user-edited configuration must not grant write eligibility. Widening the envelope is a separate, evidence-backed profile review, not a consequence of adding PCI-path fixtures.
4. **One new hardware configuration at a time — hardware evidence required.** Prefer host/display portability for the existing GPU family before adding different GPU models. Preserve the old verified case and review positive/negative host tests before any separately authorized hardware experiment.
5. **Broader distribution — evidence required.** Publish a compatibility matrix keyed by EFI/source hashes, GPU/subsystem/PROM/firmware profile, motherboard/BIOS, display route and Windows driver/build. Record reports, mock-tested profiles and hardware-verified profiles as distinct statuses.

## Integrated work plan

This sequence consolidates the current contributor workflow and qualification work. “Complete” at a software stage never substitutes for the separately identified hardware evidence.

| Order | Work package | Exit evidence / dependency |
|---|---|---|
| 0 | Reconcile the contributor-tool integration stack | Choose and document the integration owner for overlapping PR112/PR177/PR178 work; reconcile against current `main`, resolve conflicts, and preserve the already-reviewed contracts from related PRs. Do not advertise branch-only behavior as main/release functionality. |
| 1 | Agree shared contracts | Core/tool owners agree on diagnostics, versioned evidence, ownership, review and release/version boundaries. This unblocks the tool doctor, capture-only separation and manifest work. |
| 2 | Close core safety contracts | After shared diagnostics are agreed, review selector invariants/refusal cases and the Windows handoff/recovery failure matrix. Keep unproven recovery routes explicitly unavailable. |
| 3 | Close the remaining host-validation gate | Run the PCI parent-audit compile-guard and mutation suite under native Clang. The MSVC route executables are useful C/RAM evidence, not a pass of that Clang-specific runner phase. |
| 4 | Simplify safe discovery for users | Separate Windows inventory, offline capture assessment, read-only EFI capture, local-profile generation, package build, and physical staging in the UI and instructions. A future dedicated capture-only route should not need pre-supplied unlock PROM/driver assets (the probe may itself collect PROM/IMG observations), but a pre-boot capture still needs its reviewed compiler, an operator-selected USB and an attended firmware boot; unlock must refuse missing/invalid assets. Make clear that the current `new-machine.ps1` requires an `-Assets` argument and, after captures exist, builds a package on resume even without `-StageUnlock`; only copying unlock assets/package to USB is gated by that switch. Give explicit stages, cancellation, privacy review and recovery limits. |
| 5 | Make evidence reproducible | Agree the capture/evidence schema, provenance and operator-reported outcome fields; then add clean-host CI/artifact verification. Hashes and completed logs are integrity evidence, not proof of origin, boot, unlock or recovery. |
| 6 | Expand exact profiles conservatively | For each proposed GPU/board/BIOS/display route, update one coupled tuple only with reviewed evidence, negative host cases, full source-bound replay and a separate hardware-qualification plan. Preserve existing profiles and refusal behavior. |
| 7 | Qualify one exact hardware route at a time | Only after the necessary approval, record exact source/package/assets, supervised boot outcome, failure/refusal behavior, Windows/display recovery and repeatability as distinct evidence. Host/PE/mock results cannot close this gate. |
| 8 | Release and user-facing package | Define package hashes/source/support scope/recovery caveats from the agreed evidence model. Keep optional result submission downstream, sanitized, previewed and offline-capable. |

### Project 5 work map

Statuses below were read from Project 5 on 2026-11-17. They are planning states, not proof that the listed implementation is in current `main`.

| Roadmap package | Existing Project 5 cards | Current state / immediate work |
|---|---|---|
| Integration and shared contracts | [Agree component ownership and shared interface contracts](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcEU) | **Review.** Reconcile PR112/PR178 ownership and obtain maintainer agreement on diagnostic/evidence contracts. |
| Core safety and handoff | [Audit unlock selector invariants](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcsA); [Define recovery and Windows handoff](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcvo) | **Ready.** Start with source-backed invariants and negative host tests; specify a route-by-route failure/recovery matrix. |
| Contributor discovery flow | [Prerequisite doctor](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcH8); [Capture-only separation](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcMo); [EN/KO walkthrough](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcRs); [First-time capture](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEI4Ew); [Guided installation](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEI-Bk); [Session resume](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEI-GE) | **Review / Awaiting Hardware / In Progress.** Reconcile local notes with public PR heads; separate clean-host acceptance from attended capture/return evidence. |
| Evidence and release reproducibility | [Capture manifests](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcVg); [Compatibility intake](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcf0); [Host CI](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcaM); [Release contract](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcnc) | **Review / Backlog.** Agree provenance/outcome schema, then inventory tests on the integrated tree and tie package claims to exact evidence. |
| Exact machine/profile qualification | [Profile/support matrix](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIc3o); [Aggregate-console/shared GOP](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIc0E) | **In Progress / Review.** Keep synthetic branch results distinct from exact-machine evidence; finish native-Clang guard/mutation checks before calling the runner complete. |
| Research coordination | [AD104 RTX 4070 Ti](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIc70); [EVGA RTX 3090](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIc_o) | **Backlog.** Reconcile existing research records with the core owner before another overlapping experiment. |

Cards whose implementation PR has merged can remain Review when acceptance or maintainer decisions are still open. Do not mark a card Done solely because code, a branch or host tests exist.

### Current integration checkpoint (2026-11-17)

The Project 5 board has shared-contract, tool doctor and capture-only cards in **Review**; selector and recovery-contract cards are **Ready**; profile qualification and installer work are **In Progress**; clean-machine/attended capture cards are **Awaiting Hardware**. Their card text must be reconciled with the current source before treating historical checkpoints as current acceptance.

The current checkout contains its own published `release/parent-baseline-intake` branch (commits `11967aa` and `fe70ce0`), not a merge into `main`. It changes the aggregate release host fixture, its synthetic topology runner and related research/top-level README documentation. It does not supply new mainline behavior or hardware support. The related Project 5 cards remain Review/In Progress. The native Clang compile-guard/mutation phase for this branch's parent-audit runner remains outstanding; see the [PCI decode research log](../research/pci-decode/README.md).

PR112 is still an open draft and reported mergeable in the latest check. PR177 and PR178 are open, approved at their reviewed heads, but report conflicts with their recorded bases; those bases predate the current `main`. PR188 is merged. Reconcile the integration owner and exact commits against current `main` before implementing another overlapping frontend. A board note, review approval, or branch push is not a merge or acceptance completion.

### First-time user route

Use this order in beginner-facing instructions and UI:

1. **Windows inventory or manual report** — no EFI boot; unknown fields stay unknown.
2. **Offline capture assessment** — reads the user's existing files; `candidate` means only that the checked LOCAL route's capture conditions match.
3. **Optional read-only EFI capture** — separate attended firmware action with its own return/hang risk; not required to report a PC.
4. **LOCAL profile generation and source-bound host tests** — only inside the coupled proven envelope; this is still not hardware qualification.
5. **Package build and physical staging** — in the current resumable script, package build follows a successful profile/host-test phase even without `-StageUnlock`; only copying unlock package/assets to USB is gated by that switch.
6. **Exact-machine hardware validation** — separate approval and evidence gate; record Windows/display recovery and repeatability independently.

The current `research/profile/new-machine.ps1` combines steps 3–5 into a resumable command and requires an `-Assets` argument. Its first probe branch does not use those assets to build or stage the read-only probe, but it does require the reviewed compiler, an operator-selected FAT32 USB and a Windows ESP GUID build input. On a later invocation after enough captures exist, it proceeds into profile generation, host tests and package build even when `-StageUnlock` is omitted; that switch controls only copying the unlock package/assets to USB. The docs therefore tell capture-only users to stop after captures. A dedicated capture-only mode can remove the unused unlock-assets and profile/package steps, but still needs a reviewed toolchain, explicit USB destination and a clear attended-boot/recovery boundary. It belongs after the PR112/PR178 integration contract is reconciled.

## Immediate work plan

1. **Resolve contributor-tool integration ownership:** reconcile the P0 shared-contract/doctor/capture-only cards against current `main`, choose PR112 versus the PR178 integration stack, and update stale Project status/evidence. Do not implement a competing launcher before this decision.
2. **Agree shared contracts:** settle diagnostics, versioned evidence, ownership and cross-area review expectations before the doctor, capture-only and manifest changes.
3. **Close the P0 safety gates:** review selector invariants/refusal cases and the Windows handoff/recovery failure matrix with host negative tests. Keep unproven recovery routes unavailable.
4. **Complete the outstanding host gate:** run the PCI parent-audit compile-guard and mutation suite under native Clang. Current MSVC route runs are useful C/RAM evidence but are not a pass of that Clang-specific suite.
5. **Separate beginner stages:** integrate capture-only behavior, actionable tool discovery, cancellation/privacy handling and a clear stop before profile/package/staging. Keep unlock assets separate from read-only capture prerequisites.
6. **Agree evidence schema and reproducibility:** bind exact source/tool/capture hashes and operator-reported boot/Windows outcomes; then inventory existing tests and add only missing clean-host CI checks.
7. **Maintain and expand exact profiles:** reconcile the support matrix and stale evidence, review one coupled hardware tuple at a time, and preserve refusal cases. Synthetic PCI ancestry is software evidence only.
8. **Qualify physical routes separately:** after explicit approval, test one exact current build/profile/route with supervised boot, failure handling, Windows/display recovery and repeatability. Mocks do not close this gate.
9. **Define verified release/package and optional sharing:** after the contracts stabilize, include exact source/package hashes, support scope and recovery caveats; preserve offline use, redaction, preview and user choice.

## Acceptance criteria before expanding a write-enabled EFI

- Unknown device, invalid read, malformed path, unsupported layout or multiple candidates must not arm, write PCI/MMIO, enable BME, release ownership, allocate DMA or trigger FLR.
- Discovery may vary BDF/BAR location, but identity, descriptor bounds and snapshot consistency remain enforced. Changes during the transaction fail closed.
- Display verification must establish independence from the target GPU. Merely finding another GOP or matching a vendor name is insufficient. No-iGPU, multi-GPU and hybrid laptop paths need explicit designs.
- Profile tests cover wrong subsystem/revision, PROM/firmware digest mismatch, invalid cold state, selector changes and memory/WPR bounds. Default and unknown profiles remain non-writing.
- Preserve one-shot confirmation, phase guards, timeout/retry containment, driver ownership, decode restoration, DMA lifetime, FLR cleanup and `STOP / POWER OFF` on unsafe return.
- Preserve the existing negative cases in `test_checks.c`, `test_port.c`, `test_3090_preflight.c` and related transaction/ownership tests. Change expectations only when a replacement invariant is implemented and independently verified.
- A mock pass is software evidence. Hardware support needs exact build/profile provenance, complete cleanup, Windows driver recovery and controlled before/after measurements. Stability and real-application performance require their own evidence.

No hardware support is added by a model-name match, an inventory submission or a successful build. Firmware redistribution rules and existing licenses still apply.
