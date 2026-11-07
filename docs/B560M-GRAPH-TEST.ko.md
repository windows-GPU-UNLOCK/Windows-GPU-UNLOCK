# 이슈 109: 사용자 입회 B560M 그래프 캡처

[English](B560M-GRAPH-TEST.en.md) | **한국어**

Gigabyte B560M DS3H V2 BIOS `F7 RB`, i5-11400F, 단일 RTX 3060
`2487 / 1458:4072` 전용 준비입니다. 다른 보드의 언락 프로필을 재사용하지
않습니다. #33과 같은 제한된 그래프 진단으로 프로토콜/열기 관계, 콘솔 변수,
GOP 정보, PCI 헤더를 읽고 USB 로그를 쓴 뒤 Windows 인계를 시도합니다.
GPU MMIO/PROM 읽기, 드라이버 이미지 덤프, 드라이버 해제, GPU 쓰기,
펌웨어 변수 쓰기는 없습니다. 기존 인계 코드는 EFI watchdog을 끕니다.
그래프는 이후 자원/드라이버 적합성 검토용이며 언락 지원을 입증하지 않습니다.

펌웨어/화면/입력 또는 Windows 인계가 멈출 수 있습니다. 복구는 입증되지
않았으며 전원 종료, USB 제거, 평소 Windows Boot Manager 선택이 필요할
수 있습니다. 자동 재부팅/재시도/롤백은 없습니다. 준비 전 위험 설명을 읽고
수락하세요. 참여는 선택이며 Secure Boot 등 설정을 바꾸지 마세요.

여유 공간 16 MB 이상의 기존 FAT32 USB, Python, LLVM이 필요하며 Secure Boot는
이미 꺼져 있어야 합니다. 고정 소스 압축을 푼 폴더에서 관리자 PowerShell을 여세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue109
```

USB 문자를 입력하고 위험을 수락할 때만 `PREPARE`를 입력하세요. 스크립트는
Windows에 보고된 정확한 장비/단일 GPU, 현재 Windows ESP, USB를 확인하고
기존 부트로더를 백업/검증한 뒤 새 복사본을 검사합니다. 포맷하지 않습니다.
불일치, 오류, 조직 정책 차단 시 개인 경로를 지운 짧은 메시지만 보고하고
중단하세요. 설정 변경이나 검사 우회를 하지 마세요.

**READY** 후 완전히 종료하고 펌웨어 부팅 메뉴에서 USB를 한 번 선택하세요.
단축키는 필요하지 않습니다. 그래프 캡처 후 Windows 직접 부팅이 예상됩니다.
2분 내 Windows가 시작하지 않으면 전원을 끄고 USB를 제거한 뒤 평소 Windows
Boot Manager로 부팅하세요. 복구가 실패하면 중단하고 같은 실행을 반복하지 마세요.

Windows에서 필요하면 USB를 다시 연결하고 같은 스크립트로 수집하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue109 -Collect
```

표시된 문서 폴더의 **graph-summary.json**을 검토해 첨부하고 Windows 직접 시작
또는 수동 복구 필요 여부를 알려주세요. 원본 DIAG/EFI/백업은 로컬에 보관하고
수집 후 USB를 제거하세요. 요약은 숫자 그래프 관계와 완료 표식만 내보내고
원본 경로를 제외하며 쓰기 권한을 부여하지 않습니다. 해당 보드의 펌웨어 동작과
Windows 복구는 실제 입회 실행을 검토하기 전까지 검증되지 않은 상태입니다.
