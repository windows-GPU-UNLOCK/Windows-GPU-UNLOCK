# ASRock B450M-HDV R4.0 / ASUS TUF RTX3090 evidence review (issue38)

[한국어](ASROCK-B450M-3090-EVIDENCE.ko.md)

This records an exact-case reported success and its bounded review, not a new
shared write profile or universal3090 support. Machine: B450M-HDV R4.0/P10.10,
Ryzen5500,noiGPU, ASUS2204/1043:87b3, reportedVBIOS94.02.42.00.b4,
PCI0000:01:00.0. Owner reports a manual volatile USB run on mainfcf7ab5,
Windows return without display/driver problems. The initial missing capture-root
HANDOFF STOPPED and subsequent owner-run sequence remain part of the history.
No new boot, capture, benchmark or settings change is requested.

Reviewed supplied files:
- profile.json SHA256 b72a45bb4d20db3573cbb65ed76309ab75732855761c6919408ca867c5d48146
- Format2 receipt b9808c56fd496d8eb24ef2ee108802e6fd1f7cf7e2f8779f6e49edd12527be9f
- transaction report6088dfae9132d8cd3f395a55720728ff0df330d8ad9febfd42c4343ac5600c0b
- transcribed GEMM record64bfa5784204af0793ee438d4d6784f70b1d09c9f8f117a8f41115ac9680c5e3

Downloaded bytes match the supplied hashes. Profile/receipt header,PROM,fixtures
and profile-report hashes agree. Receipt's845input rows recompute to its recorded
TreeSha256;22job outcomes match the declared expectations, including two intended
refusals. These are verified document relationships, not independent reruns,
source-byte attestation or physical proof. Uploaded data was never executed.

The transaction text contains one final status0/transaction/attempted1/clean1,
intentSS0=88888888/SS1=8, matching pre-FLR selectors, successful FLR, restored
streaming/coherent masks, PCIcommand3 and BME containment withcommand3/cache300/
pending0. Five asset-cache cleanup lines have devres_released0. The child field
driver_release0 must not be reinterpreted as independent proof about the earlier
wrapper's driver-release stage. Windows return remains owner-reported.

Reported4096^3 GEMM medians: FP16 65.27->118.01TF/s(+80.8028%),
BF16 65.26->118.52(+81.6120%), FP32 21.75->21.32(-1.9770%).
Protocol is a transcription:3warmups/10timediterations,PyTorch2.13.0+cu130,
24GBLLMresidentbothruns. No raw timing series or independent reproduction.
The LLM-prefill/NVMe observation is excluded from unlock-attributed evidence.
No permanent/unattended/restart/sleep/hibernate qualification.

## Source-bound audit procedure (completed; retained for reference)

Use a fresh pinned source folder OUTSIDE the original tested checkout. Do not
copy new files into that checkout or regenerate its profile/test receipt.
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\test-profile-review.ps1
```
At prompt, enter the original tested checkout containing profile-local.h and
research/profile/local/. The tool uses this pinned source's read/hash/parsing
gates against the old data. It never executes code/scripts from that checkout,
compiles/runs tests, stages or accesses GPU/firmware. It reads existing fixture
bytes locally only for hashes, including PROM; nothing is uploaded.

Expected: profile-review.json in a new Documents folder, with header numeric
bus/BAR/root-port pins and existing source/header/fixture/22job binding checks.
Return only reviewed JSON. Raw header/captures/PROM/IMG stay local.
-OutputRoot may select an existing writable local folder. Unknown/failure:
stop; do not regenerate tests/profile, repair files or repeat hardware to pass.
If original files are unavailable, report that; no replacement artifact required.

Local tool checks: actual trusted header parser, duplicate/malformed pins,
missing-evidence refusal,22job shape/privacy and shared output-host cases pass.
The owner has now returned the completed audit below; no qualification/admission
code is changed. No recapture is requested.

Sources: [issue38](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/38),
[existing receipt comment](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/38#issuecomment-6562835517),
[owner's supplied data](https://gist.github.com/AiInfluenceGr/e551b2986888f3dde76fc86496f18ccd).

## Returned source audit and review stage

[Returned audit](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/38#issuecomment-6563360698)
reports HostEvidenceBindingsMatch=true against the original checkout,845 source inputs
and22 host jobs. Header/profile/PROM/tree hashes agree with the earlier supplied files.
Numeric pins: bus1, BAR0 fb000000..fbffffff, root-port device1/function1. These are
exact-case header observations; do not borrow them for another3090/board.
Initial output-root refusal was followed by creating a writable empty local directory;
owner reports originals unchanged and no tested-checkout code executed.

A new local cross-document check on the supplied profile/audit/receipt confirms the
profile's actual byte hash, hash links, source-row tree digest, intended-refusal job
outcomes, replay identity and numeric bounds. Negative mixed-profile/hash/tree/job/
count/duplicate/pin/scope tests pass. This validates relationships in supplied documents;
the original845 source bytes and hardware were not independently read/rerun here.

Optional reproducibility only, using existing copies named profile-review.json,
profile.json and host-test-receipt-Format2.json together in a folder:
```powershell
python -I -B .\research\profile\review-evidence-bindings.py C:\path\to\existing-evidence
```
Expected JSON: status=consistent,845inputs/22jobs and all admission/hardware/write flags
false. No owner repeat/new artifact requested. If reproduced and different, return only
that reviewed small output or short sanitized error, stop, preserve originals. Do not
regenerate tests/profile, recapture, boot or change settings.

Review stage is now exact-machine reported hardware success with reviewed document
bindings and an owner-run source audit, ready for maintainer review of profile admission.
No additional capture/benchmark/inventory is justified by these results. PR188 does not
install/admit a shared write profile or establish permanent/unattended/recovery support.
