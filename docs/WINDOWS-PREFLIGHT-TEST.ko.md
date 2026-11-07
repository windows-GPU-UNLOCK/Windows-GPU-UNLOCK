Windows에서 `powershell -NoProfile -File tools/test-windows-preflight.ps1`을 실행하세요. 관리자 권한 여부, Secure Boot 조회 결과, 각 어댑터와 내부적으로 연결한 디스플레이 드라이버 공급자/제조사/버전/INF/서명 메타데이터만 읽습니다. 장치 인스턴스 ID, 이름, 예외 메시지는 제외합니다. Secure Boot 불명은 계속 불명이며 스테이징 허용이 아닙니다. Documents/GPU-Unlock-Preflight-*/windows-preflight.json만 검토 후 보내 주세요. 준비를 중지한 채로 두고 펌웨어 변경, 어댑터 제거 또는 EFI 부팅을 하지 마세요. 오류 시 개인 경로를 지운 짧은 오류만 보내고 중지하세요. 서명 메타데이터는 어댑터 유형, 펌웨어 소유권 또는 잠금 해제 자격의 증거가 아닙니다.

스키마2는 숫자 PCI/서브시스템 ID와 선택적 `-ExpectedDevice 2489`(NVIDIA 공급자10DE)를 추가합니다. Windows 인벤토리의 단일/누락/불명확 일치만 보고하며 펌웨어 소유권, 호환성 또는 스테이징 허용이 아닙니다. 인스턴스 접미사는 계속 제외합니다. 출력 파일과 중지 규칙은 같습니다.

## 정확한 서브시스템 선택

선택적 -ExpectedSubsystem은 -ExpectedDevice와 함께 8자리 PCI 서브시스템 DWORD를
고정합니다. 장치 지정이 필수이며 불일치는 0개, 동일 장치 중복은 모호함으로 남습니다.
이는 인벤토리 일치 확인이며 하드웨어 검증이나 EFI 허가가 아닙니다.189의 첫 Windows 전용 테스트:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-windows-preflight.ps1 -ExpectedDevice 2206 -ExpectedSubsystem 38961462
```
결과 windows-preflight.json에는 Target.ExpectedSubsystem=38961462, 현재 인벤토리의
MatchCount 및 SecureBoot/드라이버 메타데이터가 포함됩니다. 검토한 JSON만 반환합니다.
알 수 없음 또는 오류 시 중지하고 짧은 개인정보 제거 오류만 보고합니다. 설정 변경,
설치, EFI 준비 또는 부팅을 하지 않습니다. 자체 테스트는 일치/불일치/중복을 확인합니다.
