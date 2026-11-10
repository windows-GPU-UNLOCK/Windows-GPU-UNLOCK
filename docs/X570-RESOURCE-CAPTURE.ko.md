# 공통 고정 리소스 캡처: issue31

[English](X570-RESOURCE-CAPTURE.en.md)

기존 그래프 전용 로그 이후의 새로운 하드웨어 범위입니다. 실수로 두 번 부팅해도
로그 바이트 자체가 무효화되지는 않으나 파일 이름/결과는 독립적인 완전 종료
캡처 증거가 아닙니다. 그래프 테스트를 반복하지 마세요. Windows 직접 복귀는
기여자의 보고입니다.

ASUS PRIME X570-PRO BIOS5013/Ryzen5950X, NVIDIA2204/10de:147d,
segment0/bus8/device0/function0, Windows의 유일한 PCI 디스플레이 어댑터로
제한됩니다. ROOT/SWD 및 서명된 LCI/LuminonCore1.0.2018.1204 연결을 유지하세요.
Windows 메타데이터는 EFI 소유권이나 해제 안전성 증거가 아닙니다.
issue114도 호환 진입점을 통해 같은 엔진을 사용합니다.

실시간 신원/리소스/콜백 검사 후 PCI 리소스/속성/부모 관측, 고정된 BAR0 DWORD16개,
전체1MiB PROM 한 번(최대262160회 직접 MMIO 읽기), CPU 메모리의 로드된 펌웨어
드라이버 이미지 복사, 소유권/콘솔 그래프 및 Windows 복귀 시도가 새 범위입니다.
GPU/PCI 쓰기, 디코드 활성화, 분리, 리셋, GPU 펌웨어 업로드/실행 또는 잠금 해제는
없습니다. 읽기도 부작용이나 펌웨어/화면/입력/Windows 멈춤을 일으킬 수 있고
복구는 검증되지 않았습니다. 기존 전환은 EFI watchdog을 끕니다. 자동 재부팅,
재시도/롤백은 없습니다. 빌드/스테이징 전 ACCEPT-MMIO 수락이 필요합니다.

Secure Boot가 이미 꺼진 상태, Windows의 Python/LLVM, 관리자 PowerShell,
여유256MB 이상의 기존 FAT32 USB 및 새로 푼 고정 소스로 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-resource-capture.ps1 -Machine issue31
```

정확한 머신/드라이버/구성/USB와 현재 Windows ESP를 확인하고 신원 고정 EFI의
PE/소스 매니페스트를 검증합니다. 컴파일 전후 구성 해시, 머신/드라이버/USB/
SecureBoot를 재확인하고 기존 로더를 백업/검증하며 캡처 폴더를 보존 아카이브로
이름 변경하고 새 복사본을 검증합니다. 포맷이나 부팅 항목 쓰기는 없습니다.
불일치/정책 불명/도구 누락/오류 시 개인 경로를 지운 짧은 오류를 보고하고
중지하세요. 검사나 설정을 변경하지 마세요.

READY 후 완전히 종료하고 USB를 수동으로 한 번만 부팅하세요. Shift 키는
필요 없습니다. 캡처 후 Windows가 예상됩니다. 2분 내 Windows가 시작하지
않으면 전원을 끄고 USB를 제거한 뒤 일반 Windows Boot Manager를 사용하세요.
복구 실패 시 사용을 중지하세요. 불완전/거부 결과라도 반복하지 마세요.

복귀 후 필요하면 USB를 재연결하고 같은 명령에 `-Collect`를 추가하세요.
출력된 Documents 폴더의 검토한 report.json 하나와 Windows 직접 시작/수동
복구 여부만 보내 주세요. 원본과 아카이브 DIAG/PROM/IMG/EFI/백업은 로컬에
유지하고 USB를 제거하세요. 결과 검토 전 프로필 생성이나 잠금 해제는 허용되지
않습니다.

로컬 검증은 일반 모의267개+Zotac 고정12개+X570 고정12개, 구성/USB/아카이브/
반복 거부, 금지 빌드4개, 두 고정 fixture 빌드와 PE/소스 매니페스트입니다.
X570 합성 GUID 이미지31744바이트의 SHA256은
32dda2435ba4d61c20e262717bc128e43c5ba2e1c1d0937a811cc796ffa55d6c입니다.
fixture는 절대 부팅하지 마세요. 준비 스크립트가 실제 Windows ESP로 빌드합니다.
로컬 모의/빌드는 실제 MMIO나 Windows 복귀 증거가 아닙니다.

준비 과정은 빌드 전과 USB 기록 직전에 시스템 볼륨의 완전 복호화를 확인합니다. 보호 해제만으로 충분하지 않습니다. 암호화/전환/알 수 없는 상태 또는 공급자 실패이면 설정 변경 없이 중단합니다. 테스트를 위해 보호 일시 중지나 복호화를 하지 마세요. 기존 파일 수집은 계속 가능합니다.
