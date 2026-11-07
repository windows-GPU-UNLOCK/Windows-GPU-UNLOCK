# 이슈 180: 사용자 입회 NVIDIA + AMD 그래프 캡처

[English](B550-DUAL-GRAPH-TEST.en.md) | **한국어**

Gigabyte B550 AORUS ELITE V2 BIOS F19, Ryzen 5 5600G,
NVIDIA `2489 / 10de:153c`, AMD `1638 / 1458:d000` 전용 준비입니다.
두 PCI 디스플레이 어댑터를 유지하고 보고된 두 모니터 케이블을 옮기지 마세요.
ROOT/SWD 가상 어댑터를 제거하거나 펌웨어 GOP의 증거로 취급하지 않습니다.

진단은 펌웨어 프로토콜/열기 관계, 콘솔 변수, GOP 정보, 노출된 어댑터의 PCI
헤더를 기록하고 USB 로그를 쓴 뒤 Windows 인계를 시도합니다. GPU MMIO/PROM
읽기, 이미지 덤프, 드라이버 해제, GPU 쓰기, 언락은 없습니다. 기존 인계 코드는
EFI watchdog을 끕니다. 실제 부팅 전 그래프를 기록하며 Windows 어댑터 두 개가
독립적으로 사용할 수 있는 AMD GOP의 존재를 입증하지는 않습니다.

펌웨어/화면/입력 또는 Windows 인계가 멈출 수 있고 복구는 입증되지 않았습니다.
전원 종료, USB 제거, 평소 Windows Boot Manager 선택이 필요할 수 있습니다.
자동 재부팅/재시도/롤백은 없습니다. 준비 전에 이 범위를 수락하세요.
Secure Boot는 이미 꺼져 있어야 하며 테스트 때문에 설정/모니터 연결을 바꾸지 마세요.

Python/LLVM과 여유 공간 16 MB 이상의 기존 FAT32 USB를 사용하세요.
고정 소스 압축을 푼 폴더에서 관리자 PowerShell로 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue180
```

USB 문자를 입력하고 위험 설명을 읽고 수락할 때만 `PREPARE`를 입력하세요.
장비/두 PCI 어댑터, 현재 Windows ESP와 USB 신원을 검사하고 기존 USB 부트로더를
보존/검증한 뒤 새 복사본을 확인합니다. 포맷하지 않습니다. 불일치, 오류, 정책
차단 시 개인 경로를 지운 짧은 메시지를 보고하고 중단하세요. 검사를 우회하지 마세요.

**READY** 후 완전히 종료하고 USB를 한 번 직접 선택해 부팅하세요. 테스트 중
단축키는 없습니다. 그래프 캡처 후 Windows 시작이 예상됩니다. 2분 내 Windows가
시작하지 않으면 전원을 끄고 USB를 제거한 뒤 평소 Windows Boot Manager로
부팅하세요. 복구가 실패하면 중단하고 같은 실행을 반복하지 마세요.

Windows에서 필요하면 USB를 다시 연결하고 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue180 -Collect
```

표시된 문서 폴더의 **graph-summary.json**을 검토해 첨부하고 Windows 직접 시작
또는 수동 복구 필요 여부를 알려주세요. 원본 DIAG/EFI/백업은 로컬에 보관하고
수집 후 USB를 제거하세요. 언락/하드웨어 지원 주장이 아니라 다음 프로필
단계를 위한 토폴로지 근거입니다.
