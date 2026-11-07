# Unsigned graph preparation policy regression

Issues182 and189 report Secure Boot enabled. Their unsigned EFI preparation
remains stopped; no settings change, signing workaround or EFI run is proposed.
The first preparation check formerly compared with false coercively, while
the pre-staging check already required Boolean false. Both now use the same
strict function so integer0 or a false-like string cannot pass the first gate.
No signed/trusted enabled-Secure-Boot route is provided by this change.

Optional offline reproduction from the pinned checkout:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-boot-policy.ps1
```

It uses synthetic values and parses trusted local source to verify both
checkpoints call the strict gate. It never queries firmware or hardware,
stages USB, installs dependencies or changes policy. Expected boot-policy.json
in a new Documents folder: Passed=true, UnverifiedCasesRefused=11,
PreparationCheckpoints=2, MockFalseAccepted=true; policy/hardware/EFI/write
and EnabledSecureBootRouteProvided flags false. MockFalseAccepted concerns
only synthetic data and says nothing about the contributor's actual policy.
Share only that JSON if reproducing; the maintainer already ran it.

Stop on failure or unexpected true policy/hardware/write flags; preserve
settings, no EFI or hardware retry. Existing Windows inventory remains valid
as inventory only. Exact target matching does not override firmware trust.
