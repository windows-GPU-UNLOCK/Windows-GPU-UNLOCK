# 이슈27: 별도 B760 댓글 구성

| 설정 | 보드 / BIOS / CPU | NVIDIA ID |
|---|---|---|
| issue27-b760-gigabyte | B760M DS3H DDR4 / F16 / i5-12400F |2786/41271458|
| issue27-b760-msi | PRO B760M-E DDR4 (MS-7D48) / B.I0 / i5-13490F |2786/20007377|

둘 다 인벤토리 전용 보고입니다. 원 MSI1462:5138 및 수집기를 검증한
B550M/1462:5136과 별개입니다. 인벤토리는 실제 화면 경로, 펌웨어 소유권,
cold 상태 또는 복구를 입증하지 않습니다. 모르는 정책/화면/VBIOS 정보는
unknown으로 유지하며 접수용 EFI 캡처나 설정/어댑터 변경은 요청하지 않습니다.

새 데이터 설정은 공통 그래프 전용 준비 엔진을 재사용합니다. 카드별 코드,
MMIO/프로브 허용, 해제, 페이로드 또는 잠금 해제를 활성화하지 않습니다.
알 수 없는/추가 어댑터, 다른 보드/BIOS/CPU/서브시스템은 계속 거부합니다.

고정 소스에서 해당 장비의 명령 하나만 선택합니다.

```powershell
powershell -NoProfile -File .\research\profile\test-graph-offline.ps1 -Machine issue27-b760-gigabyte -PackagedFixture
```

MSI B760M-E만 -Machine issue27-b760-msi로 바꿉니다. 예상은 PASS와 새
Documents/graph-build-test.json의 정확한 설정/해시, 설정/모의 준비 pass,
FixtureOnly=true, HardwareTested=false, WriteEligible=false입니다.
재현한다면 JSON만 공유하세요. 두 경우 모두 로컬 통과했습니다. 컴파일러,
하드웨어 조회, 실제 USB, 설치, EFI, 재부팅 또는 설정 변경은 없습니다.
픽스처를 준비/부팅하지 마세요. 오류나 하드웨어/쓰기 true이면 중단하고
설정을 유지합니다.

정확한 준비 검증이며 AD104 Windows 잠금 해제 허용이 아닙니다. 참석형
펌웨어 계획에는 소스/소유권/정책 검토와 명시적 동의가 필요합니다. 외부 엔진
홍보나 다른 GA104/AD104 결과에서 보장된 복구/범용 지원을 추론하지 않습니다.
