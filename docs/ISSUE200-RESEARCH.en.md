# Issue200: exact configuration and unknown Meta adapter

The shared graph-only data pins PRIME B550M-A WIFI II / BIOS3636 / 5800X3D /
2216:48973842. This is preparation data, not profile or hardware admission.
The public inventory also contains Meta Virtual Monitor5.3.57.114 with no PCI
identity. Its name/version, even with synthetic signed ROOT/SWD driver metadata,
must not satisfy the machine guard. Three regression cases preserve that stop.
BIOS3621 and subsystem403F1458 are explicitly refused; neither issue84's other
GPU nor issue173's other host establishes this case. Missing Rift connection,
exact card variant and source revision remain unknown; do not infer them.

Offline test with existing PowerShell only:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-configurations.ps1 -Report -Case 200
```

Expected graph-configuration-v4, Passed true, UnknownMetaCasesRefused3 and all
hardware/write/admission flags false. Return only reviewed graph-configuration.json
from the printed Documents folder. It tests fixtures, not current inventory.
Stop on failure/policy block; no installs, settings/adapter/cable changes,
staging, boot or unlock. No alternate firmware recovery display is established.
