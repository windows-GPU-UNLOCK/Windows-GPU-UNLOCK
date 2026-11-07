# Issue 151: graph preparation boundary

The report identifies X570 AORUS ELITE / F40 / Ryzen 5800X, a headless
Gigabyte RTX 3080 `2216/403F1458` over OCuLink, and a display-connected ASUS
RTX 5080 `2C02/89E01043`. Its three locked benchmark trials are baseline
evidence, not an unlock result. The reported Windows route does not establish
preboot ownership or an OCuLink firmware path.

`graph-configurations/issue151.json` records both exact PCI identities. It
does not list the four software displays as known adapters: their names and
versions do not establish enumerator, signed provider and firmware identity.
Unknown identities, including ROOT/SWD, still stop preparation. Do not remove
adapters or bypass the guard. Configuration data cannot enable MMIO, device
release or unlock. PR118's exact-card deep-read proposal remains separate;
its X570-F machine design cannot be transferred to this board.

From the pinned source checkout, run this optional CPU-only regression:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-configurations.ps1 -Report
```

It reads trusted fixture data and writes a new Documents report. It does not
read hardware inventory, install dependencies, stage USB media or boot EFI.
Expected: PASS, `graph-configuration.json` with `Passed=true`, two physical
adapter pins, six unknown-display refusals, and all hardware/admission/write
flags false. Share only that JSON if reproducing; the maintainer has already
run this test. No new capture is required for this check.

Stop on any failure or unexpected true hardware/admission/write flag. Keep
the report and current settings; no retry involving hardware, reboot or
adapter removal. Machine-specific graph preparation remains pending review
of the unidentified software-display identities; unavailable information is
acceptable and must remain unknown. No attended run is proposed here.
