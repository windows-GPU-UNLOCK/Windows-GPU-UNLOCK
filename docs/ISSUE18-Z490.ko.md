# 이슈18 댓글: 별도 Z490 준비

보고된 구성은 MPG Z490 GAMING PLUS (MS-7C75), AMI A.B0,
i5-10600KF, RTX3060Ti2489/150A7377입니다. 원 ASUS B550 사례 및
이슈80의 Z690/40761458과 다릅니다. 설정 데이터로2489 MMIO/잠금 해제를
허용하거나 다른 GA104 프로필 또는 GOP 소유권을 옮길 수 없습니다. 보고된
KF CPU에는 iGPU가 없으며 실제 화면/펌웨어 소유권은 unknown입니다.
정확한 장비/알 수 없는 어댑터/정책/암호화 가드를 유지합니다.

고정 소스에서 선택적으로 오프라인 준비 테스트를 실행합니다.

```powershell
powershell -NoProfile -File .\research\profile\test-graph-offline.ps1 -Machine issue18-z490 -PackagedFixture
```

예상은 PASS 및 새 Documents/graph-build-test.json의 선택 설정
issue18-z490/해시, ConfigurationTests/MockStagingTests=pass,
FixtureOnly=true, HardwareTested=false, WriteEligible=false입니다.
재현한다면 JSON만 공유하세요. 관리자는 로컬 검증했습니다. 모의 백업/읽기
검증/캡처 보존은 임시 파일만 사용하며 실제 USB를 사용하지 않습니다.
하드웨어 조회, 컴파일러, 설치, EFI 또는 설정 변경은 없습니다. 픽스처를
준비하거나 부팅하지 마세요. 오류나 하드웨어/쓰기 플래그 true이면 중단하고
설정을 유지하세요.

재현 가능한 오프라인 준비 테스트이며 무손상 보장이나 참석형 실행 제안은
아닙니다. 향후 펌웨어 진단에도 정확한 범위, 소스/빌드 및 명시적 동의가
필요합니다. BIOS 변경, 접수용 EFI 캡처 또는 프로필 우회는 요청하지 않습니다.
