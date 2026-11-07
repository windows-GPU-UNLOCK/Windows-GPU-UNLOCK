# ZBOX Windows PCI 연결 (#167)

```powershell
powershell -NoProfile -File .\tools\test-pci-parents.ps1 -Case 167
```

공유 Windows 부모 판독기를 정확한 2504/263019da, 9bc8/b44019da 데이터와 사용해
NVIDIA 연결을 먼저, Intel 연결을 두 번째로 반환합니다. 모의 테스트는 RDP가
Intel PCI 어댑터를 대신할 수 없음을 검사합니다. RDP 부모 조회 또는 ROOT/SWD
예외를 승인하지 않습니다. preboot 토폴로지, 물리 모니터/케이블 검증 또는 사용
가능한 복구 경로 증거가 아닙니다. EFI 준비의 unknown identity 거부는 그대로이며
다른 보드 프로필의 같은 GPU ID는 이 보드의 검증을 대신하지 않습니다.

[기존 v2 보고서](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/167#issuecomment-6566566392)는
NVIDIA 대상 다음의 Intel 8086:1901과 별도 Intel 9bc8 대상을 기록합니다.
두 연결 모두 비PCI 꼬리 뒤에 읽기가 실패합니다. 이 PCI 관찰은 여전히 유용하며
unavailable은 부모 부재나 펌웨어 문제의 증거가 아닙니다. 상위 observed도
어느 연결의 완료를 뜻하지 않았습니다.

windows-pci-parent-v3는 비PCI 종류, 실행 내 공통 인스턴스용 무작위 NodeId와
정확한 루트/읽기 실패/cycle/depth-limit 종료를 구분합니다. 두 연결이 모두
완료되어야 complete이며, 남은 불완전한 관찰은 partial, 선택/목록 조회 실패는
error입니다. 기존 v2 자료를 완료 증거로 바꾸지 않습니다.
[공유 상태 계약](PCI-PARENT-TEST.ko.md)을 참고하세요.
표시된 Documents 폴더의 검토한 pci-parents.json만 보내세요. Python, 관리자 권한,
펌웨어, PCI config/MMIO, 드라이버/설정 변경, 케이블 이동, EFI 또는 재부팅은
없습니다. RDP를 그대로 두세요. 차단/실패면 중지하고 개인 정보를 제거한 짧은
오류만 보내세요. 통과하려고 가상 어댑터를 제거하거나 모니터를 옮기지 마세요.
