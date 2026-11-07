# 공개 부팅 정책 기준 기록과 비교 (준비 전용)

[English](POLICY-BASELINE-TEST.en.md)

이 도구는 향후 검토된 참석 정책 계획의 기준 기록/비교 부분만 제공합니다.
계획이나 실행 허가 자체가 아닙니다. 펌웨어 메뉴, 키 등록/삭제, 암호화,
BCD, USB 준비, 재부팅 또는 EFI 실행을 변경/수행하지 않습니다.
현재 준비 스크립트는 SecureBoot가 켜진 상태를 계속 거부합니다.

기본 오프라인 테스트:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\test-policy-baseline.ps1
```
합성 상태와 임시 JSON만 사용하며 Windows 조회는 없습니다.
변수/설정 변경, 엄격한 거부, 개인정보 제외, 파일 왕복 테스트의 PASS가 예상됩니다.
통과는 소스 동작만 뜻하며 실제 복구나 펌웨어 증거가 아닙니다.

별도로 선택하는 Record/Verify 모드는 완전한 검토 계획에서만 사용하도록
준비되었습니다. Record는 정확한 현재 기기/설정, SecureBoot 켜짐, 시스템 볼륨의
완전 복호화, 형식화된 표준 Windows UEFI 부팅 관리자 관찰이 필요합니다.
Windows를 통해 공개 PK,KEK,db,dbx 변수를 읽습니다. 비공개 서명 키나 복구 키는
읽지 않습니다. 제한된 바이트를 메모리에서 해시한 뒤 버리고 해시/크기/속성만
로컬 baseline.json에 남깁니다. 이 파일은 로컬에 비공개로 보관하고 첨부하지 마세요.

Record는 기존 기준을 덮어쓰지 않습니다. Verify는 원래 기준을 읽고 현재 관찰을
반복하여 설정 및 네 공개 변수의 지문/크기/속성을 비교합니다.
변경/알 수 없음/암호화/꺼짐 상태는 observations-match가 될 수 없습니다.
작은 policy-check.json에는 지문, 원시 변수, 식별자나 경로를 넣지 않습니다.
일치는 해당 관찰만 같다는 뜻이며 복구, 펌웨어 신뢰, 실행, 숨은 설정 또는
하드웨어 안전을 검증하지 않습니다. 허가 플래그는 false입니다.
저장소 무결성/출처도 증명하지 않으며 다른 보호 조건을 우회하지 마세요.

로컬 합성/거부/파일 왕복 테스트를 통과했습니다. 기여자 기기의 Record/Verify는
실행하지 않았습니다. 두 모드 실행이나 펌웨어 진입 요청이 아닙니다.
새 하드웨어 범위 전에 정확한 펌웨어 제어, 복구/원상 복원 설명과 소유자의
충분한 이해에 따른 동의가 필요합니다. 알 수 없음/불일치/오류이면 중단하고
통과하려고 설치/변경/복구하지 마세요.

Windows API:
[Get-SecureBootUEFI](https://learn.microsoft.com/en-us/powershell/module/secureboot/get-securebootuefi?view=windowsserver2025-ps).

캡처된 암호화/보호 해제 fixture는 보고된 Device Encryption 상태를 재생합니다. 공개 변수 조회 전에 거부합니다. 암호화가 자동이었는지 의도적이었는지는 허용 입력이 아닙니다. fixture는 clear-key/보호자 출처나 복구를 검증하지 않습니다.

설치된 SecureBoot 메타데이터에서 Attributes는 단순 정수가 아니라 UInt64 Attributes 속성을 가진 네이티브 래퍼임을 확인했습니다. 기준 정규화는 정확한 형식과 UInt32 범위만 허용합니다. 로컬 래퍼 생성/직렬화/속성 변경/범위 초과 거부 테스트는 펌웨어 변수를 읽지 않고 통과했습니다. 권한 없는 로컬 db 읽기는 거부되었으며 성공적인 실제 Record/Verify는 미검증입니다.
