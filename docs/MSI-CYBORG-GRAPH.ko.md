# MSI Cyborg 그래프 전용 참석 연구 (issue130 MSI 기여자)

[English](MSI-CYBORG-GRAPH.en.md)

HP Victus 원문과 별개의 기기입니다. 정확한 준비 조건:
MSI MS-15K1, 제조사 Micro-Star International Co., Ltd., BIOS E15K1IMS.114,
i7-13620H, Intel8086:A7A8/1462:13B9 및 NVIDIA10DE:28A1/1462:13B9.
Windows 부모 관계는 활성 모니터를 Intel과 연결하지만 물리 MUX 경로나 부팅 전
소유권을 증명하지 않습니다. 내부 패널, MuMu 가상 어댑터, 케이블, MUX,
펌웨어 및 전원 설정은 그대로 유지하세요. 알 수 없는 비PCI 식별 형식은 거부합니다.
설정 데이터로 MMIO, 드라이버 해제 또는 언락을 허용할 수 없습니다.
노트북 언락 경로는 검증되지 않았습니다.

새로운 선택적 범위: 펌웨어 핸들/프로토콜/열기 메타데이터, 콘솔 변수,
GOP 모드 정보와 노출된 어댑터의64바이트 PCI 헤더 읽기, USB 로그 및 Windows 복귀 시도.
GPU MMIO/PROM, 이미지 덤프, 드라이버 해제, 재설정, GPU 쓰기, 펌웨어 업로드/실행,
언락은 없습니다. 펌웨어/화면/입력이 멈추거나 Windows가 시작하지 않을 수 있습니다.
기존 복귀 과정은 EFI watchdog을 끕니다. 이 노트북의 복구는 미검증입니다.
자동 재부팅/재시도/롤백은 없으며 기기 소유자의 한 번 실행 동의가 필요합니다.

고정 소스의 관리자 PowerShell에서 실행합니다. Windows에 이미 설치된 Python/LLVM,
16MB 여유 공간의 기존 FAT32 USB가 필요합니다.
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue130-msi
```
Secure Boot는 이미 꺼져 있어야 하고 시스템 볼륨은 완전히 복호화되어야 합니다.
변경됐거나 알 수 없으면 중단하고 설정/암호화를 바꾸지 마세요.
스크립트는 기기/현재 Windows ESP/USB를 확인하고 PREPARE 동의 후 실제 Windows
위치로 빌드/검증하며 이전 USB 로더 백업과 기록 후 읽기 검증을 수행합니다.
기록 전 암호화/SecureBoot를 재확인합니다. 알 수 없는 장치/도구/정책/오류이면
중단하고 우회하거나 설치하지 마세요.

READY 이후에만 완전 종료 후 USB를 수동으로 한 번 선택하세요. Shift는 누르지 않습니다.
그래프 로그 후 Windows 복귀가 예상됩니다.2분 안에 Windows가 시작하지 않으면
전원을 끄고 USB를 제거한 후 일반 Windows Boot Manager를 사용하세요.
복구 실패 시 중단하며 불완전한 캡처/거부 후에도 반복하지 마세요.
Windows에서 필요하면 USB를 다시 연결하고 같은 명령에 -Collect를 붙이세요.
Documents 폴더의 검토한 graph-summary.json과 직접 복귀/수동 복구 결과만 보내세요.
원시 로그/EFI/백업은 로컬에 보관하고 이후 USB를 제거하세요.

로컬 설정/거부/USB 준비/암호화 테스트와 공통 EFI 빌드/PE 검증을 통과했습니다.
AMD64 fixture14848바이트, imports0, NX/dynamicbase,
SHA2563d476bb7498d28c8f4d6e5a041d8da4b60b4df212e9edc43c2465668cd28f6f6.
가짜 GUID fixture는 부팅하지 마세요. 노트북 EFI 실행/복구는 여기서 검증하지 않았습니다.
이 단계는 토폴로지 연구 관찰이며 언락 지원을 뜻하지 않습니다.
