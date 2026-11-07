# Windows-only Secure Boot database observations

[한국어](SECUREBOOT-DATABASE-TEST.ko.md)

Run from fresh pinned source in administrator PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-secureboot-databases.ps1
```

This reads the current Secure Boot state and public `db`/`dbx` variable bytes
through Windows. It does not read PK/KEK, modify/enroll/delete keys, change settings,
stage media or execute EFI. No Python, LLVM, download or reboot is required.

Return only reviewed `secureboot-databases.json` from the printed Documents
folder. It contains bounded list/entry counts and matches to four exact public
Microsoft CA certificates. Custom/unrecognized certificate contents, subjects,
owner GUIDs, hashes and raw variables are not exported. `dbx` observations are
separate from `db`; no complete image-revocation or SBAT check is performed.
Unknown/malformed/unavailable data stay unknown, never permission to proceed.

This advances investigation of a future trusted-boot route. It is not proof that
our unsigned EFI is trusted, that any signature will be accepted, or that a GPU
is supported. Keep Secure Boot enabled; no EFI staging/boot or firmware policy
change is authorized. If access/platform support is unavailable, return the
small report and stop. For other errors, report only the short error with
personal paths removed; do not install tools, change permissions/settings or retry hardware.

The parser is tested on synthetic lists, malformed lengths, unknown private
payloads and mocked query failures. Exact public reference recognition was
also tested locally using the official Microsoft certificate files; no owner
certificate/firmware data is included in the repository. `-SelfTest` queries no
firmware. Reported source observations are not hardware qualification.

References: [Microsoft Get-SecureBootUEFI](https://learn.microsoft.com/en-us/powershell/module/secureboot/get-securebootuefi?view=windowsserver2025-ps)
and [Microsoft Secure Boot key guidance](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-secure-boot-key-creation-and-management-guidance?view=windows-11).
The checked public DER fingerprints and source URLs are in
`tools/secureboot-ca-references.json`. Runtime performs no network lookup.
