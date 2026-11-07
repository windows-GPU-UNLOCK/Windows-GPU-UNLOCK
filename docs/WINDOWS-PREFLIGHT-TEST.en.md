Run `powershell -NoProfile -File tools/test-windows-preflight.ps1` on Windows. It reads elevation, the Secure Boot query outcome, and display driver provider/manufacturer/version/INF/signature metadata matched internally to each adapter. It omits device-instance IDs, names and exception messages. Unknown Secure Boot remains unknown and never authorizes staging. Review and return only Documents/GPU-Unlock-Preflight-*/windows-preflight.json. Keep preparation stopped; no firmware changes, adapter removal or EFI boot. If it errors, stop and send the short error with personal paths removed. Signature metadata is not proof of adapter type, firmware ownership or unlock eligibility.

Schema2 adds parsed numeric PCI/subsystem tuples and optional `-ExpectedDevice 2489` (NVIDIA vendor10DE). It reports a unique, missing or ambiguous Windows inventory match; this is not firmware ownership, compatibility or permission to stage. Instance suffixes remain excluded. Same output file and stop rules.

## Exact subsystem selection

Optional -ExpectedSubsystem pins the eight-digit PCI subsystem DWORD as well as
-ExpectedDevice. It requires a device pin; mismatches return zero matches and
identical duplicates remain ambiguous. This is inventory matching only, never
hardware qualification or EFI authorization. Issue189 first Windows-only test:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-windows-preflight.ps1 -ExpectedDevice 2206 -ExpectedSubsystem 38961462
```
Expected windows-preflight.json: Target.ExpectedSubsystem=38961462 and MatchCount
reflecting current inventory, plus SecureBoot/driver metadata. Return only reviewed
JSON. Unknown/error: stop and report a short sanitized error; do not change settings,
install anything, stage or boot EFI. Self-tests cover exact/wrong/duplicate subsystem.
