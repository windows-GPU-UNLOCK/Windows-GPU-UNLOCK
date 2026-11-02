# 비공개 펌웨어 없이 PCI 상태 비교

이슈36은 ASUS FX506HCB / GA107M `25a2/13FC1043`의 USB 잠금 해제 1회와
AMD `1638` 화면을 사용하는 HP `25a2/8A3D103C` 문의를 포함합니다. 서로
다른 장비이며 이 저장소의 프로필 허용을 의미하지 않습니다. 균일 입력 MMA
성능, 실패한 마지막 FP16 대조군, Windows Event153 오류는 일반 GEMM,
앱 성능 또는 안정성 주장과 구분해야 합니다. Event153은 자동으로 NVIDIA
Xid153이 되지 않습니다.

현재 full-release 비교는 캡처된 capability DWORD가 정확히0x0012b410이고
checkCold=false일 때 DWORD0x80에서 기존 CED/URD 비트가 지워지는 것만
허용합니다. 다른 비트 변경, 새 오류 비트, 다른 오프셋 및 capability 변경은
거부합니다. 이 비교 함수는 노트북이 보고한 성공/FLR1회/정지/정리 조건 전체가
아니며 함수 통과로 주변 조건을 입증할 수 없습니다.

기존 전체 래퍼 테스트는 비공개 펌웨어 픽스처가 필요합니다. 새 실행기는 로컬의
신뢰된 full-release.c에서 실제 `VerifyConfigWord` 함수를 제한적으로 추출해
RAM 모의 설정과 컴파일합니다. 비교4483개 및 가드 제거 변형4개를 검출합니다.
복사한 대체 정책, 펌웨어 파일, 캡처 또는 하드웨어는 사용하지 않습니다.
추출 구조나 변형 기준이 바뀌면 소스 검토를 위해 중단합니다.

고정 체크아웃과 기존 Python3, clang, MSVC 도구에서 실행합니다.

```powershell
powershell -NoProfile -File .\research\profile\test-pci-status.ps1
```

-Python, -Clang, -VcVars는 이미 설치된 도구 경로에만 사용합니다. 설치나
PATH 정책 변경은 필요하지 않습니다. 예상 pci-status.json은 Passed=true,
Assertions=4483, GuardMutationsDetected=4이며 HardwareAccess,
EfiExecuted, LaptopProfileAdmitted, WriteEligible은 모두 false입니다.
Documents의 새 폴더에 CPU 테스트 파일이 저장됩니다. pci-status.json만
공유하세요. 실패하거나 허용/하드웨어 플래그가 true이면 중단합니다. 설정을
유지하고 하드웨어 재시도 또는 EFI 부팅을 하지 마세요.

HP 프로필은 별도 검토가 필요한 연구이며 ASUS의 cold mask/PROM/capability
핀을 옮길 수 없습니다. AMD/Intel 이름만으로 부팅 전 소유권이나 화면 경로를
알 수 없습니다. 정확한 HP 모델, BIOS 및 펌웨어 소유권은 아직 unknown입니다.
접수를 위한 EFI 프로브는 제안하지 않으며 확인할 수 없는 정보는 unknown으로
둬도 됩니다. 새 캡처나 하드웨어 실행 없이 소스 검토를 진행하는 테스트입니다.
