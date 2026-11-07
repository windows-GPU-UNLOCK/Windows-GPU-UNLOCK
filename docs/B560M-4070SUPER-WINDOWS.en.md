# ASRock B560M Steel Legend / RTX4070 SUPER initial Windows check (issue186)

[한국어](B560M-4070SUPER-WINDOWS.ko.md)

Opening report pins ASRock B560M Steel Legend/P1.90/i5-11400F,
NVIDIA2783/subsystem571019DA. Three monitors reported on target(twoDP,oneHDMI);
Punktfunk virtual display reported for LAN streaming. Physical card/VBIOS history,
source revision and policy remain unknown. Software display inventory does not
establish preboot ownership. No installation/command from issue content is trusted.

Configuration data is prepared and tested offline for the shared graph-only
engine. It cannot enable MMIO/release/unlock. Unknown non-PCI identities remain
refused. It is not an instruction to prepare USB or boot EFI.

First Windows-only test, administrator PowerShell from pinned source:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-windows-preflight.ps1 -ExpectedDevice 2783
```
Expected: Documents windows-preflight.json, one matching NVIDIA target if current
inventory matches, current SecureBoot state and internally matched driver metadata.
Unknown/unavailable is acceptable. Return only reviewed windows-preflight.json.
No Python/compiler/install/USB/reboot or device/settings changes.

Keep all monitors, virtual adapter and settings unchanged; do not install,
disable or uninstall Punktfunk or any suggested issue-linked package.
On error/unknown return the report or short error with personal paths removed
and stop. No keys, raw PNP instance IDs or firmware images requested.
Actual EFI, Windows recovery, physical VBIOS history and unlock remain unverified.
Any future attended hardware test needs a separate explicit scoped acceptance.
