# Windows collector test

**English** | [한국어](COLLECTOR-TEST.ko.md)

This tests the Unicode reader-thread failure reported in #27, #110, #127 and
#130. It runs synthetic checks, then the Windows inventory collector. It needs
Python, Windows and a normal PowerShell window. No administrator access, reboot,
USB, EFI or firmware-setting change is required.

From the downloaded source folder, run this **one command**:

```powershell
powershell -NoProfile -File .\tools\test-collector.ps1
```

If execution policy blocks the script, stop and report the short sanitized
message. Do not change policy, unblock files, add a process bypass, or switch
execution routes to avoid the block. If the script never starts, no result.json
is expected. A source hash or ZIP manifest does not establish publisher trust.

Expected: `Result: PASS`. The script prints the new
`Documents\GPU-Unlock-Collector-Test-<id>` folder. In `inventory.json`, expect
`collection_complete: true`, `assessment.status: not-assessed` and
`can_unlock: false`. No `UnicodeDecodeError` should appear. This does not test
GPU unlock or establish hardware support.

**Send back:** review and attach `result.json` and `inventory.json` from that
folder to your existing issue. State whether a Unicode error appeared. Do not
attach a full system report, firmware images or screenshots containing personal
paths. The collector selects model/version fields and removes device-instance
suffixes; review the files before posting.

If the result is `PARTIAL` or `FAILED`, send `result.json` and `inventory.json`
if present. If no folder was created, paste only the short error message after
removing personal paths. Stop there; no rerun or setting change is needed.

## Contributor confirmation

On 2026-11-01, [the #27 B550M / MSI 1462:5136 reporter](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/27#issuecomment-6558655010)
reported `PASS` without a Unicode error on French-locale Windows 11 Enterprise
build 26100, as a normal user without reboot or settings changes. Reviewed
attachments match collector SHA-256
`1c25e3195222a586108ce8f2b60fa42750f56e927a6c3f4c58839eb8df212a2e`,
both process exits zero, complete inventory and `can_unlock: false`.
This confirms that contributor's reported collector run only; other environments
and GPU unlock remain separate validation.

The [#19 Lenovo 1052 reporter](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/19#issuecomment-6559414071)
also reported PASS without the previous Unicode error on French Windows 11 IoT
Enterprise LTSC build 26100, without administrator rights or settings changes.
Both reviewed attachments match the same collector hash, zero exits, complete
inventory and the expected `2504 / 1043:881d` GPU tuple. This is a second
contributor collector confirmation, not EFI or unlock validation.
# Japanese Windows decoding report (#201)

The shared regression now exercises a real child process with UTF-8 Japanese
inventory and CP932 stderr beginning with byte 0x83, matching the reported
decoding boundary. The Dell 2504/c9741028 identity is synthetic fixture data;
this does not reproduce the owner's machine or establish profile support.
Binary subprocess capture already fixes this path in PR176. The same launcher
runs this regression before reading Windows inventory. Keep Secure Boot enabled;
no firmware route or profile is approved by PASS.

The #201 reporter subsequently encountered an unsigned-script policy block
before execution and stopped as requested. No result file was created and the
Japanese-host collector run remains unverified. The distributed script has no
established trusted publisher/signing route for that policy; this is a delivery
prerequisite, not a request for another inventory run or weaker policy.
