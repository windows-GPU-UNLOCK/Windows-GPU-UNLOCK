# Existing capture collection recovery

This changes the Windows collection host only. Never boot/rebuild/stage/repeat a
hardware run for an output-folder or Python-resolution failure.

The collector resolves exactly one installed Python application, in normal PATH
precedence, even when Get-Command returns several applications. A Windows app
alias/missing/invalid path remains a stop. -Python may name the existing known-good
interpreter. No installation or persistent PATH/settings change is performed.

If Documents output creation fails, choose an existing writable local root with
-OutputRoot. It creates a unique child folder there; it never silently falls back
or writes the result onto the capture USB. Example for graph collection:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue173 -Collect -OutputRoot "$env:TEMP"
```
Resource collection accepts the same -OutputRoot option. Its existing report is
already usable if supplied; do not recollect merely to rename it. Source paths
and capture bytes remain unchanged. Return only the printed graph-summary.json
or report.json after review. Error/unknown: stop, send short error with personal
paths removed; do not alter permissions, protection settings, PATH or source.

Local tests cover multiple applications, scalar/alias/missing refusal, alternate
output, simulated blocked write, capture preservation and error redaction.
The production checker export also ran on synthetic refusal data with issue31
tagging. No owner hardware or Windows recovery was tested here.

Existing-file driver review now uses the same scalar Python resolver and optional -OutputRoot. Return driver-review.json only; no second capture is needed.
