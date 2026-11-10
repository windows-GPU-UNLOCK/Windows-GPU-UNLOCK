# Existing capture driver-code review

[한국어](DRIVER-CAPTURE-REVIEW.ko.md)

This offline test addresses a gap in the automatic checker: earlier topology
refusal prevents its loaded-driver code checks. It reuses make-profile.py's
loaded-PE bounds, Stop callback range, relocation and code hashing checks on the
latest existing complete capture, independent of profile admission. It never
calls generate(), changes proven.json or grants eligibility.

With Python already on Windows, open ordinary PowerShell in pinned source:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\test-driver-capture.ps1
```
Enter the existing folder containing DIAGnn.TXT and IMGnn.BIN from the reviewed
resource capture. No new capture, compiler, admin access, USB staging or boot.
Return only reviewed driver-review.json from the printed Documents folder.
Keep DIAG/PROM/IMG files and backups local and unchanged.

The report retains capture/code hashes, numeric version/code size, fixed role
and status. It never exports driver paths, raw image bytes, handles, addresses
or parser exception strings. Only exact known NVIDIA GOP and EDID file identities
are inspected. Unknown drivers are not guessed. A missing image or refused PE
remains missing/invalid; do not create substitute files.

listed_nvgop_code compares version plus code hash with the global reviewed-code
list. It does NOT verify ownership, release on this board, signature trust,
machine-specific admission, separate cold boots, transaction or Windows return.
All eligibility flags remain false. One observed fingerprint is not a profile.

If unavailable/invalid, return the report and stop. For an error, send the short
message with personal paths removed. Do not install tools, change configuration,
run profile generation, stage or boot anything to make it pass.
