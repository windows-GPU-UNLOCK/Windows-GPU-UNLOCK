# 공통 그래프 진단

[English](GENERIC-GRAPH-TEST.en.md)

모든 구성은 하나의 준비 엔진과 그래프 전용 EFI 빌드를 공유합니다.
`research/profile/graph-configurations/*.json`은 실행 코드가 아닌 보드, 제조사
일치 규칙, BIOS, CPU 토큰, 전체 PCI 디스플레이 장치 ID 데이터입니다.
구성 ID는 테스트 선택자이며 잠금 해제 지원 프로필이 아닙니다.
기존 명령과 X99 진입점은 유지됩니다.

Python과 LLVM은 USB가 아닌 Windows에 설치합니다. 고정된 소스 ZIP을 새로
풀고 관리자 PowerShell과 여유 공간 16 MB 이상의 FAT32 USB를 사용하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue182
```

검토된 이슈 안내에 지정된 ID만 사용하세요. 실제 장치, 이미 꺼진 Secure Boot,
현재 내부 Windows ESP와 USB ID를 확인합니다. 불일치나 정책 차단 시 짧은
오류만 보고하고 중지하세요. JSON/검사 우회, 장치 비활성화, 펌웨어 설정 변경,
다른 ID 대체는 하지 마세요. VBIOS 이력이 불명이면 그대로 불명입니다.
이 진단은 VBIOS를 읽거나 지원 여부를 입증하지 않습니다.

표시된 범위를 이해하고 수락한 경우에만 `PREPARE`를 입력하세요.
펌웨어 프로토콜/열린 관계, 콘솔 변수, GOP 정보, 64바이트 PCI 헤더를 읽고
USB에 진단을 기록한 뒤 Windows로 돌아가려고 시도합니다. GPU MMIO/PROM,
이미지 덤프, 드라이버 해제, GPU 쓰기 및 잠금 해제는 없습니다. 기존 Windows
전환은 EFI watchdog을 끕니다. 펌웨어/화면/입력이 멈추거나 Windows 복귀가
실패할 수 있으며 복구는 검증되지 않았습니다. 기존 USB 로더를 백업/재검증하며
빌드 후 구성 해시를 재확인하여 graph-stage.json에 기록합니다.
포맷, 부팅 항목 쓰기, 자동 재부팅/재시도/롤백은 없습니다.

READY 후 완전히 종료하고 USB를 수동으로 한 번만 부팅하세요. Shift 키는
필요 없습니다. 캡처 후 Windows가 예상됩니다. 2분 내 Windows가 시작되지
않으면 전원을 끄고 USB를 제거한 뒤 일반 Windows Boot Manager를 사용하세요.
복구 실패 시 테스트 사용을 중지하세요. 반복하지 마세요. Windows 복귀 후
필요하면 USB를 다시 연결하고 같은 명령에 `-Collect`를 추가하여 실행하세요.
출력된 Documents 폴더의 검토한 `graph-summary.json` 하나와 Windows가 직접
시작했는지 수동 복구가 필요했는지만 보내 주세요. 원본 로그/EFI/백업은 로컬에
보관하고 USB를 제거하세요. 결과 검토 후 다음 테스트를 결정합니다.

## 유지관리 검사

`test-graph-configurations.ps1`은 모든 데이터 구성, 거부 사례 및 기존 진입점을
검사합니다. `test-x99-graph-preparation.ps1`은 기존 핀과 모의 파일 스테이징을
검사합니다. `build-graph-only.ps1 -Fixture`는 공통 EFI를 검증합니다.
Windows ESP GUID가 비어 있는 fixture는 절대로 부팅하지 마세요.
구성 데이터 추가는 GPU 계열 지원이나 MMIO/해제/잠금 해제 허용이 아닙니다.
별도 소스 검토, 증거 및 충분한 설명에 따른 수락이 필요합니다.

`issue184` 구성은 MSI MAG X870E TOMAHAWK WIFI (MS-7E59), BIOS2.A91, Ryzen9800X3D, NVIDIA2204/1462:3882 및 AMD13c0/1462:7e59로 제한됩니다. NVIDIA의 모니터 3개와 VR 헤드셋, AMD의 모니터 1개 연결을 그대로 유지하고 두 어댑터를 활성 상태로 두세요. VR 연결은 펌웨어 소유권의 증거가 아니며 검사를 통과하려고 어댑터를 무시해서는 안 됩니다. VBIOS 이력은 불명입니다. 같은 명령에서 `-Machine issue184`를 사용하며 위 수락, 중지/복구 및 수집 안내가 모두 적용됩니다.

그래프 내보내기 v2는 고정된 진단 실패 이름과 숫자 상태 코드를 중복/충돌 관측값까지 유지합니다. 알 수 없거나 잘못된 원인 문자열은 개수만 기록하고 복사하지 않습니다. 불완전 캡처는 그대로 불완전입니다. 내보내기만 수정된 경우 기존 로그에서 `-Collect`만 실행하며 EFI를 다시 부팅하지 않습니다.

그래프 내보내기 v3는 명시적인 핸들과 DevicePath 프로토콜 레코드 아래에서만 경로 노드 유형/길이 및 PCI 장치/함수 번호를 유지합니다. 공급자/GUID, ACPI, 저장소, 네트워크 및 파일의 원본 페이로드는 모두 제외합니다. 고정된 불완전 원인도 핸들/프로토콜 스트림 내 위치를 유지합니다. 이 라우팅 관측값은 자동 소유권 판정이나 해제 허용이 아니며 불완전 표시는 바꾸지 않습니다. 이 내보내기 수정은 기존 로그에서 `-Collect`만 실행하세요.

구성의 `KnownNonPciAdapters`는 추가적인 비 PCI Windows 열거자를 제한할 수 있습니다. 각 항목은 정확히 하나 존재하고, 내부 장치 인스턴스 연결 및 공급자/버전이 일치하는 서명된 DISPLAY 드라이버 항목 하나와 연결되어야 합니다. 이는 준비용 신원 관측값이며 펌웨어 소유권이나 신뢰 증명이 아닙니다. issue31은 반환된 Windows 보고서의 LCI/LuminonCore/1.0.2018.1204만 제한적으로 허용합니다. 누락/추가/변경/미서명/연결 불명 항목은 중지됩니다. ROOT/SWD 동작은 유지됩니다. 열거자의 전역 허용이나 해제/잠금 해제 허용은 아닙니다.

issue173은 MSI MEG Z790 ACE (MS-7D86)/BIOS1.G0/i9-13900K, EVGA2216/3842:4897 및 IntelA780/1462:7d86으로 제한됩니다. RTX의 DisplayPort+HDMI 연결과 보고된 TV 꺼짐 상태를 유지하세요. issue185는 ASRock A520M-ITX/ac/P3.90/RyzenPRO4650GE 및 Windows의 유일한 PCI 디스플레이 어댑터 ASUS2507/1043:887c로 제한됩니다. 펌웨어/iGPU 상태나 케이블을 변경하지 마세요. Windows 목록은 펌웨어 iGPU 부재의 증거가 아닙니다. 두 구성은 공통 그래프 전용 테스트를 재사용하며 다른 GPU의 잠금 해제 프로필을 사용하지 않습니다.

issue51은 ASUS TUF GAMING X570-PLUS (WI-FI)/BIOS4002/Ryzen5900X 및 유일한 ASUS RTX3090 2204/1043:87b3으로 제한됩니다. HDMI 모니터 두 개와 현재 설정을 유지하세요. VBIOS94.02.42.00.b4/기본 이력 및 Secure Boot 꺼짐은 기여자의 보고이며 준비 시 현재 정책/Windows 신원을 검사합니다. issue38과 GPU/VBIOS가 같아도 이 보드나 소유권 그래프가 검증되는 것은 아닙니다. 같은 그래프 전용 명령의 `-Machine issue51`과 위 수락/백업/한 번 부팅/중지/복구 및 요약 하나 수집 규칙을 사용합니다. 프로브 MMIO나 다른 머신의 잠금 해제 프로필은 허용되지 않습니다.
