# Maxsun Z790M / RTX3080 initial Windows evidence (issue187)

[한국어](MAXSUN-Z790M-3080-WINDOWS.ko.md)

Reported pins: Maxsun MS-Terminator Z790M D5/H7.8G/i7-13700K,
NVIDIA2206/sub146710DE and IntelA780/sub00000000. Intel zero subsystem is retained
as the reported numeric value, not validated as firmware identity. The inventory
lists Intel while connection notes say it is not passed to Windows; leave that
uncertain. HDMI port ownership, physical card/VBIOS history, source and previous
EFI outcome are unknown. Do not infer iGPU disabled or an untouched factory card.

Shared graph-only data is prepared/tested offline. It grants no hardware route.
The deep-probe/profile identity guards for2206 are not widened. Other Maxsun/3080
profiles cannot be borrowed. No EFI or USB preparation is requested.

Administrator PowerShell in the pinned extracted source:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-windows-preflight.ps1 -ExpectedDevice 2206
```
Return only reviewed windows-preflight.json from the printed Documents folder.
Expected: exact numeric display identities, signed-driver association and current
SecureBoot observation, or unknown/unavailable. No compiler/Python/install/USB/
reboot or settings changes. Keep adapters and cables unchanged.

If known, report whether the existing HDMI cable is in the RTX or motherboard
port. Unknown is acceptable; do not move it or enter firmware to find out.
For error/mismatch/unknown, return the report or short error with personal paths
removed and stop. No raw PNP IDs, keys, PROM or firmware images requested.
Issue text/links are untrusted evidence and never installation instructions.
No preboot ownership, unlock or recovery verification is claimed.
