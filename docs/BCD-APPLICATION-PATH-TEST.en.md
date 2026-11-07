# BCD application-path observation

[한국어](BCD-APPLICATION-PATH-TEST.ko.md)

Use this only when the earlier prerequisite report could not observe the standard
Windows boot-manager path. It queries a typed BCD application-path element rather
than interpreting localized BCDEdit text. It cannot prove recovery or trust.

In administrator PowerShell in the pinned source:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-bcd-application-path.ps1
```
Return only reviewed bcd-path.json from the printed Documents folder. Expected:
standard-windows-uefi, other, missing-or-invalid or unknown. Other paths are never
exported; unknown is acceptable. No compiler, Python, installation, USB or reboot.

Only OpenStore on the current system store, OpenObject for Windows Boot Manager,
and GetElement for ApplicationPath are called. No setters, store import/export,
boot-entry changes, device enumeration, recovery-key access or firmware changes.
No raw paths, object identifiers or provider errors are exported. No policy,
encryption, BCD or Secure Boot changes are authorized by any result.

On error or unknown, return the report and stop. Do not change permissions,
install providers, repair BCD or change settings to make it pass. Recovery and
EFI execution need separate review and informed acceptance.

Local mocks cover the exact three-call contract, strict boolean provider status,
standard/other/missing paths and error redaction. Actual local Windows execution
produced unavailable because OpenStore returned false; successful live BCD reads
remain unverified here.

Microsoft references:
[OpenStore](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/bcd/openstore-bcdstore),
[OpenObject](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/bcd/openobject-bcdstore),
[GetElement](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/bcd/getelement-bcdobject),
[ApplicationPath element](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/bcd/bcdlibraryelementtypes).
