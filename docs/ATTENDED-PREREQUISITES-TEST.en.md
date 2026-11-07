# Windows-only attended-plan prerequisites

[한국어](ATTENDED-PREREQUISITES-TEST.ko.md)

This is a prerequisite observation test, not instructions to disable Secure Boot
or authorization for an EFI run. No firmware policy/key, encryption, BCD, cable,
clock or device settings are changed. No USB staging, key recovery, installation,
reboot or EFI execution is performed.

In administrator PowerShell in fresh pinned source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-attended-prerequisites.ps1
```

It reads current Secure Boot state, the system volume's BitLocker protection/
conversion statuses, and the current Windows boot-manager path from a read-only
BCD query. Only GetProtectionStatus/GetConversionStatus are called; recovery
passwords, protector IDs and keys are not queried. The report exports no volume
identifiers, BCD text, exception messages or personal paths. This is BitLocker
provider data, not proof about all encryption products or other volumes.

Return only reviewed `attended-prerequisites.json` from the printed Documents
folder. Unknown/unavailable observations are acceptable and remain blockers.
Protection off with an encrypted volume is not treated as fully decrypted.
A boot-manager path observation does not prove recovery or firmware execution.
No result grants policy-change, EFI staging/boot or unlock permission.

Keep Secure Boot, keys and settings unchanged. If it errors, stop and report the
short error with personal paths removed. Do not disable encryption, change
permissions or install anything for this test. Private recovery material must
stay private and is not requested.

Purpose: establish concrete prerequisites before a maintainer can review any
optional, separately accepted attended research plan. A trusted signed EFI route
is not established by earlier CA/database observations. Any future policy change
would require a distinct informed decision and reviewed recovery/restore plan;
this script neither performs it nor asks you to do it.

Local checks cover decrypted versus suspended/encrypted/failed/unknown states,
non-integer input refusal and boot-manager-path/error redaction. Runtime read/
report was also exercised locally; no boot recovery was tested.

References: [Microsoft GetConversionStatus](https://learn.microsoft.com/en-us/windows/win32/secprov/getconversionstatus-win32-encryptablevolume),
[GetProtectionStatus](https://learn.microsoft.com/en-us/windows/win32/secprov/getprotectionstatus-win32-encryptablevolume),
[BCDEdit /enum](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--enum).

Preparation also requires a live observed fully decrypted system volume before build and again before staging. Protection off with encrypted data, unknown/provider failures or changed state is refused. Do not suspend/decrypt/change settings for this test. Existing-file collection remains available without this staging gate.
