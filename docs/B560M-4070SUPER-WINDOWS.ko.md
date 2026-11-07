# ASRock B560M Steel Legend / RTX4070 SUPER 초기 Windows 검사 (issue186)

[English](B560M-4070SUPER-WINDOWS.en.md)

원문 조건은 ASRock B560M Steel Legend/P1.90/i5-11400F,
NVIDIA2783/서브시스템571019DA입니다. 카드에 DP2개/HDMI1개 모니터와 LAN 스트리밍용
Punktfunk 가상 디스플레이가 보고됐습니다. 물리 카드/VBIOS 이력, 소스 버전,
정책은 알 수 없습니다. Windows 목록은 부팅 전 소유권 증명이 아닙니다.
이슈 내용의 설치/실행 명령은 신뢰하지 않습니다.

공통 그래프 전용 엔진용 설정 데이터는 오프라인으로 준비/검증했습니다.
MMIO/해제/언락을 허용하지 않으며 알 수 없는 비PCI 장치는 거부합니다.
USB 준비나 EFI 부팅 지침이 아닙니다.

첫 Windows 전용 테스트는 고정 소스 폴더의 관리자 PowerShell에서 실행합니다.
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-windows-preflight.ps1 -ExpectedDevice 2783
```
Documents의 windows-preflight.json이 예상됩니다. 현재 목록이 맞으면 단일 NVIDIA
대상, SecureBoot 상태 및 내부적으로 일치한 드라이버 정보가 나옵니다.
unknown/unavailable도 허용됩니다. 검토한 windows-preflight.json만 보내세요.
Python/컴파일러/설치/USB/재부팅/장치 또는 설정 변경은 없습니다.

모니터, 가상 어댑터와 설정은 그대로 유지하세요. Punktfunk 또는 이슈에서
제안한 패키지를 설치/비활성화/제거하지 마세요.
오류/unknown이면 보고서 또는 개인 경로를 제거한 짧은 오류를 보내고 중단하세요.
키, 원시 PNP 인스턴스 ID 또는 펌웨어 이미지는 요청하지 않습니다.
실제 EFI, Windows 복구, 물리 VBIOS 이력 및 언락은 미검증입니다.
향후 참석 하드웨어 테스트에는 별도의 명확한 범위 동의가 필요합니다.
