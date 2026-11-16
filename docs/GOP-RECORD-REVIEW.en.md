# Existing GOP diagnostic records (#2)

The reported Inno3D2782/16e110de metadata (MaxMode14, current15, framebuffer0/0)
is a present GOP without a framebuffer, not evidence of no GOP handle.
The regression transcribes those reported values into the linked patch's
GOPDIAG syntax; it is not a supplied raw hardware log or firmware test.

```powershell
powershell -NoProfile -File .\research\profile\test-gop-records.ps1
```

Uses an existing Python3 application. Expect three tests OK and a PASS line.
No contributor repeat needed; maintainer already ran it. Return only PASS or
a short sanitized failure if reproduced. Missing tools or policy blocks: stop;
no installs, new captures, EFI boot, automatic retries or settings changes.

The reader can inspect an existing text file using review-gop-records.py.
It exports phase/index, numeric shape and classifications, never handles or
framebuffer addresses. Target ancestry, geometry, SetMode/reconnect authority,
hardware proof and write eligibility remain unverified/false. Missing,
duplicate, malformed and out-of-bound observations refuse. Live/partial
framebuffers and non-target records cannot authorize recovery.

Linked Ada PR3/4 were reviewed as source data, not executed. PR3 also connects
all discovered GOPs and ConsoleOut, beyond its target-only SetMode helper.
PR4 treats failed GOP lookup similarly to no live GOP; an arbitrary service
failure is not proof of absence. Neither patch is adopted here. The original
4070 SUPER report and MSI4070Ti research remain distinct from that owner's
reported Inno3D4070Ti result. No general RTX4000 support claim follows.
