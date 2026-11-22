# ASUS X570-E GAMING / RTX 3090 headless USB evidence (local profile, first X570-E in the registry)

## Provenance and build scope

Contributor-reported results from one machine on 2026-11-22, made with a local profile generated
by `research/profile/make-profile.py` from two read-only probe captures of that machine. They are
not a reviewed machine profile and not a maintainer-operated hardware test. The EFI hashes in
[summary.json](summary.json) depend on that machine's `profile-local.h` and are not expected
hashes for any other machine.

Built from upstream commit `88961cc` with Clang 20.1.8 (LLVM 20.1.8, MSVC freestanding target).
Local, non-upstream diffs are disclosed: three `Join-Path $PWD` to absolute-path fixes in
`research/headless/{build-usb,build-unlock,test-full}.ps1` (PowerShell 5.1 stringifies a UNC
working directory, which .NET APIs reject; the checkout lives on a UNC share), and for the second
recorded run only a cosmetic wrapper console-text change (banner and two success-path strings,
no logic change; the child is byte-identical in both runs).

## Authorship

This report was drafted with AI assistance: an OpenCode agent running a local
Qwen3.8-27B Q4_XL (Unsloth) model through llama-swap — on this very RTX 3090, i.e. the agent
that wrote the report runs on the card it documents. Every hardware claim is real: all steps
(the two probe boots, the 22 host jobs, both unlock boots, the before/after benchmark) were
executed on this physical machine, each one human-initiated and human-checked by the operator.
The AI performed no hardware operations and had no direct access to the stick, BIOS or GPU.

## Machine

ASUS ROG STRIX X570-E GAMING (BIOS 5031, AMI), AMD Ryzen 7 5800X3D (no iGPU), MSI RTX 3090
SUPRIM X 24 GiB (GA102, `10de:2204` / `1462:3882`) at `0000:11:00.0` (the child log prints it in
decimal as `0:11:0.0`). Non-aggregate single-RTX console with two display children
(`ChildCount 2`, `GU_LOCAL_CONSOLE_AGGREGATE 0`) and the AMI EDID driver bound
(`GU_NO_EDID_DRIVER 0`). Secure Boot disabled, Fast Startup disabled, BitLocker off.

| Common GPU/platform item | Validated value |
|---|---|
| Card | MSI SUPRIM X RTX 3090, 24 GiB (GA102) |
| PCI identity | `10de:2204`, subsystem `1462:3882` |
| GPU BDF | `0000:11:00.0` |
| Chip / VRAM register | `0xb72000a1` / `0x6000` MiB |
| BAR0 | `0xfb000000`, 16 MiB |
| PROM SHA256 | `b137489fb2062cbca2a850826d67d2b1193b92690c1f148f91df50758e92ff87` |
| Motherboard / BIOS | ASUS ROG STRIX X570-E GAMING / 5031 |
| CPU | AMD Ryzen 7 5800X3D |
| Recorded Windows / driver | Windows 11 Enterprise 26200 / NVIDIA 616.92 |
| UEFI / Secure Boot | x64 / disabled |
| Selector profile | `entryLatchedSs1Full`; targets SS0 `0x88888888`, SS1 `0x8` |

The VBIOS version string was not extracted from the PROM dump; the PROM SHA256 above is the
recorded identity. The PciIo attribute cache was `0x300` with PCI command `0x0003` at release
time (`BME containment: ... cached=0x300`).

## Recorded hardware runs

Route: headless wrapper/child from a FAT32 USB stick (`GU_USB_MEDIA`, TOSHIBA 8 GB), chosen in
the firmware boot menu (F8). The stick was not made a default boot device.

| Run | Boot | Entry SS0 / SS1 | Result |
|---|---|---|---|
| AUTO000000 | cold boot after a full shutdown | `0x50337103` / `0x6` (latched) | `FINAL status=0 clean=1`, one FLR, Windows direct start; operator observed Windows re-detecting the GPU including the HDMI audio device |
| AUTO000001 | cold boot after a full shutdown (cosmetic local wrapper, child byte-identical) | `0x0` / `0x0` (power-on default) | `FINAL status=0 clean=1`, one FLR, Windows direct start |

Both entry states were accepted by the `entryLatchedSs1Full` profile (`latched_once=1`); the
pre-release cold check found the GPU cold in both runs (a Windows restart on this board resets
the GPU, so the unlock does not survive a restart). Every run ended with
`SS0=0x88888888 SS1=0x8`, WPR2 cleared after FLR, BME off and no retained mappings.
The wrapper log records the NVIDIA GOP detach, decode restore, `verify-complete` and the
Windows `StartImage` chain, all status 0. See [report-excerpt.txt](report-excerpt.txt).

## Measurements

The repository's own cuBLAS GEMM benchmark (`benchmark/run-benchmark.ps1`, n=4096, FP16/BF16/TF32
with FP32 accumulation plus a pedantic FP32 control; median of 3 trials), CUDA 12.6 runtime with
cuBLAS 12.6, driver 616.92 in both states. Locked state: normal reboot without the stick.
Unlocked state: the same session after the AUTO000000 cold boot.

| Mode | Locked TFLOPS | Unlocked TFLOPS | Ratio |
|---|---|---|---|
| FP32 pedantic (control) | 26.71 | 26.45 | 0.99 |
| FP16 tensor / FP32 accumulate | 70.72 | 130.31 | 1.84 |
| BF16 tensor / FP32 accumulate | 70.53 | 133.15 | 1.89 |
| TF32 tensor / FP32 accumulate | 36.34 | 68.17 | 1.88 |

The unlocked FP16 median is 92 % of the 142.3 TFLOPS datasheet rate; the FP32 control is
unchanged within noise, so the tensor-core path is the only affected path.

## Not established

Repeated boots beyond the two recorded cold transactions; warm restarts; sleep and hibernate
resume; the internal-ESP route; any other board or subsystem. Excluded: PROM image, raw probe
and handle-graph logs, driver dumps, partition and disk identifiers.
