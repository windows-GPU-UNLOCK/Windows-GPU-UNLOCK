# Cross-host JSON evidence numbers (#129)

```powershell
powershell -NoProfile -File .\research\profile\test-json-evidence-hosts.ps1
```

Uses already installed Windows PowerShell5.1 and PowerShell7 (pwsh, or
-PowerShell7 with an existing executable). Runs the actual trusted
Test-GuExactInteger function on JSON tokens: Int32/Int64 integer0/1/2 pass
only their exact expected value; strings, float/scientific tokens, booleans,
null, arrays/objects and out-of-range values refuse.51 checks per host.
Writes json-gates.json to a new printed Documents folder. Expect passed,
host majors5 and7, IntegerType Int32 and Int64 respectively,51 checks each.

Return only reviewed json-gates.json if reproduced. Maintainer already ran
this command; contributor repeat is optional. A missing host, policy block,
timeout or failure stops; report the summary/short sanitized error. Do not
install a host, edit PATH/policy, repair historical receipts, regenerate
profiles or boot anything to clear a failure. No compiler, GPU or EFI access.

Current main already uses the exact integer helper; this adds reproducible
host validation rather than another gate implementation. The separate full
test-evidence.ps1 suite also passed323 checks in each host locally. These are
synthetic/software checks, not historical receipt acceptance or hardware proof.
