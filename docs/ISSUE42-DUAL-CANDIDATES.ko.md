# Issue42: 같은 시스템의 NVIDIA 후보2개

최신 요청은 기존3090-only 범위를 대체합니다. 같은 이슈에서 보고된3090/
2204-147D10DE(0:5:0.0, Windows NVIDIA index1),3090Ti/2203-161810DE
(0:1:0.0,index0,primary monitor)를 모두 검토합니다. PRIME Z690-A/4505/
i9-14900K와 IntelA780/86941043도 유지합니다. 보고 mapping이며 firmware
ownership/target 실행 증거는 아닙니다. cross-flash 이력은 미확인입니다.

공통 graph-only 구성은 물리 adapter3개를 보존합니다. inventory 순서 변경은
통과하고 하나라도 누락되면 거부합니다. 미확인 Microsoft Remote Display Adapter는
합성 signed null/ROOT/SWD metadata가 있어도 거부합니다. Windows 이름/status는
firmware 부재 증거가 아닙니다. adapter/GPU/iGPU 제거·비활성화나 케이블/설정
변경은 요청하지 않습니다.

이 플랫폼에서 어느 GPU도 unlock target으로 검증되지 않았습니다. graph-only는
모든 adapter를 관찰하며 MMIO/release/unlock target을 선택하지 않습니다. 향후
동작은 Windows/CUDA index/순서가 아닌 BDF/device/subsystem, fresh firmware
path/owner를 각각 고정해야 합니다. unlock 순서, 동시/두 번째 카드 실행,
복구 display 경로는 미확립입니다.

기존 PowerShell만 사용하는 offline 재현:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-configurations.ps1 -Report -Case 42
```

예상 graph-configuration-v5/Case42,Passed true,PhysicalAdapterPins3,
NvidiaCandidates2,MissingAdapterCasesRefused3,UnknownRemoteCasesRefused3이며
target-selection/unlock-sequence/hardware/admission/write는 false입니다.
재현 시 검토한 graph-configuration.json 또는 정제된 짧은 오류만 반환하세요.
live inventory가 아닌 fixture 검사입니다. tool/policy/error 시 설치/설정 변경,
staging/EFI 부팅 없이 중단합니다. maintainer 검증을 확인할 반복은 필요 없습니다.
공통 config/mock staging/fixture PE/source/hash 검사가 통과했습니다.

stock 측정은 unlock 판정에 불충분합니다. 낮은 sample도 함께 보존하며 원인은
미확인입니다. 새 benchmark나 외부 toolkit 실행을 요청하지 않습니다.
