# 이슈38: 독립적인 receipt 소스 출처 확인

2026-11-02에 제공된 Format2 host-test receipt의 경로/SHA256845개를
공개 Git blob과 독립 비교했습니다. 기여자 코드나 펌웨어를 실행하지
않았습니다. 모든 입력이 공개 커밋
[d9094ae8b784cd8fecc529ab3cc21e6a52584f31](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/commit/d9094ae8b784cd8fecc529ab3cc21e6a52584f31)의
정확한 바이트와 일치하며 줄 끝 정규화도 필요하지 않았습니다.

receipt 트리 해시는
`654f2c97b8e5df0c5eac0c25ba5b059c1156684414de9acbb81812ca64f0898c`입니다.
현재 main fd8bbea에는842개가 정확히 일치합니다. 버전 차이3개는
research/pci-decode/snapshot.c, research/profile/proven.json,
research/profile/test_family_admission.py입니다. 현재 main과 다르다는
이유만으로 임의 로컬 변경으로 분류하면 안 됩니다.

receipt가 나열한 소스 해시의 공개 출처를 확인한 것입니다. 소유자가 실제로
그 바이트를 컴파일/실행했다는 독립 증명은 아닙니다. 별도로 해시된 생성
헤더와 비공개 PROM/드라이버/캡처 픽스처는 추적 입력845개에 포함되지 않으며
이 비교로 바이트를 재구성하지 않았습니다. 소유자가 보고한 host 작업22개,
하드웨어 잠금 해제, Windows 직접 복귀 및 동일 조건 GEMM은 각각 별도
증거입니다. 프로필 허용이나 새 하드웨어 실행을 승인하지 않습니다.

관리자는 확인된 공개 소스를 기준으로 검토를 진행하되 생성 헤더/픽스처와
트랜잭션/정리 증거의 경계를 유지합니다. 기여자의 추가 인벤토리, 벤치마크,
EFI 부팅 또는 반복 실행은 요청하지 않습니다.
