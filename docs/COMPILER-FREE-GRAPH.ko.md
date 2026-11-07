# 컴파일러 없는 고정 그래프 준비

-PackagedGraph는 별도 그래프 전용 템플릿을 사용하며 기존의 부팅 금지 zero-GUID
fixture를 사용하지 않습니다. 템플릿 SHA256:
7070d624c00cb4d194ae03626f336ae0b02b279716ffb42f6b53cf5609c5ee60.
모듈은 템플릿 매니페스트와 기록된761개 추적 C/헤더 입력을 고정합니다.
파일 오프셋10752의16바이트만 현재 내부 Windows ESP GUID의 UEFI 바이트 순서로
설정합니다. 빈/센티널 GUID, 소스/바이트 변경, 기존 출력은 거부합니다.
그 필드 밖 코드/PE 바이트는 바뀌지 않습니다. 로컬 컴파일이 아닌 데이터 설정이며
BuildPerformed=false입니다. 원본 템플릿을 부팅하지 마세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue172 -PackagedGraph
```
컴파일러/설치/PATH 변경은 필요하지 않습니다. 기존 정확한 기기/디스플레이,
SecureBoot 이미 꺼짐, 완전 복호화 볼륨, 유일한 Windows ESP, USB ID, PREPARE 동의,
백업/읽기 검증, 빈 캡처 폴더 및 일회 중지 조건을 모두 유지합니다. GUID는 로컬에
남습니다. 자동 종료/재부팅/재시도나 펌웨어 변수 쓰기는 하지 않습니다.
하드웨어 범위도 동일합니다: 프로토콜/GOP 정보, 콘솔 변수, PCI 헤더 읽기,
USB 로그 및 Windows 복귀 시도. MMIO/PROM/이미지/드라이버 해제/잠금 해제는 없습니다.
펌웨어/화면/입력이 멈출 수 있으며 이 사례의 Windows 복귀/복구는 검증되지 않았습니다.

소유자 동의와 READY 후에만 수동 종료하고 USB를 한 번 선택합니다.2분 안에
Windows가 시작하지 않으면 전원을 끄고 USB를 제거한 뒤 정상 Windows Boot Manager를
사용합니다. 복구 실패 시 중지하고 재시도하지 않습니다. 같은 명령에 -Collect를
추가해 기존 로그를 수집합니다(이때만 기존 Python 필요). 검토한 graph-summary.json과
Windows 직접/수동 복귀 여부만 반환합니다. EFI/로그/백업은 로컬에 보관합니다.
불일치/오류 시 설치, 가드 수정 또는 설정 변경 없이 중지합니다.

검증: 별도 컴파일한 샘플 GUID 이미지와 설정된 이미지의 전체 바이트가 같습니다
(SHA7974eb71bfd46eec67672d31ee437d34b1da1c248082f7b0fc25179ff8765b52).
AMD64 EFI14848바이트/수입0/NX/dynamicbase를 확인했습니다. GUID 바이트 순서,
761개 소스 고정, 빈/센티널/기존 출력/소스 누락/이미지 손상 거부와 기존 모의
준비/백업/캡처 보존 테스트를 통과했습니다. 실제 부팅은 여기서 수행하지 않았습니다.
이전 graph-only.fixture는 계속 부팅 금지이며 이 옵션에서 사용하지 않습니다.
