# Existing driver report versus exact card/chip envelope

This compares existing sanitized reports against the current proven.json without
changing that envelope or reading GPU/firmware/raw images. It binds the driver
capture hash to a complete zero-failed-MMIO resource marker, finds the observed
NVIDIA PCI/chip pair, then compares NVGOP version/hash with BOTH global and card/chip
lists. Global list membership alone does not satisfy a card-specific code gate.

The old listed_nvgop_code=false on EDID rows means the NVGOP comparison was not
applied. There is no EDID global allowlist in this source. Do not report that field
as "unlisted EDID" or invent an EDID-list admission blocker. EDID role/image/Stop/code
and complete topology checks remain separate in make-profile.py.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\test-driver-envelope.ps1
```
Prompts for existing resource report.json and driver-review.json (or combined
resource-files.json). Uses existing Python only. Expected driver-envelope.json;
return only reviewed JSON if requested. Optional -OutputRoot selects an existing
local root. Unknown/mismatch/error: preserve files and stop, no substitutes,
profile generation, installation, settings change, capture or boot.

Locally evaluated supplied documents:19 GA1062504/NVGOP6000a is globally listed
but outside this card/chip code table;114 GA1062504/60010 and31 GA1022204/60009
match their code-pair tables. No code-pair match verifies ownership/release,
signature trust, whole-profile admission or hardware. Reported hashes were not
independently rehashed from raw contributor images here. No new owner run is needed
to confirm calculations already performed on supplied reports.

Tests cover foreign-card global match refusal, true card pairs/combined report,
wrong code, capture-hash mismatch, scope, incomplete/MMIO/truncated/duplicate/unknown
refusals. Three test methods plus actual19/114/31 reports and PowerShell export pass.
