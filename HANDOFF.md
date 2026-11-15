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

## Commit and push authority

- No explicit commit or push authorization has been established in this conversation. No commit, push, or public GitHub action was performed. Confirm commit/push scope with the caller before doing either.
