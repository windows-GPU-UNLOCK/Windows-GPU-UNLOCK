# 이슈 31: 사용자 입회 X570 그래프 테스트

[English](X570-GRAPH-TEST.en.md) | **한국어**

ASUS PRIME X570-PRO BIOS 5013, Ryzen 9 5950X, 단일 PCI 디스플레이 어댑터
`2204 / 10de:147d` 전용 준비입니다. ROOT/SWD 소프트웨어 어댑터를 물리 PCI GPU나
부팅 전 소유권의 근거로 취급하지 않습니다. 알 수 없는 신원과 추가 PCI
디스플레이 어댑터는 거부하며 장치를 끄거나 제거하지 않습니다.

프로필 개발을 위한 진단으로 프로토콜/열기 관계, 콘솔 변수, GOP 정보,
PCI 헤더, USB 로그와 Windows 인계 시도를 포함합니다. GPU MMIO/PROM,
드라이버 이미지 덤프, 드라이버 해제, GPU 쓰기, 언락은 없습니다. 기존 인계
코드는 EFI watchdog을 끕니다. 펌웨어/화면/입력 또는 Windows 부팅이 멈출 수
있으며 복구는 입증되지 않았습니다. 자동 부팅/재시도/롤백은 없습니다.

한 번의 입회 실행을 수락하면 16 MB 이상 남은 기존 FAT32 USB, Python, LLVM을
사용하세요. Secure Boot는 이미 꺼져 있어야 하며 테스트 때문에 설정을 바꾸지
마세요. 고정 소스 압축을 푼 폴더에서 관리자 PowerShell을 여세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue31
```

USB 문자를 입력하고 위험 설명을 읽은 뒤 수락할 때만 `PREPARE`를 입력하세요.
장비, Windows ESP, USB를 검사하고 기존 부트로더를 보존/검증한 뒤 새 복사본을
확인합니다. 포맷/재부팅하지 않습니다. 오류, 불일치, 정책 차단 시 개인 경로를
지운 짧은 메시지를 보고하고 중단하세요. 설정 변경이나 검사 우회를 하지 마세요.

**READY** 후 완전히 종료하고 USB로 한 번 직접 부팅하세요. Shift 키는 필요
없습니다. 그래프 캡처 후 Windows 시작이 예상됩니다. 2분 내 Windows가 시작하지
않으면 전원을 끄고 USB를 제거한 뒤 평소 Windows Boot Manager를 선택하세요.
복구 실패 시 테스트 사용을 중단하고 같은 실행을 반복하지 마세요.

Windows에서 필요하면 USB를 다시 연결하고 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue31 -Collect
```

표시된 문서 폴더의 **graph-summary.json**을 검토해 보내고 Windows 직접 시작 또는
수동 복구 필요 여부를 알려주세요. 원본 DIAG/EFI/백업은 로컬에 보관하고 수집 후
USB를 제거하세요. 이 장비의 EFI 동작/복구를 검증했다는 주장이 아니며 언락
프로필을 승인하지 않습니다.
