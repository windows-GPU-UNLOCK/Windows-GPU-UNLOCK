# 서명되지 않은 그래프 준비 정책 회귀 테스트

이슈182/189는 Secure Boot 활성 상태를 보고했습니다. 서명되지 않은 EFI
준비는 계속 중단합니다. 설정 변경, 서명 우회 또는 EFI 실행을 제안하지
않습니다. 첫 검사는 false 강제 변환 비교를 사용했고 실제 준비 직전 검사는
이미 Boolean false만 요구했습니다. 이제 양쪽이 같은 엄격한 함수를 사용해
정수0이나 false처럼 보이는 문자열도 첫 가드를 통과하지 못합니다. Secure
Boot 활성 상태에서 신뢰된 실행 경로를 제공하는 변경이 아닙니다.

고정 체크아웃에서 선택적으로 오프라인 재현합니다.

```powershell
powershell -NoProfile -File .\research\profile\test-graph-boot-policy.ps1
```

합성 값과 신뢰된 로컬 소스를 사용해 두 지점이 같은 가드를 호출하는지
확인합니다. 펌웨어/하드웨어 조회, USB 준비, 의존성 설치, 정책 변경은
없습니다. 새 Documents 폴더의 boot-policy.json은 Passed=true,
UnverifiedCasesRefused=11, PreparationCheckpoints=2,
MockFalseAccepted=true이며 정책/하드웨어/EFI/쓰기 및
EnabledSecureBootRouteProvided 플래그는 false여야 합니다.
MockFalseAccepted는 합성 데이터에만 해당하며 실제 정책을 뜻하지 않습니다.
재현한다면 JSON만 공유하세요. 관리자는 이미 실행했습니다.

실패하거나 정책/하드웨어/쓰기 플래그가 true이면 중단합니다. 설정을 유지하고
EFI/하드웨어 재시도는 하지 마세요. 기존 Windows 결과는 인벤토리로만
유효하며 정확한 대상 ID 일치가 펌웨어 신뢰 조건을 무시할 수 없습니다.
