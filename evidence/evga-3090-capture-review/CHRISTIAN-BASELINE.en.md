# Christian Windows baseline test

[한국어](CHRISTIAN-BASELINE.ko.md)

Run `research/profile/collect-christian-baseline.ps1`. Defaults: saved captures `C:\GPU-Unlock\Captures`; unique output directory and ZIP under `C:\GPU-Unlock\Results`. Send the printed ZIP. No administrator access or reboot is required.

The script reads Windows build/boot time, board product, BIOS version, GPU driver/PCI identity and a bounded NVIDIA telemetry query. It hashes the two saved diagnostics without copying their raw contents. Serial numbers, full PNP instance identifiers and raw firmware dumps are excluded. NVIDIA query failure is recorded rather than converted to successful telemetry. No GPU workload, benchmark, tuning, firmware write, EFI execution or unlock occurs. This is a current-configuration baseline, not a performance baseline or Stop-path qualification.

Mock tests pass in PowerShell 7 and Windows PowerShell 5.1: ZIP creation, allowed NVIDIA query arguments, serial/instance exclusion, capture hashes and wrong-GPU refusal before output. Live telemetry is not established by these mocks. Preserve captures and current BIOS settings; on error send the error instead of repeating an EFI.
