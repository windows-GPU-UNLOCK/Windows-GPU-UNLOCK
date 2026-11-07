# Existing inventory versus source identity scope

Compare an existing collector inventory to the generic probe device list and fixed
profile device/subsystem identities. This never selects a profile, runs Windows
queries or infers physical PCB manufacturer from a flashed subsystem. A fixed-profile
identity match still says nothing about motherboard/BIOS/PROM/topology qualification.

```powershell
powershell -NoProfile -File .\research\profile\test-inventory-source-scope.ps1
```
Enter an existing inventory.json. Existing Python only; no installation/compiler/admin.
Expected source-scope.json; return only reviewed JSON if requested. -OutputRoot may
select an existing writable local root. Unknown/error: stop, preserve files, no new
inventory/capture, settings/VBIOS change, EFI stage/boot or borrowed profile.

Issue22 existing report: physical ASUS TUF OC3070Ti with reported MSI Suprim X VBIOS,
2482/50511462. Same device appears in B660M3070Ti fixed profile but its subsystem is
50521462; the reported B460M DS3H/F8a/10400F is also a different machine.2482 is absent
from generic probe_device_ids. Neither the fixed profile nor automatic probe route is
admitted by these observations. Original ASUS94.04.65.00.3E/current MSI94.04.65.00.2C
history remains owner-reported; no restore/flash experiment is requested.

Three unit methods cover same-device/different-subsystem, exact identity without
machine admission, unknown scope/identity refusal; the actual existing22inventory and
PowerShell export passed locally. This is source-list/document comparison, not hardware
or VBIOS provenance proof. No additional contributor artifact/run is needed to repeat
an already-computed comparison.
