# Work handoff

## Goal and scope

- Continue the host-only PCI parent ancestry verification in `Windows-GPU-UNLOCK-discovery`.
- Preserve existing changes in `internal-boot/boot/test_release_aggregate_audit.c` and `research/pci-decode/test-release-parent-audit.py`.
- Complete remaining ancestry depth/root/segment coverage, document the tested limits, obtain an independent review, and inspect the final diff.
- No public GitHub issue/PR/comment, EFI execution, reboot, GPU state change, or ESP/BCD/NVRAM change is authorized.

## Starting state

- Branch: `release/parent-baseline-intake`; starting HEAD: `dc19de9`.
- At intake, the two scoped files above were the only modified tracked files. No root `AGENTS.md`, prior `HANDOFF.md`, or `docs/plans` entry was present.
- Existing source-hash-matched-at-run-time artifacts establish a one-parent default run and a three-hop/two-parent run (`research/pci-decode/build/release-chain-1/{legacy,chain3}`). The latter is a RAM-only command3 aggregate case with root type 8, segment 1, two display children, and 582,654 checks. Current runner changed after these runs to harden generated-capture substitution, so fresh provenance is still required.
- The local shell has Python 3.12 but no discovered Clang or GCC executable at intake; confirm compiler availability before claiming new C runs.

## Current phase: PARTIAL

- Discovery complete; WIP reviewed against `efi-path.h`, `gpu_path.py`, the runner, and existing summaries/logs.
- Completed: hardened generated-capture substitutions (the shared controller prefix occurs `children + 2` times in the aggregate fixture), documented ancestry controls and verification boundaries, and received two independent read-only reviews with no blockers.
- Verification performed: Python `py_compile` and `git diff --check` passed; 180 pure-Python path-generation combinations and five CLI refusal/boundary cases passed. Fresh source builds used a local MSVC 19.44 compatibility launcher for 30 combinations (PCI nodes 2–16 × roots 3/8, two children, segment values 0/1/65535 distributed across the matrix). All 30 executables passed on direct execution, covering 92,237,570 assertions. Generated capture/root/segment/result markers also matched all 30 expected routes. Two separately built mismatch-history executables passed at 3 nodes/root8/segment1 and 16 nodes/root3/segment65535. Outputs are under `research/pci-decode/build/parent-chain-msvc-resume-1/`.
- The Python runner itself exits at the first Clang-specific `freestanding` guard diagnostic under the MSVC compatibility launcher, after building/running the aggregate binary and image checks. Its compile-guard suite and mutation suite therefore did not complete. A native Clang run remains needed for those checks; do not report the full runner or its guard/mutation phase as passed.
- Existing one-parent and two-parent historical artifacts also still pass when their binaries are run directly, but the fresh 30-route matrix is the current-source evidence.
- Final review: capture root/UID markers, PCI path multiplicity, target/location segments, generated target define and parent counts were checked for all 30 depth/root routes plus both mismatch routes (32 total). An independent read-only review reported no blockers; `git diff --check`, Python syntax check, final status and changed-file diff were reviewed. No commit, push, EFI/hardware action, or public GitHub change was made.
- Remaining validation: run the uncompleted compile-guard and mutation suites under native Clang when available. Until then this checkpoint is partial, not a full runner pass. No hardware, EFI, reboot, GPU state, or ESP/BCD/NVRAM verification is implied.
- Tests must remain host-only and use new ignored output paths. Existing build artifacts are evidence and must not be overwritten or removed.

## Cross-project plan checkpoint (2026-11-16)

