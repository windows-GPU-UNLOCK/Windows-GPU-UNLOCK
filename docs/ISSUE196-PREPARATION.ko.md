# 이슈196: A4000 유지

그래프 전용 핀은 MSI PRO X870-P WIFI (MS-7E47), BIOS1.A76,
Ryzen9800X3D, 3080Ti2208/40811458, A4000 24B0/14AD10DE,
AMD13C0/7E471462입니다. 보고된 PCI 어댑터3개를 모두 요구합니다.
카드 제거, 장치 관리자, 케이블 또는 펌웨어 설정 변경은 요청하지 않습니다.
케이블 없는 A4000의 펌웨어 소유권이 없다고 볼 수 없고 Windows에서 비활성인
iGPU가 부팅 전 GOP 또는 복구 경로라고 볼 수 없습니다. 정확한 장비의 잠금
해제는 입증되지 않았습니다.

고정 체크아웃에서 선택적으로 픽스처 전용 검사를 실행합니다.

```powershell
powershell -NoProfile -File .\research\profile\test-graph-configurations.ps1 -Case 196 -Report
```

예상은 PASS 및 새 Documents/graph-configuration.json의 Case196,
PhysicalAdapterPins=3, MissingPhysicalAdapterCasesRefused=3,
A4000Required=true와 하드웨어/쓰기/허용 플래그 false입니다. 재현한다면
JSON만 공유하세요. 관리자는 이미 실행했습니다. 하드웨어 조회, USB 준비,
EFI 실행은 없습니다. 실패하거나 하드웨어/쓰기 플래그가 true이면 중단하고
설정과 카드를 유지하세요. 의존성 설치는 필요하지 않습니다.

공통 그래프 전용 엔진의 정확한 인벤토리 가드를 준비하는 테스트입니다.
MMIO, NVIDIA 카드 분리, 드라이버 해제 또는 잠금 해제를 활성화하지 않습니다.
향후 참석형 작업에는 펌웨어 소유권과 정확한 핀 검토 및 해당 위험에 대한
동의가 필요합니다. 일반 심층 프로브의 다중 NVIDIA 가드는 그대로입니다.
#108의 동일 서브시스템으로 호스트/OCuLink 경로를 옮길 수 없으며 #110이나
케이블 없는 A4000만으로 장치 해제 경로를 입증할 수 없습니다.
