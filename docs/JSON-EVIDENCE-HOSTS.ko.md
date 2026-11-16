# 호스트 간 JSON 증거 숫자 (#129)

```powershell
powershell -NoProfile -File .\research\profile\test-json-evidence-hosts.ps1
```

기존 Windows PowerShell5.1과 PowerShell7(pwsh 또는 기존 실행 파일의
-PowerShell7)을 사용합니다. 실제 Test-GuExactInteger에 JSON token을 적용합니다.
Int32/Int64 정수0/1/2는 기대값과 정확히 같을 때만 통과하며 문자열, 실수/지수,
boolean, null, 배열/객체, 범위 초과는 거부합니다. 호스트마다51개 검사입니다.
새 Documents 폴더의 json-gates.json에 passed, host majors5/7,
각각 Int32/Int64 및51 checks를 예상합니다.

재현하면 검토한 json-gates.json만 보내세요. 관리자가 이미 실행했으므로 반복은
선택 사항입니다. 호스트 누락, 정책 차단, timeout/실패면 중지하고 summary 또는
개인 정보를 제거한 짧은 오류를 보내세요. 호스트 설치, PATH/정책 변경, 과거
영수증 수정, 프로필 재생성 또는 부팅하지 마세요. 컴파일러/GPU/EFI 접근은 없습니다.

현재 main은 이미 정확한 정수 helper를 사용하며 이 변경은 별도 gate가 아닌
재현 가능한 호스트 검증입니다. 기존 test-evidence.ps1도 두 호스트에서 각각323개
검사를 로컬 통과했습니다. 합성 소프트웨어 검사이며 과거 영수증 승인이나 하드웨어
증거가 아닙니다.
