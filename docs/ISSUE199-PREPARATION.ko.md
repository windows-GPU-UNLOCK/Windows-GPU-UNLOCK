# 이슈199: 정확한 GA104/Intel 준비

보고된 MSI PRO Z690-A WIFI (MS-7D25), A.A0, i7-12700,
NVIDIA2487/40741458 및 Intel4680/7D251462를 별도 그래프 전용 핀으로
기록합니다. NVIDIA HDMI와 케이블 없는 Intel 어댑터로 펌웨어 GOP 소유권이나
복구를 입증할 수 없습니다. 제공된 PROM 해시와16MiB BAR 상수는 메타데이터이며
독립적으로 확인된 바이트나 소스/빌드 출처가 아닙니다. 펌웨어 덤프, 상수
재생성 또는 접수용 EFI 실행은 요청하지 않습니다.

공통 설정, 모의 준비/백업/읽기 검증/캡처 보존 및 패키지 PE/소스/해시
테스트가 issue199에서 로컬 통과했습니다. 공통 preflight 상태/개인정보
회귀 테스트도 통과했습니다. 데이터로 MMIO/해제/잠금 해제를 허용하지 않습니다.

고정 소스에서 Windows 전용 명령 하나를 실행합니다.

```powershell
powershell -NoProfile -File .\tools\test-windows-preflight.ps1 -ExpectedDevice 2487 -ExpectedSubsystem 40741458
```

새 Documents 폴더의 windows-preflight.json에 SchemaVersion3, 대상 수,
펌웨어 정책, 드라이버 연결 및 제한된 시스템 볼륨 암호화 상태,
HardwareTested=false/WriteEligible=false가 예상됩니다. unknown/unavailable도
괜찮습니다. JSON만 공유하세요. 복구 키, 보호기, 볼륨 ID 또는 장치 접미사는
내보내지 않습니다. 컴파일러, 설치, USB, EFI, 재부팅 또는 설정 변경은
없습니다. 오류 시 중단하고 개인 경로를 지운 짧은 오류만 반환하세요.
통과를 위해 Secure Boot/암호화/화면 설정을 바꾸지 마세요. 별도 검토 그래프
경로를 준비하는 것이며 잠금 해제 프로필이나 참석형 실행 제안은 아닙니다.
Windows 값이 예상과 같아도 소스/펌웨어 소유권과 동의는 별도 단계입니다.
