# 이슈 19: 사용자 입회 Lenovo 그래프 캡처

[English](LENOVO-GRAPH-TEST.en.md) | **한국어**

Lenovo 1052 BIOS S0AKT48A, i9-11900K, 단일 ASUS RTX 3060
`2504 / 1043:881d` 전용입니다. 보고된 직접 DisplayPort 연결과 꺼진 iGPU를
유지하세요. 기존 공식 ASUS VBIOS 업데이트는 장비 이력으로 남기며 이 테스트는
해당 펌웨어를 읽거나 바꾸지 않습니다.

프로필 개발을 위한 그래프 진단으로 펌웨어 프로토콜/열기 관계, 콘솔 변수,
GOP 정보, PCI 헤더, USB 로그, Windows 인계 시도를 포함합니다. GPU MMIO/PROM
읽기, 드라이버 이미지 덤프, 드라이버 해제, GPU 쓰기, 언락은 없습니다. 기존
인계 코드는 EFI watchdog을 끕니다. 펌웨어/화면/입력 또는 Windows 인계가 멈출
수 있고 복구는 입증되지 않았습니다. 자동 부팅/재시도/롤백은 없습니다.
준비 전에 이 범위를 수락하세요.

Python/LLVM, 여유 공간 16 MB 이상의 기존 FAT32 USB, 이미 꺼진 Secure Boot가
필요합니다. 고정 소스 압축을 푼 폴더에서 관리자 PowerShell로 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue19
```

USB 문자를 입력하고 위험 설명을 읽어 수락할 때만 `PREPARE`를 입력하세요.
정확한 장비/현재 Windows ESP/USB를 확인하고 기존 USB 부트로더를 보존/검증한 뒤
새 복사본을 확인합니다. 포맷하지 않습니다. 오류, 불일치, 정책 차단 시 개인
경로를 지운 짧은 메시지를 보고하고 중단하세요. 설정 변경이나 우회를 하지 마세요.

**READY** 후 완전히 종료하고 USB를 한 번 직접 선택해 부팅하세요. Shift 키는
필요하지 않습니다. 그래프 캡처 후 Windows 시작이 예상됩니다. 2분 내 Windows가
시작하지 않으면 전원을 끄고 USB를 제거한 뒤 평소 Windows Boot Manager를
선택하세요. 복구 실패 시 테스트를 중단하고 같은 실행을 반복하지 마세요.

Windows에서 필요하면 USB를 다시 연결하고 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue19 -Collect
```

표시된 문서 폴더의 **graph-summary.json**을 검토해 보내고 Windows 직접 시작
또는 수동 복구 필요 여부를 알려주세요. 원본 DIAG/EFI/백업은 로컬에 보관하고
이후 USB를 제거하세요. Windows 수집기 성공은 EFI 동작이나 언락 프로필을
검증한 결과가 아닙니다.
