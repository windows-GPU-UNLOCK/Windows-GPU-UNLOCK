# Issue196: keep the A4000 installed

Graph-only pins: MSI PRO X870-P WIFI (MS-7E47), BIOS1.A76, Ryzen9800X3D,
3080Ti2208/40811458, A4000 24B0/14AD10DE, AMD13C0/7E471462.
All three reported PCI adapters remain required. No removal, Device Manager
change, cable change or firmware-setting change is requested. An uncabled
A4000 is not proven unowned, and a Windows-disabled iGPU is not a proven
preboot GOP or recovery route. No exact-machine unlock is established.

Optional fixture-only check from the pinned checkout:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-configurations.ps1 -Case 196 -Report
```

Expected PASS; new Documents/graph-configuration.json reports Case196,
PhysicalAdapterPins=3, MissingPhysicalAdapterCasesRefused=3,
A4000Required=true and hardware/write/admission flags false. Share only that
JSON if reproducing; the maintainer already ran it. No hardware is queried,
USB staged or EFI executed. Stop on failure or unexpected true hardware/write
flags; keep settings and cards unchanged. No dependency installation needed.

This prepares exact inventory guards using the common graph-only engine.
It cannot enable MMIO, detach either NVIDIA card, release drivers or unlock.
Future attended work needs reviewed firmware ownership and exact pins plus
its applicable informed acceptance. Generic deep probe multi-NVIDIA guards
remain unchanged. #108's same target subsystem does not transfer its host
or OCuLink topology; neither #110 nor an uncabled A4000 proves a release route.
