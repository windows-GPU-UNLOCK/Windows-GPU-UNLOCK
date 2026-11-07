# One diagnostic workflow

**English** · [한국어](CAPTURE-SETUP.ko.md) · [Project](../README.md)

Open **`Start-Capture.cmd`** in an extracted copy of this source tree. Use the
same launcher when you return with results. It saves one report and remembers
your local session.

Windows observation and saved-file review accept every motherboard and
display-adapter vendor. An unfamiliar board, AMD/Intel adapter, mobile GPU,
software adapter or duplicate card remains useful evidence. NVIDIA
family/profile admission is a separate assessment inside the report.

## Start here

1. Extract the complete source ZIP. Keep `Start-Capture.cmd`, `tools`,
   `research`, `internal-boot` and `deps` together.
2. Double-click **`Start-Capture.cmd`**.
3. If you already have captures, paste their folder when asked. Otherwise press
   Enter. The launcher records available Windows observations and explains the
   next available action.
4. Review and share **`report.json`** from the folder printed in the window.
   The default is `Documents\GPU-Unlock-Diagnostics`.

You can also drop a capture folder onto `Start-Capture.cmd`. Keep related
`DIAGnn.TXT`, `IMGnn.BIN` and `PROM.BIN` files together in their original folders.
The reviewer discovers nested capture sets and keeps their images separate.

**A compiler, USB, administrator window and supported NVIDIA model are not
required to obtain Windows observations.** Python is needed only to parse
saved captures. If it is missing, you still receive the Windows report and a
specific dependency result. LLVM/MSVC are not required to personalise the
included graph-only template.

If Windows policy prevents PowerShell from starting the script, a session
report cannot be created. Preserve the exact error and report it. The launcher
does not change execution policy or use an encoded-command alternative.
Existing files can be reviewed by a maintainer or on an appropriately
authorised analysis machine. Do not change security settings for a diagnostic.

## What happens automatically

| Available evidence | Work performed by the same launcher |
|---|---|
| This Windows machine | Bounded hardware/driver inventory, firmware/encryption observations and display-adapter parent relationships |
| Unknown, mixed or duplicate adapters | All observed adapters retained; opaque per-run node IDs preserve shared ancestry without publishing raw Windows instance IDs |
| Saved diagnostic logs | File validation and hashes, graph observations and the existing strict LOCAL-profile assessment |
| Saved images and EDID records | Relevant NVIDIA code-identity and display-child checks selected automatically |
| Saved wrapper/transaction or GOP text logs | Recognised command-boundary, GOP and legacy transaction/handoff observations reviewed without executing captured code |
| Partial, refused or unsupported captures | Available observations and specific reasons preserved; no automatic request for another EFI boot |
| Unchanged previously reviewed files | Fresh byte/source checks followed by reuse of the verified result |
| A previously prepared graph session | Receipt/media/source checks and collection of existing logs, without staging again |

The public report separates **CollectionHost** from **SavedEvidence**. The PC
reviewing someone else's files is not assumed to be the captured machine.
Receipt agreement binds preparation/media/source; it does not attest capture
origin or verify the current collection host.

The report excludes input-directory paths, raw device-instance IDs, partition
GUIDs, firmware images and arbitrary exception text. It is still your hardware
report: review it before posting. Keep `session.json`, `graph-receipt.json`,
other local receipts and original capture files private.

## Optional: one graph-only EFI observation

The launcher offers this only when the prerequisites are actually observed:

- x64 UEFI Windows and an elevated process;
- Secure Boot disabled and the system volume fully decrypted;
- one unambiguous internal Windows EFI system partition;
- a readable display inventory and matching packaged source/template;
- an explicitly selected, writable, non-system FAT32 USB with stable identity.

Motherboard model, BIOS version, CPU model, GPU vendor and issue number do not
select separate graph implementations. The source, current inventory, Windows
handoff target and USB are bound to this preparation instead.

The preparation screen identifies the USB by drive letter, label, model and
size. Type `PREPARE` only for the displayed device. The workflow personalises
the template's Windows ESP GUID, verifies it, preserves an existing removable
boot loader and rechecks the medium before copying. It does not format the
USB, register a boot entry or restart Windows.

The graph image observes firmware handles/protocol relationships, PCI header
information and available GOP metadata. It does not read GPU MMIO, dump PROM
or loaded images, release a display driver or attempt an unlock. Missing GOP
information is recorded rather than replaced with a motherboard assumption.

After successful preparation, fully shut down and manually select this USB
**once** from the firmware boot menu. No test key is required. The image
attempts to return to the pinned Windows boot loader.

If Windows has not started after two minutes, power off, remove the USB and use
normal Windows Boot Manager. Record whether manual recovery was needed;
recovery is not guaranteed. **Do not repeat an attempted run.**

When Windows is running, reconnect the original USB and reopen
**`Start-Capture.cmd`**. It collects and reviews the existing capture. A changed
drive letter can be resolved through the recorded disk/partition identity.
A different USB, changed EFI/source, incomplete preparation or partial result
does not silently start a new preparation.

ARM, 32-bit and legacy-boot machines retain Windows/saved-file reporting. The
packaged EFI image is x64. Unknown or enabled policy/encryption states remain
explicit reasons why that action is unavailable.

## Resume and dependencies

Reopening the launcher resumes `Documents\GPU-Unlock-Diagnostics`. You do not
need an issue number, several testing scripts or a capture count. Offline
checks can rerun after changed inputs/source without requesting a hardware
repeat.

If Python is outside PATH, select an existing Python 3.10+ executable allowed
by your local policy:

```powershell
.\Start-Capture.cmd -Captures "C:\saved captures" -Python "C:\Python313\python.exe"
```

The command does not invoke the Windows Store alias or install software.
For separate investigations, select a separate local session folder:

```powershell
.\Start-Capture.cmd -SessionRoot "C:\diagnostics\another-session"
```

Keep the session outside the capture folder being analysed. Do not use another
session to repeat a failed EFI attempt.

For saved-file review without querying the current Windows machine:

```powershell
.\Start-Capture.cmd -Offline -NonInteractive -Captures "C:\saved captures" -SessionRoot "C:\diagnostics\review"
```

On a non-Windows analysis host, the same offline engine is available:

```sh
python3 -I -B tools/review_diagnostic_session.py "/path/to/saved captures"
```

This is an offline analysis route, not a workaround for a Windows policy block.

## What the result means

`report.json` contains observations, assessments, provenance hashes, EFI
availability and one next action. A LOCAL-checker `candidate` is a
source/profile assessment, not unlock authorisation. Diagnostic results keep
`hardware_tested` and `write_eligible` false.

A saved-file status of `reviewed` means the analysis finished; individual
stages can still report partial, refused or out-of-scope evidence.

This launcher never calls profile generation, deep GPU probing, firmware asset
preparation or an unlock stage. Specialised handlers and named-machine
configurations remain for maintainers reproducing reviewed tests. New users
start here; the next justified step can be selected from the single report.

Native PowerShell/Python tests and the C diagnostic harness cover unknown and
mixed adapters, duplicate GPUs, missing providers, changed inputs, interrupted
preparation, moved USB letters, corrupt receipts, incomplete logs and source
drift. These are host/parser/mock checks. They do not establish EFI boot,
Windows recovery or GPU unlock on an additional physical machine.

See the [implementation and validation record](UNIFIED-DIAGNOSTICS-VALIDATION.en.md)
for the executed suites and remaining limits.
