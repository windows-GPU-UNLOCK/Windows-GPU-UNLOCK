# Windows monitor device-parent observations

[한국어](MONITOR-PARENTS-TEST.ko.md)

This read-only Windows diagnostic follows monitor device-parent links to Windows
video controllers. It addresses the association gap on hybrid/virtual-display
systems without changing cables, MUX, drivers, firmware settings or power state.
It does not verify physical display routing, preboot GOP ownership or unlock.

Run in PowerShell from the pinned extracted source; no administrator rights,
compiler, Python, USB or reboot are required:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-monitor-parents.ps1
```

Return only reviewed monitor-parents.json from the printed Documents folder.
Expected: numeric active/output-technology observations and associated, unknown,
ambiguous, cycle or hop-limit states. Missing Windows APIs/access can produce
unavailable; that is acceptable. Numeric technology values are not routing proof.
Parent traversal is limited to16hops,32monitors and16adapters. Raw monitor/adapter
instance IDs, names, serials and error messages are never exported. Only matched
PCI vendor/device/subsystem numbers are retained.

Stop after an error or unknown result; return the small report if created, or a
short error with personal paths removed. Do not install anything, change policy,
disable virtual adapters or alter display/firmware settings to make it pass.

Local self-tests cover parent matching, privacy, failed/multiple parents, cycles,
ambiguous adapters, WMI suffix validation and bounds. Local Windows read/report
execution is separate from contributor hardware observations.
