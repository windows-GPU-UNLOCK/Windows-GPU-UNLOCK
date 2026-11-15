# Combined existing resource-file review

This combines the existing production FWSEC parser and captured-driver reader in
one command. It reads the existing successful PROM/DIAG/IMG files, without profile
generation or changes to the compatibility envelope. Driver observation/list membership
is not signature trust, ownership, release, hardware proof or write eligibility.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\test-resource-files.ps1
```
Enter the existing capture folder. Uses Python and LLVM/MSVC already installed on
Windows; if tools are unavailable, stop without installing or changing PATH/settings.
Expected resource-files.json in a new Documents folder. Optional -OutputRoot selects
an existing writable local root. Return only reviewed JSON; keep raw files/backups local.
Located/not-found PROM and observed/missing/invalid driver statuses are useful results.
Stop on error or incomplete result. Do not substitute files, generate a profile, stage,
change firmware/display settings or repeat a capture/boot. No hardware action authorized.

Local validation uses the actual production parser on an empty synthetic PROM, missing
driver data, hash-preservation/privacy checks and existing captured-driver positive/
corrupt/missing/duplicate regressions. Contributor hardware/files were not independently
rerun here. Prefer this combined test for cases needing both checks, not serial repeats.

Preparation consistency: resource preparation now refuses unreviewed ROOT/SWD display identities like graph preparation, rather than silently ignoring them. A signed flag alone is not an exact identity pin. Existing signed LCI pins remain. ROOT/SWD/Punktfunk signed-and-unsigned refusal and LCI positive/negative tests pass. Completed captures remain usable; do not recapture, disable/remove adapters or change settings to pass. No hardware engine change.
