# Lenovo1052 next resource capture (issue19)

[한국어](LENOVO-RESOURCE-CAPTURE.ko.md)

The original graph log3533a5c42b911b1eeb2aad94e8b92f5858361278f883bbf61ba36454d03fa4c5
remains incomplete due to gop-info/NOT_READY. Export v3 retained numeric PCI
routing without changing that result: a physical-mode GOP has a device path,
and another pathless GOP lacks mode information. This is not ownership/release
qualification. Direct Windows return from one original boot is contributor-reported.
Do not repeat the graph boot or collect the same log again.

The shared resource engine now pins Lenovo1052/BIOSS0AKT48A/i9-11900K,
NVIDIA2504/1043:881d,segment0/bus1/device0/function0 and sole Windows PCI display
adapter. Manufacturer is exactly LENOVO. Keep the reported DP display/iGPU state
and official ASUS VBIOS-update history unchanged; no factory-VBIOS assumption.

New scope after live identity/resource/callback guards: PCI resource/attribute/
parent observations,16fixed BAR0 DWORDs, one full1MiB PROM window(max262160direct
MMIO reads), loaded firmware-driver image copies from CPU memory, graph capture
and attempted Windows handoff. No GPU/PCI writes, decode enable, detach, reset,
GPU firmware upload/execution or unlock. Reads may have side effects/hang
firmware/display/input/Windows; recovery remains unproven. Existing handoff
disables the EFI watchdog. No automatic reboot/retry/rollback. The existing
generic-probe GOP handling does not grant profile eligibility.

In administrator PowerShell in fresh pinned source, with Python/LLVM on Windows,
Secure Boot already off and an existing FAT32 USB with256MB free:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-resource-capture.ps1 -Machine issue19
```

Type ACCEPT-MMIO only after accepting the new boundary. It verifies actual
machine/current Windows ESP/USB, builds/verifies pinned EFI, rechecks policy/
identity/configuration/media, backs up/verifies the old loader, preserves prior
captures in a renamed archive, then verifies the staged copy. No formatting or
boot-entry writes. Error/mismatch: stop and report the short error with personal
paths removed; do not change settings or bypass checks.

After READY, fully shut down and manually boot the USB ONCE. No Shift keys.
Expect capture then Windows. If Windows has not started within2minutes, power
off, remove USB and use normal Windows Boot Manager. If recovery fails, stop.
Do not repeat, even if capture/refusal is incomplete. After Windows returns,
reconnect USB if needed and run the same command with -Collect. Return only
reviewed report.json from the printed Documents folder and direct/manual Windows
outcome. Keep DIAG/PROM/IMG/EFI/archives/backups local; remove USB afterward.
No profile generation, unlock or second capture is authorized by this test.

Local checks:267generic+36exact-pin native RAM checks, Windows identity/refusal/
staging mocks and source/PE verification. Lenovo synthetic-GUID fixture31744B,
AMD64,zeroimports,NX/dynamicbase,SHA256fd3f4f105d6a3bdcec72dc350bff6169a163e8f4db9674a7f56dd70440573183.
Never boot fixture images. Preparation builds with the actual current Windows
ESP. No physical MMIO or Windows return was tested locally for this case.

Preparation also requires a live observed fully decrypted system volume before build and again before staging. Protection off with encrypted data, unknown/provider failures or changed state is refused. Do not suspend/decrypt/change settings for this test. Existing-file collection remains available without this staging gate.
