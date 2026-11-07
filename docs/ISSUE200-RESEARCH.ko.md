# Issue200: 정확한 구성과 미확인 Meta 어댑터

공통 graph-only 데이터는 PRIME B550M-A WIFI II / BIOS3636 / 5800X3D /
2216:48973842를 고정합니다. 준비 데이터이며 프로필/하드웨어 승인이 아닙니다.
공개 inventory의 Meta Virtual Monitor5.3.57.114에는 PCI ID가 없습니다.
이름/버전과 합성 signed ROOT/SWD 메타데이터로 machine guard를 통과할 수 없으며
회귀3개가 거부를 유지합니다. BIOS3621 및403F1458도 거부합니다.
issue84의 다른 GPU와 issue173의 다른 호스트는 이 시스템의 증거가 아닙니다.
Rift 연결, 카드 세부 모델, 소스 revision은 미확인이며 추정하지 않습니다.

기존 PowerShell만 사용하는 오프라인 테스트:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-configurations.ps1 -Report -Case 200
```

예상: graph-configuration-v4, Passed true, UnknownMetaCasesRefused3,
hardware/write/admission 플래그 false. 출력된 문서 폴더의 검토한
graph-configuration.json만 반환하세요. 현재 inventory가 아닌 fixture 검사입니다.
실패/정책 차단 시 중단하세요. 설치, 설정/어댑터/케이블 변경, staging, 부팅,
unlock은 하지 않습니다. 대체 firmware 복구 화면은 확인되지 않았습니다.
