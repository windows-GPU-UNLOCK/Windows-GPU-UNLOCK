# Issue42: both NVIDIA candidates, one system

The latest request supersedes the opening's3090-only scope. Keep both candidates
in the same issue: reported3090/2204-147D10DE at0:5:0.0 (Windows NVIDIA index1),
and3090Ti/2203-161810DE at0:1:0.0 (index0, primary monitor). PRIME Z690-A/4505/
i9-14900K and IntelA780/86941043 are retained. These are reported mappings, not
firmware ownership or target-execution proof; cross-flash history remains unknown.

The shared graph-only configuration preserves all three physical adapters.
Reordered inventory passes; omitting any adapter refuses. A Microsoft Remote
Display Adapter without a verified identity refuses even with synthetic signed
null/ROOT/SWD metadata. Its Windows status/name does not establish firmware
absence. Do not remove/disable it, another GPU, the iGPU or change cables/settings.

Neither GPU is a qualified unlock target on this platform. Graph-only capture
would observe all adapters; it does not select either for MMIO/release/unlock.
Future action contracts must independently pin BDF/device/subsystem and fresh
firmware paths/owners, not Windows/CUDA index or list order. No unlock sequence,
simultaneous/second-card operation or recovery-display route is established.

Offline reproduction with existing PowerShell only:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-configurations.ps1 -Report -Case 42
```

Expected graph-configuration-v5/Case42, Passed true, PhysicalAdapterPins3,
NvidiaCandidates2, MissingAdapterCasesRefused3, UnknownRemoteCasesRefused3;
target-selection/unlock-sequence/hardware/admission/write flags false.
Return only reviewed graph-configuration.json if reproducing, or a short sanitized
failure. This tests fixtures, not live inventory. Stop on tool/policy/error;
no installs, settings changes, staging or EFI boot. No repeat is needed to confirm
maintainer validation. Shared config/mock staging/fixture PE/source/hash tests pass.

The stock measurements remain inconclusive for unlock state. Preserve the low
samples with the others; their cause has not been established. No new benchmark
or execution of the external toolkit is requested.
