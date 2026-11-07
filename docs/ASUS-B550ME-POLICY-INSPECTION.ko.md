# ASUS B550M-E BIOS4101: 관찰 전용 연구 계획

[English](ASUS-B550ME-POLICY-INSPECTION.en.md)

정확한 대상은 issue135의 ASUS TUF GAMING B550M-E/BIOS4101/Ryzen5600X,
NVIDIA2489/서브시스템248910DE입니다. Windows는 SecureBoot 켜짐, 시스템 볼륨
완전 복호화 및 표준 Windows UEFI 경로를 보고했습니다. 복구 증명은 아닙니다.

이 선택적 새 테스트는 정책 변경 전에 실제 메뉴 정보의 공백을 확인합니다.
SecureBoot 비활성화나 EFI 실행 요청이 아니며 거절해도 됩니다.
자동 재부팅/재시도/롤백/하드웨어 실행은 없습니다. USB는 필요하지 않습니다.
테스트 USB를 제거하고 일반 Windows를 사용하세요.

새 고정 소스의 관리자 PowerShell:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-policy-inspection.ps1 -Machine issue135
```
INSPECT-ONLY를 입력하기 전에 범위를 이해하고 동의하세요: Windows에서 공개
PK/KEK/db/dbx를 메모리로 읽어 로컬 해시/크기/속성을 비교하고, 소유자가 펌웨어
설정에 수동으로 한 번 들어가 Boot/SecureBoot/OS Type을 관찰할 수 있습니다.
비공개 서명/복구 키는 읽지 않습니다. 설정, 키 관리, 암호화, TPM, CSM, 부팅 항목,
정책은 변경하지 않습니다. 펌웨어/화면/입력/Windows 복귀가 멈출 수 있으며
복구는 미검증입니다. 전원 종료 및 일반 Windows Boot Manager가 필요할 수 있습니다.
복구 실패 시 중단하고 CMOS/TPM/키 초기화나 반복을 하지 마세요.
수동 재시작 전에 취소할 수 있습니다.

스크립트는 현재 정확한 기기/설정, SecureBoot 켜짐, 완전 복호화, 표준 Windows
경로를 확인한 뒤 고유 Documents 기준 폴더와 해시 영수증을 기록합니다.
오류/알 수 없음/불일치이면 중단하고 펌웨어에 들어가지 마세요.
통과하려고 설치/변경하지 마세요. baseline.json 및 inspection-receipt.json은
로컬 비공개로 보관하고 첨부하지 마세요.

BASELINE READY 이후에도 동의하면 수동으로 한 번 재시작하고 Delete로 ASUS 설정에
들어갑니다. 필요하며 명확히 표시되어 있으면 F7로 Advanced Mode를 선택하세요.
Boot > Secure Boot > OS Type을 값 선택/변경 없이 관찰하세요.
레이블 일치 및 현재 OS Type이 Windows UEFI mode인지 기록합니다.
메뉴가 다르거나 불확실하면 관찰을 중단하세요. Key Management, SecureBoot Mode,
CSM, TPM을 만지지 마세요. Discard Changes and Exit로 나가고 Save 안내는 취소하세요.
저장은 허용되지 않습니다. 일반 Windows Boot Manager로 돌아오세요.

Windows에서 같은 명령에 -Verify를 붙여 실행합니다. 원래 로컬 Documents 폴더를
입력하고 세 질문에 YES/NO/UNKNOWN으로 답하세요. 새 폴더의 검토한
inspection-check.json만 보내주세요. 화면 사진, 원시 변수, 기준 지문,
식별자는 요청하지 않습니다. NO/UNKNOWN도 허용되며 빈칸을 채우려고 재진입하지 마세요.

일치 보고서는 현재 설정/공개 변수, SecureBoot 켜짐, 복호화 볼륨, Windows 경로만
비교합니다. 소유자 답변은 독립 검증이 아닌 보고입니다. 숨은 설정, 펌웨어 복구,
신뢰는 미검증입니다. 정책 변경/EFI/허가 플래그는 모두 false입니다.
서명 없는 EFI 실행은 자동으로 이어지지 않으며 정책 변경에는 별도 계획과 동의가 필요합니다.

로컬 범위/unknown/변경/영수증 변조 모의 테스트 및 기준/네이티브 속성/
조기 중단/파일 왕복 테스트를 통과했습니다. 기여자의 펌웨어 진입/복구는
실행하지 않았습니다. 공통 그래프 EFI는 별도로 빌드/검증했지만 이 계획에서는
USB에 기록하거나 실행하지 않습니다.

출처:
[ASUS 정확한 모델 설명서 페이지](https://www.asus.com/uk/motherboards-components/motherboards/tuf-gaming/tuf-gaming-b550m-e/helpdesk_manual?model2Name=TUF-GAMING-B550M-E),
[ASUS SecureBoot FAQ](https://www.asus.com/global/support/faq/1049829/).
FAQ는 다른 보드를 예시로 들며 인터페이스 차이를 경고합니다.
이 테스트는 스크린샷을 가정하지 않고 BIOS4101의 실제 메뉴를 관찰합니다.
