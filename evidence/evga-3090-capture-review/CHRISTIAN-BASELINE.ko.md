# Christian Windows 기준 정보 검사

[English](CHRISTIAN-BASELINE.en.md)

`research/profile/collect-christian-baseline.ps1`를 실행합니다. 기본 캡처 위치는 `C:\GPU-Unlock\Captures`, 고유 출력 폴더/ZIP은 `C:\GPU-Unlock\Results` 아래입니다. 표시된 ZIP을 보내세요. 관리자 권한이나 재부팅은 필요하지 않습니다.

Windows 빌드/부팅 시각, 보드 제품, BIOS 버전, GPU 드라이버/PCI 식별 및 제한된 NVIDIA 조회를 읽습니다. 원시 진단을 복사하지 않고 두 파일 해시를 기록합니다. 일련번호, 전체 PNP 인스턴스와 원시 펌웨어 덤프는 제외합니다. NVIDIA 조회 실패는 실패로 기록합니다. GPU 부하, 벤치마크, 설정 변경, 펌웨어 쓰기, EFI 실행이나 잠금 해제를 하지 않습니다. 현재 구성 기준 정보이며 성능 기준이나 Stop 경로 검증은 아닙니다.

PowerShell 7과 5.1의 모의 검사에서 ZIP 생성, NVIDIA 조회 인자, 개인정보 제외, 캡처 해시 및 잘못된 GPU의 출력 전 거부가 통과했습니다. 실제 조회 성공은 모의 검사로 입증하지 않습니다. 캡처/BIOS 설정을 보존하고 오류 시 오류를 보내세요. EFI를 반복하지 마세요.
