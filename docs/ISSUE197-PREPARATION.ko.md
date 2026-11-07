# 이슈197: MSI B650 정확한 그래프 준비

준비 핀은 MAG B650 TOMAHAWK WIFI (MS-7D75), BIOS1.R3,
Ryzen7800X3D, 2504/397D1462 및164E/7D751462입니다. #114/#136과
다른 구성입니다. 모니터2개는 NVIDIA에 연결되었다고 보고했으며 펌웨어
GOP/CSM은 unknown입니다. 케이블 없는 iGPU의 복구 경로는 입증되지
않았습니다. 빠른 시작 설정은 유지합니다.

공통 오프라인 그래프 테스트에서 이 설정, 모의 USB 백업/읽기 검증/캡처
보존 가드, 패키지 PE/소스/해시 검사가 통과했습니다. 실제 미디어나 EFI는
실행하지 않았습니다. 다음 준비 전제는 시스템 볼륨 암호화 상태이며 캡처나
프로필은 아직 없습니다.

고정 소스에서 Windows 전용 명령 하나를 실행합니다.

```powershell
powershell -NoProfile -File .\tools\test-windows-preflight.ps1 -ExpectedDevice 2504 -ExpectedSubsystem 397D1462
```

새 Documents 폴더의 windows-preflight.json에 SchemaVersion3, 대상 일치
수, SecureBoot, 화면 드라이버 연결 및 제한된 SystemVolumeEncryption 상태가
예상됩니다. 보호 off가 복호화 완료를 뜻하지 않습니다. 확인 불가는 unknown으로
유지합니다. 복구 키, 보호기, 볼륨 ID, 장치 접미사 또는 공급자 오류 문자열을
조회/내보내지 않습니다. JSON만 공유하세요. 컴파일러, USB, 설치, 설정 변경,
재부팅은 필요하지 않습니다. 오류 시 중단하고 개인 경로를 지운 짧은 오류만
반환하세요.

공통 모의 테스트는 보호 off/암호화 상태, 공급자 확인 불가의 개인정보 보호,
복호화 완료 상태를 검사하며 암호화 가드13개도 통과했습니다. 로컬 Windows
내보내기를 확인했으며 기여자 장비 검증은 아닙니다. WriteEligible=false를
유지합니다. 보호 일시 중지/복호화 또는 Secure Boot/CSM/빠른 시작 변경은
하지 마세요. 검토 후 참석형 그래프 전용 계획에도 명시적 범위/동의와 기존
준비 가드가 필요합니다. 인벤토리는 MMIO/드라이버 해제/잠금 해제 허가가
아니며 여기서는 참석형 부팅을 제안하지 않습니다.
