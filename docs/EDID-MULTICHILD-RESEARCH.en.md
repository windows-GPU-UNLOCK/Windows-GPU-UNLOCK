# EDID-bound multi-child runtime review

Issue114's returned JSON confirms three children versus an allowed count of two.
The private graph itself has not been independently reviewed. No monitor change
or additional boot is requested.

The non-aggregate GU_HEADLESS_RESEARCH FullConsumers branch already iterates up
to four children, validates their paths/PCI parent and same EDID owner, and
requires secondary children to lack GOP/text consumers. The aggregate fallback
requiring one child is a different preprocessor branch. The generator and local
header previously refused EDID-bound counts above two. Runtime capacity alone
did not justify extending that contract.

The existing shared RAM-only runner now accepts optional --card and --children
selectors, preserving its default matrix and all existing exclusions. For the
baseline, with the already configured host compiler environment:

```text
python -I research/profile/test_local_release.py --card 0x250410de --children 2 --output <new-output-folder>
```

Eight GA106 cases passed locally: bus1/2b, PCI command2/3, EDID/no-EDID. Each
EDID case passed6456 checks; each no-EDID case passed4961. This is existing
two-child production-code behavior on synthetic RAM fixtures, not three-child
validation, vendor firmware execution or contributor hardware evidence.

The shared generator/header now permit one to four non-aggregate children
with or without a bound EDID driver, retaining exact child paths, agent/open
counts, same EDID owner, role/code pins and separate capture agreement. The runtime
also requires the observed child count to equal generated local metadata. Aggregate
counts above two and all five-child configurations still refuse. No identity,
MMIO, vendor transaction, recovery or write qualification is added.

New native GA106 three/four-child matrices passed16 RAM-only cases (two buses,
two PCI command states, EDID/no-EDID). Three-child EDID cases passed7249 checks;
four-child EDID cases passed7956. Four added last-child mutations independently
prove wrong owner, duplicate owner, wrong controller and wrong open count stop
before any EDID/NVIDIA detach, decode enable or exclusive claim. Existing late
path/code/consumer/missing-EDID/partial-stop faults also run.

Recheck existing files with tools/test-existing-captures.ps1 only. The old
count-only refusal can clear if all remaining graph checks pass; other refusals
may surface. capture_count remains for one file; hardware/write flags stay false.
No profile generation, new capture, staging, boot or guard override is authorized.
The actual private three-child graph and physical release remain unverified.
