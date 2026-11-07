# ASUS B550M-E BIOS4101: inspection-only research plan

[한국어](ASUS-B550ME-POLICY-INSPECTION.ko.md)

Exact case: issue135, ASUS TUF GAMING B550M-E/BIOS4101/Ryzen5600X,
NVIDIA2489/subsystem248910DE. Windows reports SecureBoot enabled, fully decrypted
system volume and typed standardWindowsUEFIpath. These do not prove recovery.

This optional new test closes the actual menu-information gap before any policy
change can be proposed. It is NOT a request to disable SecureBoot or run EFI.
Owner may decline. No automatic reboot/retry/rollback or hardware execution.
No USB is needed; remove test USB media and use normal Windows for this plan.

In fresh pinned source, administrator PowerShell:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-policy-inspection.ps1 -Machine issue135
```
Before typing INSPECT-ONLY, accept the exact new scope: Windows reads PUBLIC
PK/KEK/db/dbx into memory for local hash/size/attribute comparison, and YOU may
manually enter firmware setup ONCE to inspect Boot/SecureBoot/OS Type. No private
signing/recovery keys are read. No settings, key management, encryption, TPM,
CSM, boot entries or policy changes. Firmware/display/input or Windows return may
hang; recovery is unproven and may require power-off/normal Windows Boot Manager.
If recovery fails, stop; do not reset CMOS/TPM/keys or repeat. You can stop before
the manual restart without changing firmware.

The script checks live exact-machine/configuration, enabledSecureBoot,
fullydecrypted system volume and typed Windows path before recording a unique
Documents baseline folder and hash-bound receipt. On any error/unknown/mismatch,
stop and do not enter firmware; do not install/change anything to pass.
Keep baseline.json and inspection-receipt.json private/local, never attach them.

Only after BASELINE READY, if you still accept, manually restart once and press
Delete for ASUS setup. If needed and clearly labelled, F7 selects Advanced Mode.
Inspect Boot > Secure Boot > OS Type without selecting/changing a value. Record
whether the labels match and whether OS Type currently says Windows UEFI mode.
If labels differ or uncertain, stop inspecting. Do not touch Key Management,
SecureBoot Mode, CSM or TPM. Exit via Discard Changes and Exit; cancel any Save
prompt. No save is permitted. Use normal Windows Boot Manager for return.

Back in Windows run the same primary command with -Verify appended. Enter the
original local Documents folder and answer the three YES/NO/UNKNOWN observations.
Return only reviewed inspection-check.json from the new folder. No screenshots,
raw variables, baseline fingerprints or identifiers requested. NO/UNKNOWN is
acceptable; do not enter firmware again to fill a gap.

A matching report compares only current configuration/public variables, enabled
SecureBoot, decrypted volume and Windows path. Owner answers are reported, not
independently proven. Hidden settings, firmware recovery and trust are unverified.
All policy-change/EFI/eligibility flags remain false. No unsigned EFI run follows
automatically; any policy change needs a separate reviewed plan and acceptance.

Local validation: inspection scope/unknown/changed/receipt-tamper mocks,
baseline/native-attribute/early-stop/file-roundtrip tests. No contributor firmware
entry or recovery was exercised. The shared graph EFI is separately built and
verified but is not staged/executed in this plan.

Sources:
[ASUS exact model manual page](https://www.asus.com/uk/motherboards-components/motherboards/tuf-gaming/tuf-gaming-b550m-e/helpdesk_manual?model2Name=TUF-GAMING-B550M-E),
[ASUS SecureBoot FAQ](https://www.asus.com/global/support/faq/1049829/).
FAQ illustrates another board and warns interfaces vary. This test observes
BIOS4101's actual menu rather than assuming those screenshots are exact.
