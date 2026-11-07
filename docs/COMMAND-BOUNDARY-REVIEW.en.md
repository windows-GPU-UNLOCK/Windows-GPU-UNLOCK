# Existing command-boundary review (#164)

Run from pinned review source, selecting the existing published logs folder:

```powershell
powershell -NoProfile -File .\research\profile\test-command-log.ps1
```

Uses an existing Python3 application, reads only RUN0002-fail.TXT,
RUN0004-ok.TXT and RUN0005-ok.TXT, and exports numeric records and file hashes.
No supplied code executes, and no PCI/GPU/firmware access or settings change occurs.
Return only reviewed command-review.json from the printed Documents folder.
If missing/ambiguous/blocked, stop and return a short sanitized error. Do not
generate new logs, rebuild, repair records or repeat a hardware failure.

Published RUN0002 has started=0 but retained=1 and DMA_live=20612; firmware not
started is not equivalent to no allocations/mappings or fully clean unwind.
RUN0004/5 report transaction result0/safe1/retained0/DMA_live0. They restore
transaction-original command2 while wrapper entry was0. This distinguishes
transaction cleanup from wrapper-entry restoration; it does not establish
that Windows handoff must use0, or prove an independent hardware result.
The local patch also changes timeout default to stock and requires explicit U.
No general compatibility/safety or upstream admission follows from this review.
