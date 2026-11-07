# Public boot-policy baseline and comparison (preparation only)

[한국어](POLICY-BASELINE-TEST.ko.md)

This tool supplies the baseline/comparison part of a future reviewed attended
policy plan. It does not supply or authorize that plan. No firmware menu change,
key enrollment/deletion, encryption change, BCD change, USB staging, reboot or
EFI execution is performed. Current preparation still refuses enabledSecureBoot.

Default offline test:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\test-policy-baseline.ps1
```
It uses synthetic states and temporary JSON, with no Windows queries. Expected:
PASS for variable/configuration drift, strict refusals, privacy and roundtrip.
A pass is source behavior only, not physical recovery or firmware evidence.

The separately selected Record/Verify modes are intended only for a complete
reviewed plan. Record requires exact live machine/configuration pins,
SecureBoot enabled, system volume fully decrypted and typed standardWindowsUEFI
boot-manager observation. It reads the PUBLIC PK,KEK,db,dbx variables through
Windows. It does not read private signing keys or recovery keys. Bounded bytes
are hashed in memory and discarded; only hash/size/attributes are kept in the
local baseline.json. Keep that file private/local; never attach it.

Record never overwrites a baseline. Verify reads the original local baseline,
repeats live observations, and compares configuration plus all four public
variable fingerprints/sizes/attributes. Changed/unknown/encrypted/disabled state
cannot yield observations-match. The small policy-check.json omits fingerprints,
raw variables, identifiers and paths. A match means only these observations
match: no recovery, firmware trust, execution, hidden settings or hardware safety
is verified; eligibility stays false. Store integrity/provenance is not attested.
Never use it to bypass another guard.

Local synthetic/refusal/file-roundtrip tests pass. Record/Verify have not been
exercised on the contributor's machine. This is not a request to run either
mode or enter firmware. Exact firmware controls, recovery/restore briefing and
informed owner acceptance are still required before any new hardware boundary.
Stop on any unknown/mismatch/error; do not install/change/repair to pass.

Windows API reference:
[Get-SecureBootUEFI](https://learn.microsoft.com/en-us/powershell/module/secureboot/get-securebootuefi?view=windowsserver2025-ps).

The captured encrypted/protection-off fixture replays a reported Device Encryption state. It is refused before any public-variable query. Whether encryption was automatic or deliberate is not an admission input. The fixture does not verify clear-key/protector provenance or recovery.

Installed SecureBoot metadata confirms that Attributes is a native wrapper with a UInt64 Attributes property, not a plain integer. Baseline normalization accepts that exact type within UInt32 bounds. Local native-wrapper construction, serialization, attribute-drift and overflow-refusal tests pass without reading a firmware variable. A non-elevated local db read was denied; successful live Record/Verify remain untested.
