# Windows PCI 부모 연결 (#108)

고정 소스를 압축 해제한 폴더의 일반 Windows PowerShell에서 실행하세요.

```powershell
powershell -NoProfile -File .\tools\test-pci-parents.ps1
```

현재 디스플레이 목록과 유일한 2208/40811458 대상의 DEVPKEY_Device_Parent만
읽으며, 대상을 포함해 최대 16개 노드를 방문합니다. windows-pci-parent-v3는
숫자 PCI ID/서브시스템, 연결 순서, 제한된 비PCI 종류와 무작위
NodeId/ParentNodeId를 내보냅니다. 같은 RunId 안에서는 같은 Windows 인스턴스의
NodeId가 같고, 모델이 같은 별도 브리지는 다른 ID를 갖습니다. 실행 간 ID는
비교할 수 없습니다. 원본 인스턴스 경로, 일련번호, 이름과 오류 본문은 제외합니다.

표시된 Documents 폴더의 검토한 pci-parents.json만 반환하세요. 모든 대상 연결이
정확한 Windows 장치 트리 루트 또는 성공적으로 읽은 빈 부모에 도달해야
ReadStatus가 complete입니다. 노드가 남은 불완전한 결과는 partial이고,
대상 선택/목록 조회 실패는 error입니다. 각 연결에 State, Termination,
StopNodeId를 기록합니다. parent-read-failed, invalid-parent-response, cycle,
depth-limit는 명시적인 partial 결과입니다. 깊이 제한 뒤의 부모는 방문 행 없이
ParentNodeId만 있을 수 있습니다. 읽기 실패는 부모가 없다는 증거가 아닙니다.

정확한 HTREE 루트만 부모 조회 없이 완료합니다. 일반 ROOT 열거 장치는 계속
조회하며, 알 수 없는 비PCI 노드는 other로 남깁니다. 순차 Windows 연결 관찰이며
동시 스냅샷, 물리 커넥터/슬롯, EFI 소유권 또는 unlock 증거가 아닙니다.
[부모 속성 문서](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/devpkey-device-parent)와
[루트 노드 예시](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-devobj)를 참고하세요.

Secure Boot, 카드, 케이블과 설정을 유지하세요. Python, 권한 상승, 펌웨어 덤프,
PCI config/MMIO, 드라이버 변경, EFI 또는 재부팅은 필요하지 않습니다.
partial/error도 유용하므로 이를 없애려고 장비를 변경하지 마세요. 정책이 차단하면
개인 정보를 제거한 짧은 오류를 보내세요. 하드웨어/쓰기/경로 검증 플래그는 모두
false입니다. -SelfTest는 합성 연결의 CPU 전용 회귀 테스트이며 PnP 조회나
보고서 파일 생성 없이 모델 반복, 공통 부모, 비PCI 꼬리와 종료 경계를 검사합니다.
