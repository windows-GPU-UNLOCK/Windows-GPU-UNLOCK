# X570 AORUS ELITE F41c / RTX3090 FE 리소스 연구 준비

상태: 소스/빌드/준비 검증은 완료했지만 이전 그래프 부팅이 Windows로 직접
복귀했는지 소유자가 보고할 때까지 실제 실행 제안은 보류합니다. 그래프 해시
1f04a81a939da4ed52aa93404edadf15ccbc904712bd75d1e837e246043d50ae는
완전/status0이며2204/147d10de, segment0/bus8/device0/function0 및 GOP 프로토콜
연결1개를 보입니다. 수집/업로드 성공으로 Windows 복귀를 추론하지 않습니다.
정확한 Windows 조건: X570 AORUS ELITE/F41c/Gigabyte/5800X, NVIDIA 어댑터1개.

새 issue172 데이터는 공유 리소스 엔진을 재사용합니다. 드라이버 해제, GPU/PCI
쓰기, decode 활성화, 리셋, GPU 펌웨어 실행/업로드 또는 잠금 해제는 없습니다.
그래프 동의에 포함되지 않은 새 범위: PCI 리소스/속성/부모 읽기, 고정 BAR0
DWORD16개, 전체1MiB PROM(최대262160 직접 MMIO 읽기), CPU 메모리의 드라이버
이미지, USB 로그 및 Windows 복귀 시도입니다. 읽기도 부작용을 가질 수 있으며
펌웨어/화면/입력이 멈추거나 Windows 시작이 실패할 수 있습니다. 복구는 미검증입니다.
자동 재부팅/재시도/롤백은 없습니다. 미래 실행 제안은 전원 끄기/USB 제거/정상
Windows Boot Manager 복구와 반복 금지를 포함해야 합니다. 보호/암호화/디스플레이/
설정은 유지하며 알 수 없음/거부 시 중지합니다.

컴파일러 없는 리소스 템플릿은 그래프 fixture와 별개로31744바이트이며 SHA:
f8a8b25ee0e8e02dcd0645f0a0285b7625cd3c302a6a0d5e34bd3f72e0c2e5ab.
추적 소스/헤더775개와 생산 프로브 매니페스트를 고정하고 오프셋26624의 Windows
ESP GUID16바이트만 변경합니다. device220410de/sub147d10de/bus8/segment0은
컴파일 상수이며 설정으로 변경하지 않습니다. issue172만 이 경로를 사용합니다.
빈/센티널 GUID, 변경된 소스/이미지, 다른 사례, 기존 출력은 거부합니다.
원본 템플릿이나 샘플 GUID 이미지를 부팅하지 마세요.

컴파일러/하드웨어 조회 없는 오프라인 재현 명령:
```powershell
powershell -NoProfile -File .\research\profile\test-resource-template.ps1
```
GUID 데이터/소스/범위/기기/준비/거부 PASS가 예상됩니다. 로컬 검증 반복용 소유자
재실행/파일은 필요하지 않습니다. 재현 실패 시 짧은 개인정보 제거 오류만 보고하고
원본 보존 후 중지합니다.

개인화 샘플은 별도 컴파일 이미지와 전체 바이트가 같습니다:
SHA9027cf308e2bb89d288a8e1bd92259994db552a4b0be8c59cc4a9faf6ddb02e9,
AMD64 EFI31744B/수입0/NX/dynamicbase. 소스/매니페스트/사례/GUID/덮어쓰기/손상
거부, 그래프 로그 보관, 로더 백업/읽기 검증 및 반복 거부와 기존 공유 준비 테스트를
통과했습니다. 실제 하드웨어 실행은 하지 않았습니다. 준비 경로는 새 ACCEPT-MMIO
동의 전에 GRAPH-DIRECT를 요구합니다. 이는 소유자 보고/동의이며 독립 복구 증명이
아닙니다. 이 문서만으로 실행을 요청하지 않으며 별도 검토 실행 제안을 기다립니다.
