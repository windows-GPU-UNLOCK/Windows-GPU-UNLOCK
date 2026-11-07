# Existing EDID binding review (#144)

```powershell
powershell -NoProfile -File .\tools\test-existing-edid.ps1
```

Select the existing folder of complete DIAG00/01.TXT captures. Existing Python3
only; -Python may select an installed known-good executable. No IMG/PROM needed.
The reader uses the common complete-graph and binding parsers, supports CRLF,
and reports BY_DRIVER edges for EDID_DISCOVERED and EDID_ACTIVE separately.
Counts are observed edges, not unique driver images. Exported GUID/version is
firmware metadata, not a release fingerprint or verified source identity.

For #144's disclosed EDID_DISCOVERED owner, expect version16,
605ced2c-583b-4171-9311-aa6e146b1a4b, reviewed_mouse_identity_match=false.
That means bound with a different identity, not absent. NoEdidDriver and detach
authorization remain false. It cannot prove whether a driver survived release.
Missing/ambiguous bindings or incomplete captures stop the review.

Return only reviewed edid-review.json from the printed Documents folder.
If unavailable/blocked/failing, stop and return a short sanitized error.
Do not create new captures, relax GU_NO_EDID_DRIVER gates, change settings or
boot firmware. Raw captures, pointers, images and PROM remain private.
Local tests use synthetic ownership data with the reported GUID/version;
they do not independently verify the Dell hardware result or admit2560.
# Issue144 returned owner correction

The second same-build pair's returned metadata identifies
e1ff8a3d-0a1f-49c2-67d3-930bcaee7798/version16 as the EDID_DISCOVERED owner,
with discovered BY_DRIVER1 and active BY_DRIVER0 per file. The coexisting
605ced2c-583b-4171-9311-aa6e146b1a4b/version16 image is not that edge's owner.
This corrects the earlier reported association; presence/version alone is not
ownership. Returned file hashes are contributor observations, not independent
rehashes of private DIAG bytes.

A new synthetic two-image regression reverses the binding-record order and
requires the owner selected by the actual edge, not the first same-version
image. Four test methods pass. The foreign binding remains distinct from no
EDID driver; generation still refuses its identity. First-pair zero counts do
not authorize no-EDID treatment or establish post-release absence. No raw image,
new capture, profile regeneration, BME change or hardware run is requested.

Optional reproduction, existing Python only:
`python -I -m unittest discover -s research/profile -p test_edid_bindings.py`.
Expect four tests OK; return only PASS or a short sanitized failure if reproduced.
Stop on error/tool/policy block without installs or policy changes. The actual
returned metadata is already enough for this correction; no repeat is needed.
