# Existing-capture report provenance

Issue114 comment6570205099 says topology_scope cleared, but independently parsed attachments34257674/34257675 still say outside_scope, three children/allowed two. Preserve both observations; this does not establish that either file came from the stated source/run. Do not request another capture or boot.

The v2 launcher records a random run_id, SHA256 of the launcher/checker/generator/envelope, and the exact report.json bytes. It checks source hashes again after execution and refuses if they changed. These are local provenance aids, not an authenticated attestation or proof of hardware/cold boots. A report hash binds the files; it cannot establish that an owner used the intended inputs. Old v1 files remain readable evidence, with unknown source provenance.

From the pinned checkout, using the same existing capture folder:

```powershell
powershell -NoProfile -File tools/test-existing-captures.ps1
```

Expected for the reported three-child input: topology_scope cleared; capture_count remains for one capture; hardware_tested/write_eligible false. Actual private input has not been replayed here. Local test `python research/profile/test_capture_receipt.py` invokes the real launcher twice on an empty fixture, verifies unique run IDs, matching report/source hashes and no private paths. It does not validate the contributor capture.

Return only reviewed report.json and result.json from the single newly printed results folder, together. Result test must be existing-capture-refusal-v2. Optional -OutputRoot selects an existing writable output folder, with no policy/settings changes. Stop if blocked or the source/check fails; keep any result.json and report the short sanitized error. No installs, EFI, new capture, monitor changes or automatic retries.

The interpreter resolver selects the first Application match, matching normal command precedence; it does not combine executable paths. The real-launcher test also exercises multiple resolver matches with a trusted shim, without changing PATH or installing Python. Explicit -Python remains available.
