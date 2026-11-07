# Issue31 graph evidence review

[한국어](ISSUE31-GRAPH-EVIDENCE.ko.md)

Source: issue31 comment6560657107 and attachment34242809 graph-summary.json,
reviewed 2026-11-01. This is contributor-supplied sanitized evidence, not a
local firmware execution or signed attestation of machine/build provenance.

Both captures declare graph-only scope, exactly one complete=1 footer, one
success status, no incomplete reasons and5,328 records each. DIAG00 raw-log hash:
`d44500fbffd93a39309c7919fdacece69d7f8b38e84cf57feeca3173894329fd`.
DIAG01 hash:
`3128b7968eb3f474219baccf240bcc348d6da13f39a75d78d821826fa1c5ef02`.
The reporter says Windows started automatically without manual recovery; the
reporter subsequently disclosed two accidental USB boots. Preserve them as two
separate observations, without claiming independent full-shutdown provenance.
Do not request another graph boot just to clarify existing evidence.

Both streams report NVIDIA2204/10de:147d at segment0,bus8,device0,function0;
config command bits show memory decode enabled and bus mastering disabled at
capture time. BAR0 is fb000000. One GOP has framebuffer d0000000,1024x768,
stride1024,pixel-format1,info-bytes0x24. Handle addresses differ between logs;
the complete record arrays are not byte-identical. These are observations,
not an atomic or current ownership/resource authorization.

Remaining work: confirm existing run/build association; review graph routing
and driver provenance; prepare a separately scoped resource-capture plan that
checks live exact identity, BDF and resource bounds. No MMIO/PROM, driver release,
unlock, cleanup proof or performance evidence was supplied by this graph test.
Keep the original USB/logs unchanged and do not repeat the graph test.
