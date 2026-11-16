# ASRock B450 Pro4 P4.20 / RTX3090Ti reported-success intake (issue190)

Owner reports Ryzen2700/noiGPU,3090Ti220310de/161810de,bus0x0A,24564MiB;
physical brand unknown, no reported flash/crossflash, Parsec software display present.
Two supervised local-profile USB unlock boots reportedly returned directly to Windows
with display working. Reported local profile LOCAL-220310de-161810de-6263592b and22
host jobs; only build/PROM hash prefixes and release0.3.1 snapshot label supplied.
These are reports, not independently verified transaction/cleanup/provenance evidence.
Do not send the owner back through capture, unlock, settings or performance runs.

The shared existing-profile audit has a new synthetic3090Ti/0x5ff4-memory case,
using the actual trusted header parser; it does not run old-checkout code. To review
existing files only, use a fresh pinned folder outside the tested checkout:
```powershell
powershell -NoProfile -File .\research\profile\test-profile-review.ps1
```
Enter the original tested checkout. Expected profile-review.json: source/header/
fixture/host-receipt bindings and numeric pins, with all hardware/admission flags false.
Return that reviewed JSON; additionally existing profile.json, Format2 test receipt and
successful transaction reports may be shared only if already available and sanitized.
No raw PROM/IMG, serials, home paths or partition identifiers. If missing/old format/error,
stop and report unknown/unavailable or short sanitized error; no regeneration or rerun.

Benchmark distinction:140 versus87.5BF16 is60% against a published reference, not an
own-machine matched control.131.7 versus87.5FP16 is50.51% on that same reference basis.
Reported same-protocol decode50.88vs49.08 is3.67%; it is not a GPU tensor/unlock causal
proof. Keep protocol/power/clock/workload/raw-timing limitations explicit. No further
benchmark requested merely to improve this report.

No source/profile admission is changed. Next step is existing evidence/source review,
not inventory. Source audit passing would still be owner-run; local document relationships
and actual physical results must remain separate.

## Returned audit and transaction excerpts (2026-11-01)

Incoming comment6564350941 reports the pinned audit completed against the original
checkout, HostEvidenceBindingsMatch=true,845source inputs/22host jobs, no old code
execution or changed source/capture files. Exact reported pins: bus0A, BAR0fb000000..
fbffffff, root-port device3/function1, segment0, nonaggregate/one child/EDID driver,
chipb72000a1/memory0x5ff4. Initial nonexistent output-root refusal was resolved by
creating the requested existing local directory; no profile/test regeneration reported.

Full returned audit digests:
- Header65c8f00839534b0903e82c66750161eeb0f8b9b780c52eaf4d20af746b8577b5
- PROM6263592b3bc5a698528bfadefdff30ad9f8bc972ad9f09ea7ac8a0cd90404a6d
- Profile375b8cf68603e84f6c48f1dd5f8941d14a97bae08ac63835a492277d44c4459f
- SourceTreec4ffc95407b1695aa203ba1eb0f88bd87aa224f66f24d73e573186eae33d707e

Profile.json and Format2receipt were summarized, not supplied as complete files;
their asserted byte-for-byte hash agreement and22results remain owner reports.
Do not label this the independently recomputed cross-document review performed for38.
The new source audit is more precise than a release label/hash prefixes, but its
original845input bytes and receipt job outcomes were not independently read here.

Existing transaction excerpts report repeated live PROM checks before arming, allfive
asset hashes verified (prefixes only), selectorsSS0target88888888/SS1entry6/target8,
matching pre-FLR selectors, transactionresult0/containment0/started1/quiesced1/fault0/
retained0/maps0/FLR1, FINALstatus0/attempted1/clean1. These are reported log excerpts,
not independently authenticated full logs. Child driver_release0 is not a separate
claim about wrapper release. Windows/display return remains owner-reported.

Profile HardwareTested=false was generated before the two reported physical boots;
it does not retroactively certify those boots and is not a contradiction. Current
stage: exact-case reported success with owner-run source-binding audit/excerpts,
maintainer evidence review; no shared profile admission or independent hardware proof.
No further capture/unlock/benchmark/inventory is justified. Complete existing profile/
receipt/log files, if later voluntarily supplied and sanitized, can be compared locally;
no new run or raw PROM/IMG is required or requested to manufacture that evidence.
