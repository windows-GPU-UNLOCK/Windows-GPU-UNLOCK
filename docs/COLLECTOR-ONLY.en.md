# Windows collector-only package

This package contains exactly LICENSE, three existing collector/test source files,
English/Korean instructions, and collector-files.json (file sizes/SHA256). It includes
no EFI images, native executables, firmware assets, GPU experiments, dependencies or
installers. Source names/bytes are transparent; the collector and ten synthetic tests
are reused from PR176. It is not a new compatibility or antivirus verdict.

Leave any quarantined repository archive quarantined. Do not restore it, disable
Defender, add exclusions, rename/repackage to evade detection, or change protection.
No Microsoft false-positive determination or submission result is claimed. If this
minimal package is also blocked, stop and report the threat name and package hash;
do not retry alternate delivery routes or run it. No raw security history is needed.

If normal protection permits download/extraction and you choose to run it, open an
ordinary PowerShell in the extracted folder and use:
```powershell
powershell -NoProfile -File .\tools\test-collector.ps1
```
The helper first runs existing synthetic collector regressions, then reads Windows
inventory. It requires an existing Python application and refuses Windows Store
installer aliases. No installation, elevation, policy/settings changes or GPU/EFI
operations. If script policy/tools block it, stop without changing them.

Expected PASS with collection_complete=true, can_unlock=false. Review and return
only result.json and inventory.json (if produced) from the printed Documents folder.
On PARTIAL/FAILED, return the reviewed small files or short sanitized error and stop;
no automatic hardware retry. Hardware inventory does not establish unlock support.

The package builder uses an exact allowlist and reproducible ZIP metadata; tests
check contents, byte/hash agreement, excluded unrelated files, overwrite refusal and
repeatable archive bytes. Local package/regression success is not Defender approval
or proof that every security product will accept it.