- Current product objective: make discovery/evidence collection and the route for supported machines easier to use while preserving exact-configuration unlock gates. Universal unlock on arbitrary hardware is not a currently substantiated deliverable.
- Project 5 has 19 cards. Current critical path: reconcile overlapping PR112/PR178 ownership and current-main divergence; agree shared diagnostics/evidence contracts; finish selector/refusal and Windows handoff/recovery contracts; provide a true capture-only beginner flow; establish current-source evidence/host CI; maintain exact profile qualification; perform authorized exact-machine hardware validation separately.
- Current local `main` comparison: `release/parent-baseline-intake` has two branch-only commits and is 30 commits behind upstream `main` at 88961cc. This is route-test/docs evidence only; it has not been merged to main. PR112 is open/draft and reported mergeable; PR177/178 are open and approved at their reviewed heads but DIRTY against old bases; PR188 is merged.
- Immediate safe work completed across the planning/documentation session: expanded EN/KO portability roadmap and Project 5 dependency map; corrected capture-vs-inventory/profile/staging explanations in Start Here and NEW-MACHINE; added bilingual capture-only guidance; marked the entry-point inventory historical. Independent review findings on EN/KO gate parity, branch scope, PR177 status, package/capture-only boundary and new-machine arguments were incorporated. Relative links, roadmap anchors and diff checks passed. The current docs-only diff is still unpublished.
- Open follow-up: owners need to choose and reconcile the contributor-tool integration path. PR112 and PR178 overlap in scope (PR112 is mergeable; PR177/178 conflict with their old bases); native-Clang compile-guard/mutation work is pending; local installer/session notes on the board are not merged implementation. Relevant Project 5 shared-contract, capture-only, core-safety, recovery, profile and aggregate-topology cards received roadmap/evidence notes; their statuses remain unchanged because their acceptance gates remain open.
- Hardware qualification, physical EFI, USB staging, recovery validation and profile widening were not performed or authorized by this checkpoint.

## Integrated roadmap and capture documentation checkpoint (2026-11-17)

- Latest Project 5 snapshot has 19 cards; the reviewed dependency order is documented in `docs/PORTABILITY.en.md` and `docs/PORTABILITY.ko.md`: reconcile PR112/PR178 integration ownership; agree shared contracts; complete core refusal/recovery contracts; close the outstanding native-Clang host gate; simplify capture-only UX; agree reproducible evidence; expand exact profiles; qualify exact hardware; then define package/release and optional sharing.
- Updated EN/KO Start Here, new-machine and entry-point documentation to distinguish Windows inventory, offline capture assessment, generic EFI capture, LOCAL profile/host tests, package build and physical staging. The checked-in `new-machine.ps1` still requires `-Assets`; its first probe branch does not use that data to build/stage the probe, and resume with sufficient captures continues through profile/tests/package unless the user stops. `-StageUnlock` gates USB copy, not package build. A true standalone capture-only frontend is still a planned integration item.
- PR readback: #112 remains open/draft and was reported mergeable; #177/#178 are open/approved at their reviewed heads but DIRTY against recorded bases; #188 is merged. The ancestry commits and README update are on this branch, not main.
- Documentation validation passed: `git diff --check`; 208 relative Markdown link targets resolved across 13 docs and ten roadmap section anchors exist. No code or hardware tests were rerun because this pass changed documentation only.
- Relevant Project 5 integration-contract, capture-only, selector/recovery, evidence, host-CI, release-contract and profile/topology cards received roadmap/next-step notes. Their status fields were preserved because acceptance gates remain open.
- Current working tree has an uncommitted documentation/roadmap diff in `README.md`, `README.ko.md`, `docs/PORTABILITY.{en,ko}.md`, `docs/START-HERE.{en,ko}.md`, `docs/NEW-MACHINE.{en,ko}.md`, `docs/ENTRYPOINT-PLAN.{en,ko}.md`, `docs/COMPATIBILITY.ko.md`, `docs/CONTRIBUTING.ko.md`, and this handoff. Relative-link and section-anchor checks pass. Two independent reviews found no unresolved blocker; prior review findings about implementation-maturity vs work order, stage ordering, PR status, branch scope and capture/package boundaries were corrected. Final diff/status review remains before the authorized documentation commit.

## Commit and push authority

- Earlier caller requests authorized publishing the scoped ancestry changes and committing the subsequent README update. The latest caller approved committing the docs work and updating Project statuses. No additional remote push was requested in this turn; verify the current deploy instruction before pushing the resulting commit.
