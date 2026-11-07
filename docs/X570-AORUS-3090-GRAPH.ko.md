# X570 AORUS ELITE / RTX3090 FE 그래프 전용 연구 (issue172)

[English](X570-AORUS-3090-GRAPH.en.md)

정확한 준비 조건: Gigabyte X570 AORUS ELITE/F41c/Ryzen5800X,
유일한 PCI 디스플레이 어댑터 NVIDIA2204/서브시스템147D10DE.
소유자는 RTX3090 FE, VBIOS94.02.27.00.0A와 카드에 연결한 두 DP 모니터를 보고했습니다.
플래싱 이력과 수집기 버전은 알 수 없으며 원래 공장 펌웨어라고 가정하지 않습니다.
다른 X570/3090 사례가 이 기기를 검증하지 않습니다.

선택적 새 범위: 펌웨어 핸들/프로토콜/열기 정보, 콘솔 변수, GOP 메타데이터,
64바이트 PCI 헤더, USB 로그 및 Windows 복귀 시도입니다.
GPU MMIO/PROM, 이미지 덤프, 드라이버 해제/재설정, GPU 쓰기/펌웨어 업로드/
실행/언락은 없습니다. 펌웨어/화면/입력/Windows 복귀가 멈출 수 있습니다.
기존 복귀 과정은 EFI watchdog을 끕니다. 복구는 미검증이며 전원 종료,
USB 제거 및 일반 Windows Boot Manager가 필요할 수 있습니다.
자동 재시도/재부팅/롤백은 없으며 소유자의 명시적 동의가 필요합니다.

Windows에 이미 설치된 Python/LLVM,16MB 여유 공간의 기존 FAT32 USB,
새 고정 소스 폴더의 관리자 PowerShell을 사용합니다.
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue172
```
두 DP 연결과 설정은 그대로 두세요. SecureBoot는 이미 꺼져 있어야 하고
시스템 볼륨은 완전히 복호화되어 있어야 합니다. 켜짐/알 수 없음/암호화 상태이면
중단하고 이 테스트를 위해 펌웨어/암호화 설정을 변경하지 마세요.
도구가 없으면 설치하지 말고 중단하세요. 범위에 동의할 때만 PREPARE를 입력합니다.

현재 기기/Windows ESP/USB를 확인하고 실제 Windows 위치로 빌드/검증하며
이전 USB 로더 백업/읽기 검증, 기록 전 미디어/설정/암호화/SecureBoot 재확인을
수행합니다. 불일치/알 수 없음/오류이면 중단하고 조건이나 설정을 우회하지 마세요.

READY 이후에만 완전 종료 후 USB를 수동으로 한 번 선택하고 Shift는 누르지 마세요.
그래프 캡처 후 Windows 복귀가 예상됩니다.2분 안에 Windows가 시작하지 않으면
전원을 끄고 USB를 제거한 뒤 일반 Windows Boot Manager를 선택하세요.
복구 실패 시 중단합니다. 불완전/거부된 캡처 후에도 반복하지 마세요.
Windows에서 필요하면 USB를 다시 연결하고 같은 명령에 -Collect를 붙이세요.
Documents의 검토한 graph-summary.json과 직접 복귀/수동 복구 여부만 보내세요.
원시 로그/EFI/백업은 로컬에 두고 이후 USB를 제거하세요.

15개 데이터 구성과 공통 식별/거부/USB 준비/암호화 테스트가 통과했습니다.
AMD64 fixture14848바이트, imports0, NX/dynamicbase 빌드/PE 검증,
SHA2563d476bb7498d28c8f4d6e5a041d8da4b60b4df212e9edc43c2465668cd28f6f6.
가짜 GUID fixture는 부팅하지 마세요. 이 보드의 실제 펌웨어 동작/Windows 복구는
여기서 미검증입니다. 그래프 증거는 언락/프로필 허가나 VBIOS 이력 검증이 아닙니다.
