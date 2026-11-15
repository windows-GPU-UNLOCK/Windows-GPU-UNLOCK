# Lenovo1052 다음 리소스 캡처(issue19)

[English](LENOVO-RESOURCE-CAPTURE.en.md)

원본 그래프 로그3533a5c42b911b1eeb2aad94e8b92f5858361278f883bbf61ba36454d03fa4c5는
여전히 gop-info/NOT_READY로 불완전합니다. v3는 결과를 바꾸지 않고 숫자 PCI
라우팅을 유지했습니다. 모드 정보가 있는 GOP에는 장치 경로가 있고, 다른 경로 없는
GOP에는 모드 정보가 없습니다. 소유권/해제 검증은 아닙니다. 원래 한 번 부팅의
Windows 직접 복귀는 기여자의 보고입니다. 그래프 부팅/같은 로그 수집을 반복하지 마세요.

공통 리소스 엔진은 Lenovo1052/BIOSS0AKT48A/i9-11900K,
NVIDIA2504/1043:881d,segment0/bus1/device0/function0 및 Windows의 유일한 PCI
디스플레이 어댑터로 제한됩니다. 제조사는 정확히 LENOVO입니다. DP/iGPU 상태와
공식 ASUS VBIOS 업데이트 이력을 유지하며 공장 VBIOS라고 가정하지 않습니다.

실시간 신원/리소스/콜백 검사 후 PCI 리소스/속성/부모 관측, 고정 BAR0 DWORD16개,
전체1MiB PROM 한 번(최대262160회 직접 MMIO 읽기), CPU 메모리의 로드된
펌웨어 드라이버 이미지 복사, 그래프 및 Windows 복귀 시도가 새 범위입니다.
GPU/PCI 쓰기, 디코드 활성화, 분리, 리셋, GPU 펌웨어 업로드/실행 또는 잠금 해제는
없습니다. 읽기도 부작용/멈춤을 일으킬 수 있고 복구는 미검증입니다. 기존 전환은
EFI watchdog을 끕니다. 자동 재부팅/재시도/롤백은 없습니다. 기존 일반 프로브의
GOP 처리도 프로필 자격을 부여하지 않습니다.

Windows의 Python/LLVM, 이미 꺼진 Secure Boot, 여유256MB 이상 FAT32 USB,
새로 푼 고정 소스 및 관리자 PowerShell에서 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-resource-capture.ps1 -Machine issue19
```

새 범위를 수락한 경우에만 ACCEPT-MMIO를 입력하세요. 실제 머신/Windows ESP/
USB와 고정 EFI를 검증하고 정책/신원/구성/미디어를 재확인합니다. 기존 로더를
백업/검증하고 이전 캡처는 이름 변경한 아카이브로 보존한 뒤 새 복사본을 검증합니다.
포맷/부팅 항목 쓰기는 없습니다. 오류/불일치 시 개인 경로를 지운 짧은 오류를
보고하고 중지하며 설정이나 검사를 변경하지 마세요.

READY 후 완전히 종료하고 USB를 수동으로 한 번만 부팅하세요. Shift 키는
필요 없습니다. 캡처 후 Windows가 예상됩니다. 2분 내 시작하지 않으면 전원을
끄고 USB를 제거한 뒤 일반 Windows Boot Manager를 사용하세요. 복구 실패 시
중지하세요. 불완전/거부라도 반복하지 마세요. 복귀 후 필요하면 USB를 재연결하고
같은 명령에 -Collect를 추가하세요. Documents 폴더의 검토한 report.json 하나와
Windows 직접 시작/수동 복구 여부만 보내 주세요. DIAG/PROM/IMG/EFI/아카이브/
백업은 로컬에 두고 USB를 제거하세요. 프로필 생성/잠금 해제/두 번째 캡처는
허용되지 않습니다.

로컬 검사는 일반 모의267개+고정 핀36개, Windows 신원/거부/스테이징 모의 및
소스/PE 검증입니다. Lenovo 합성 GUID fixture는31744바이트,AMD64,import0,
NX/dynamicbase이며 SHA256은fd3f4f105d6a3bdcec72dc350bff6169a163e8f4db9674a7f56dd70440573183입니다.
fixture는 절대 부팅하지 마세요. 준비 시 실제 Windows ESP로 빌드합니다.
이 케이스의 실제 MMIO나 Windows 복귀를 로컬에서 테스트하지 않았습니다.

준비 과정은 빌드 전과 USB 기록 전에 현재 시스템 볼륨의 완전 복호화 상태를 확인합니다. 암호화된 데이터가 남은 보호 해제 상태, 알 수 없는 상태, 공급자 실패 또는 상태 변경은 거부합니다. 테스트를 위해 보호 일시 중지, 복호화 또는 설정 변경을 하지 마세요. 기존 파일 수집에는 이 USB 준비 조건을 적용하지 않습니다.
