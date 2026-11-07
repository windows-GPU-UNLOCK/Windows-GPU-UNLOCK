# 이슈 33: 사용자 입회 X99 그래프 캡처

[English](X99-GRAPH-TEST.en.md) | **한국어**

#33에 보고된 ASUS X99-PRO/USB 3.1 BIOS 4101, i7-5820K, 단일 ASUS RTX 3090
`2204 / 1043:87af` 전용입니다. 프로필 개발을 위한 그래프 진단이며 언락이나
완전한 프로필 캡처가 아닙니다. GPU MMIO/PROM 읽기, 드라이버 이미지 덤프,
드라이버 해제, GPU 쓰기, 펌웨어 변수 쓰기는 추가하지 않습니다.

EFI는 펌웨어 프로토콜/열기 관계, 콘솔 변수, GOP 모드 정보, PCI 헤더를 읽고
USB 로그를 쓴 뒤 현재 시스템 ESP의 Windows Boot Manager로 리셋 없이 인계를
시도합니다. 기존 인계 코드처럼 EFI watchdog을 끕니다. 펌웨어 호출이나 인계가
멈추고 화면/입력이 사라지거나 Windows로 돌아오지 못할 수 있습니다. 복구는
입증되지 않았으며 자동 재시도/롤백은 없습니다. 소유자가 이 범위를 수락하고
직접 지켜보는 장비에서만 사용하세요.

## 한 번 준비

기존 FAT32 USB 데이터 장치, Python, LLVM(`clang`, `lld-link`)이 필요합니다.
Secure Boot는 이미 꺼져 있어야 합니다. 테스트 때문에 설정을 바꾸지 마세요.
고정된 테스트 소스 압축을 풀고 그 폴더에서 관리자 PowerShell을 여세요.
스크립트는 Secure Boot/디스크 정보를 읽지만 디스크를 포맷하지 않습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-x99-graph.ps1
```

USB 드라이브 문자를 입력하세요. 정확한 장비 튜플, USB/FAT32/시스템 디스크 제외,
기존 Secure Boot 상태, 현재 Windows ESP를 확인합니다. 위험 설명을 읽고
수락할 때만 `PREPARE`를 입력하세요. EFI를 빌드하고 기존 USB 부트로더를
백업/검증하며 기존 캡처가 있으면 거부하고 최종 USB 복사를 검증합니다.
재부팅하지 않습니다.

예상 결과는 **READY**입니다. 오류나 조직 정책 차단이 발생하면 개인 경로를
지운 짧은 오류만 보고하고 중단하세요. 설정 변경, 검사 우회, 무작정 재시도를
하지 마세요. 일부 준비 결과와 백업은 검토를 위해 남깁니다.

## 한 번 실행하고 근거 회신

완전히 종료한 뒤 펌웨어 부팅 메뉴에서 USB를 직접 한 번 선택하세요.
Shift 키 등 단축키는 필요하지 않습니다. 그래프 캡처 후 Windows로 직접
부팅되는 것이 예상 동작입니다. 2분 내 Windows가 시작하지 않으면 전원을 끄고
USB를 제거한 뒤 평소 Windows Boot Manager를 선택하세요. 복구가 실패하면
테스트 사용을 중단하세요. 같은 실행을 반복하지 마세요.

Windows에서 필요하면 USB를 다시 연결하고 같은 스크립트에 `-Collect`를 붙이세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-x99-graph.ps1 -Collect
```

USB 문자를 다시 입력하세요. 표시된 문서 폴더의 **graph-summary.json**만 검토해
첨부하고 **Windows 직접 시작** 또는 **수동 복구 필요**를 알려주세요.
원본 DIAG 로그, EFI, 백업은 로컬에 보관하세요. 요약은 허용한 숫자 관계/PCI
헤더, 해시, 완료 표식만 담고 원본 장치/파일 경로를 제외합니다. 수집 후 USB를
제거하세요. 표식은 관측값이며 프로필 성공이나 안전한 해제의 증명이 아닙니다.
이 그래프를 바탕으로 자원/드라이버 적합성의 다음 단계를 별도 검토합니다.
