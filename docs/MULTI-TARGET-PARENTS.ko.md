# Issue17 Windows 대상 분리

PCI 부모 판독기는 case 17의 2204/40411458과 1e04/12fa10de를 각각 하나씩
선택합니다. 대상이 아닌 2c02/41781458의 부모는 읽지 않습니다.
대상이 누락되거나 중복되면 선택 단계에서 중지합니다.

```powershell
powershell -NoProfile -File .\tools\test-pci-parents.ps1 -Case 17
```

[기존 v2 보고서](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/17#issuecomment-6571986594)는
후속 읽기 실패 전의 두 PCI 연결을 보존합니다. 반복된 1022:43f5/43f4 모델
일치만으로 같은 인스턴스라고 판단할 수 없으며, Pci:null인 꼬리도 상위 장치
부재를 뜻하지 않습니다. 상위 observed 표시는 완료 여부를 과장했습니다.

windows-pci-parent-v3는 같은 RunId 안의 두 연결에서 무작위 NodeId를 공유합니다.
NodeId가 같아야 같은 Windows 인스턴스의 관찰이며, vendor/device 일치만으로는
부족합니다. 비PCI 노드는 제한된 Kind를 표시합니다. 두 연결 모두 명시적 루트에
도달해야 complete이고, 노드가 남은 나머지는 종료 이유가 있는 partial입니다.
선택/목록 조회 실패는 error입니다. 기존 보고서의 누락 ID나 루트 증거를
소급해 만들 수는 없습니다. 표시된 Documents 폴더의 검토한 pci-parents.json만
반환하세요. 원본 장치 인스턴스 경로는 제외합니다.
관리자 권한, Python, 드라이버 변경, PCI config/MMIO, EFI, 재부팅은 없습니다.
카드, 케이블과 설정을 유지하세요. 차단/실패하면 중지하고 개인 정보를 제거한
짧은 오류를 보내세요. 통과하려고 카드를 제거하지 마세요.

다중 대상 격리 검토를 위한 Windows 연결 정보이며 물리 슬롯, 링크 폭,
펌웨어 소유권, 독립 release 또는 unlock을 증명하지 않습니다.
TU102 1e04는 현재 generic probe 허용 목록 밖입니다. vendor 함수 이름은
제품군 지원의 근거가 아닙니다. 이 테스트는 GPU를 승인하지 않습니다.
[공유 상태 계약](PCI-PARENT-TEST.ko.md)을 참고하세요. -SelfTest는 합성 ID로
같은 모델의 다른 인스턴스와 실제 공통 부모를 검사하며 제보자의 원본 토폴로지를
재생하는 테스트는 아닙니다.
