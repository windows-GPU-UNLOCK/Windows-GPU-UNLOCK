# Review an existing local driver-envelope change

For #165, keep the original tested checkout, generated profile and receipt intact.
Run this command from the separately extracted pinned review source:

```powershell
powershell -NoProfile -File .\research\profile\test-profile-review.ps1
```

Select the original tested source folder when prompted. The trusted review
script reads the local profile and verifies the existing host receipt/source
bindings. It never executes code from that checkout, rebuilds, stages or boots.
It additionally compares driver version/hash rows from the saved proven.json
with the reviewer source, separately for global, family and card lists.
Only numeric identities and hashes are exported, never evidence strings/paths.
Differences are relative to the reviewer version, not proof of the original
upstream diff. This comparison does not admit a driver or establish safety.

For the disclosed #165 override, expect added 60014/1226b2cb... rows in global
and family/GA106 scope if the saved file matches the disclosure. Other removed
rows may reflect source-version differences. Memory 0x3000 means 12288 MiB.
HardwareIndependentlyVerified, RecoveryVerified, WriteEligible and
DriverEnvelopeComparison.AdmissionGranted remain false.

Return only reviewed profile-review.json from the printed Documents folder.
If old evidence/source no longer matches or anything is unavailable, stop and
send the short sanitized error; do not repair files to pass, regenerate a
profile, rerun host jobs or repeat hardware. No setting/cable changes required.
