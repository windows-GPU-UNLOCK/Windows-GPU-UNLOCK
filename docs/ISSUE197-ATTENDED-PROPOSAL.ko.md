# 이슈197: 동의를 기다리는 준비된 그래프 범위

반환 schema3 보고서는 Secure Boot 비활성, 복호화 완료/0%, 정확한
2504/397D1462 및164E/7D751462 PCI 장치를 기록합니다. 보고된 Windows
전제이며 부팅 전 소유권이나 복구 증거는 아닙니다. 추가 인벤토리는 불필요합니다.
핀은 MSI MAG B650 TOMAHAWK WIFI (MS-7D75), BIOS1.R3,7800X3D와
두 어댑터입니다. 알 수 없는 ID 거부는 유지합니다. 공통 스크립트에 로컬
Windows ESP 개인화, FAT32 USB 데이터 디스크 검사, 로더 백업/해시/읽기
검증, 정책/암호화 재확인, 캡처 보존/반복 금지 및 요약 수집이 구현되어 있습니다.
실제 ESP GUID는 로컬에서 얻으며 공개할 필요가 없습니다.

제안하는 새 하드웨어 범위는 참석형 그래프 전용 EFI1회입니다. 펌웨어
핸들/프로토콜/열기 관계, GOP 모드 메타데이터, 콘솔 변수6개, 노출된 PCI-I/O
핸들의64바이트 PCI 헤더를 읽습니다. USB 로그를 쓰고 기존 복귀 코드처럼
EFI watchdog을 끄며 정상 Windows Boot Manager 복귀를 시도합니다.
GPU MMIO/PROM/이미지 덤프, 분리, 리셋, GPU 쓰기/펌웨어 실행, 잠금 해제
또는 펌웨어 변수 변경은 없습니다.

펌웨어/화면/입력이 멈추거나 Windows 시작이 실패할 수 있습니다. 케이블 없는
iGPU는 검증된 대체 화면이 아닙니다. 복구는 입증되지 않았습니다. 제안하는
중단은2분 내 Windows가 시작하지 않으면 전원 끄기/USB 제거/정상 Windows
Boot Manager 사용이며 복구 실패 시 중단합니다. 자동 재부팅/재시도/롤백,
설정/케이블/빠른 시작 변경 및 불완전한 결과 후 재사용은 없습니다.

실행 절차 전에 소유자가 정확한 범위와 위험에 명시적으로 동의해야 합니다.
예: ACCEPT-197-GRAPH로 답변. 잠금 해제 허가가 아닙니다. 그전에는 EFI
준비/부팅을 중단합니다. 이 문서에는 하드웨어 실행 명령이 없습니다.
선택적 CPU/파일 전용 재현 명령은 하나입니다.

```powershell
powershell -NoProfile -File .\research\profile\test-graph-offline.ps1 -Machine issue197 -PackagedFixture
```

예상 graph-build-test.json은 issue197 선택, 설정/모의 준비 pass,
FixtureOnly=true 및 하드웨어/쓰기 false입니다. 재현한다면 JSON만 공유하세요.
픽스처를 준비/부팅하지 마세요. 오류 시 중단하고 설치/설정 변경을 하지 마세요.
관리자 검증 확인을 위한 반복은 필요하지 않습니다.

로컬 검증: 새14848바이트 AMD64 sample-GUID 이미지, imports0,
NX/dynamic-base, SHA7974eb71bfd46eec67672d31ee437d34b1da1c248082f7b0fc25179ff8765b52,
패키지 템플릿 바이트 일치, 소스/GUID/범위/해시/거부, 전체 설정 픽스처,
모의 백업/읽기 검증/캡처 보존, 엄격한 정책, 암호화13개 및 요약7개 통과.
샘플 GUID 이미지는 기여자 Windows에 고정된 빌드가 아니므로 부팅하면 안 됩니다.
실제 USB 준비나 EFI 실행은 없었습니다. 향후 동의된 실행의 반환 자료는
graph-summary.json과 Windows 직접/수동 복귀 여부이며 원본 로그/EFI/백업은
로컬에 유지합니다. 사례 변경 시 절차 전달 전에 소스와 범위를 재검토합니다.
