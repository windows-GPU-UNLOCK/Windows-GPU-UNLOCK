# X570 AORUS ELITE / RTX3090 FE graph-only research (issue172)

[한국어](X570-AORUS-3090-GRAPH.ko.md)

Exact preparation pins: Gigabyte X570 AORUS ELITE/F41c/Ryzen5800X,
sole PCI display adapter NVIDIA2204/subsystem147D10DE. Owner reports RTX3090 FE,
VBIOS94.02.27.00.0A and two DisplayPort monitors on the card. Flashing history and
collector revision remain unknown; no untouched-factory firmware assumption.
Different X570/3090 cases do not qualify this machine.

Optional new boundary: firmware handle/protocol/open metadata, console variables,
GOP metadata and64-byte PCI headers; USB log and attempted Windows return.
No GPU MMIO/PROM, image dumps, driver release/reset, GPU writes/firmware upload/
execution or unlock. Firmware/display/input or Windows return may hang.
Existing handoff disables the EFI watchdog. Recovery remains unproven and may
need power-off/USB removal/normal Windows Boot Manager. No automatic retry,
reboot or rollback. Exact owner acceptance is required before preparation.

With Python/LLVM already installed on Windows, an existing FAT32 USB with16MB
free and administrator PowerShell in fresh pinned source:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue172
```
Keep both DP connections and settings. SecureBoot must already be off and the
system volume observed fully decrypted. If enabled/unknown/encrypted, stop;
do not change firmware/encryption settings for this test. Missing tools: stop,
do not install for this step. Type PREPARE only if accepting the printed scope.

It verifies live machine/current Windows ESP/USB, builds/verifies the actual
Windows-pinned image, backs up and readback-verifies old USB loader/staging,
rechecks media/configuration/encryption/SecureBoot before staging. Any mismatch,
unknown or error: stop; do not override pins, settings or guards.

After READY only, fully shut down and manually select USB ONCE, no Shift.
Expected: graph capture then Windows. If Windows has not started within2minutes,
power off, remove USB and choose normal Windows Boot Manager. Recovery failure:
stop. Do not repeat even after an incomplete capture or refusal. Back in Windows,
reconnect USB if needed and run the same command with -Collect appended.
Return only reviewed graph-summary.json from the printed Documents folder and
whether Windows returned directly or needed manual recovery. Raw logs/EFI/
backups stay local; remove USB afterward.

All15 data configurations and shared identity/refusal/staging/encryption tests
passed. Shared AMD64 fixture14848bytes,zeroimports,NX/dynamicbase built/PEverified,
SHA2563d476bb7498d28c8f4d6e5a041d8da4b60b4df212e9edc43c2465668cd28f6f6.
Never boot this synthetic-GUID fixture. Actual firmware behavior/Windows recovery
on this board is untested here. Graph evidence cannot establish unlock/profile
eligibility or verify VBIOS history.
