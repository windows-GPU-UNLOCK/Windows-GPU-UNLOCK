# Data-preservation companion for PR #335

This patch is based on contributor head `db5c9209d6f88d6de4a4cbff8b8e3612022e243a`
of [PR #335](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/pull/335).
It fixes bounded offline file-handling defects. It is not approval of the entire
utility, an unlock release, or new hardware evidence.

## Changes

- Synthetic fixture generation refuses existing destinations, stages a new set,
  and preserves an output folder that appears during generation. Logs and
  metadata identify the output as synthetic and ineligible as hardware evidence.
- The GUI generates fixtures in a separate unique folder rather than the
  currently selected hardware-capture directory. Python failures propagate.
- Cache cleanup removes only known archive files created by the current run.
  Existing archives, unrelated files and caller-owned extraction folders survive.
- Existing mismatched or symlinked archives are refused. Downloads use unique
  temporary files and exclusive final-file creation. A failed final copy removes
  only its newly created partial file.
- USB staging enforces explicit opt-in (`-OptIn`), validates removable USB
  targets (`BusType == 'USB'`), rejects system and boot partitions/disks
  (`IsSystem`, `IsBoot`, matching system ESP GUID), and refuses existing
  destination files upfront without overwriting or backup-replacing. Silent probe
  staging from `Deploy-ToUsb` is removed.
- EFI log flush in `GuLogFlush` enforces fail-closed behavior by treating every
  non-success status code (`flush_status != EFI_SUCCESS`) as a logging failure,
  closing the bypass where positive EFI warnings (`EFI_WARN_*`) were ignored.

Hash pins, source parsing and final firmware validation are unchanged. Tests use
fake bytes and mocked network responses, never real firmware downloads.

## Verification

Run the test suites:

```sh
python -m unittest discover -s tools/gpu_unlock_utility -p test_data_preservation.py -v
powershell -NoProfile -ExecutionPolicy Bypass -File tools/gpu_unlock_utility/test_usb_staging.ps1
python -m unittest discover -s tools -p 'test_*.py' -q
python -m unittest discover -s benchmark -p 'test_*.py' -q
python -m unittest discover -s research/profile -p 'test_*.py' -q
```

31 data-preservation, 13 native PowerShell mock regressions, 14 existing tools,
28 benchmark and 101 profile tests pass.
The preservation tests reproduce overwriting/deletion/bypass on the unmodified PR head.
No GPU, CUDA library, EFI, registry, physical USB, boot or security-setting
operation was executed. Existing release manifests were not refreshed.

## Resolution of Safety Blockers

All four safety blockers identified for PR #335 are addressed:
1. **USB staging**: Explicit opt-in enforced; removable USB target validated;
   system/boot partitions and Windows ESP rejected; existing destination files
   refused without overwrite.
2. **Synthetic captures**: Generated in isolated unique folders; no-overwrite
   checks protect existing real captures; labeled explicitly as synthetic.
3. **Cache cleanup**: Cleans only current run's downloaded files and isolated
   temporary extraction folders; unrelated files and caller cache contents survive.
4. **EFI flush warnings**: `GuLogFlush` fail-closed check treats any non-success
   status as logging failure (`flush_status != EFI_SUCCESS`). Regressions covered
   in `test_app.c`, `test_headless.c`, and `test_data_preservation.py`.

The cache, staging, fixture and flush fixes do not establish hardware compatibility,
safe recovery, source authenticity, or the broader PR's claimed performance.
