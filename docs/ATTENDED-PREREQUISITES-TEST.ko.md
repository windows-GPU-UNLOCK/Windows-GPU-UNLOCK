# Windows 전용 참석형 계획 사전 조건

[English](ATTENDED-PREREQUISITES-TEST.en.md)

이 테스트는 사전 조건 관측이며 Secure Boot 해제 안내나 EFI 실행 허용이 아닙니다.
펌웨어 정책/키, 암호화, BCD, 케이블, 클록 또는 장치 설정을 변경하지 않습니다.
USB 준비, 키 복구, 설치, 재부팅 또는 EFI 실행도 하지 않습니다.

고정 소스를 새로 풀고 관리자 PowerShell에서 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-attended-prerequisites.ps1
```

현재 Secure Boot 상태, 시스템 볼륨의 BitLocker 보호/변환 상태 및 읽기 전용 BCD
조회에서 Windows 부팅 관리자 경로를 읽습니다. GetProtectionStatus와
GetConversionStatus만 호출하며 복구 암호, 보호기 ID나 키는 조회하지 않습니다.
볼륨 ID, 원본 BCD, 예외 메시지나 개인 경로는 내보내지 않습니다. BitLocker
공급자 데이터이며 다른 암호화 제품이나 다른 볼륨 전체에 대한 증거가 아닙니다.

출력된 Documents 폴더의 검토한 `attended-prerequisites.json`만 보내 주세요.
불명/접근 불가는 계속 차단 조건입니다. 암호화된 볼륨의 보호만 꺼진 상태를
완전히 복호화된 것으로 취급하지 않습니다. 부팅 관리자 경로 관측은 복구나
펌웨어 실행 증명이 아닙니다. 어떤 결과도 정책 변경, EFI 준비/부팅 또는
잠금 해제 허용을 부여하지 않습니다.

Secure Boot, 키와 설정을 유지하세요. 오류 시 개인 경로를 지운 짧은 오류만
보고하고 중지하세요. 이 테스트를 위해 암호화 해제, 권한 변경 또는 설치를
하지 마세요. 복구 자료는 개인적으로 보관하고 공유하지 마세요.

목적은 선택적이며 별도로 수락하는 참석형 연구 계획 검토 전에 필요한 실제
조건을 확인하는 것입니다. 기존 CA/데이터베이스 관측은 신뢰된 서명 EFI 경로를
입증하지 않습니다. 향후 정책 변경은 별도의 충분한 설명에 따른 결정과 검토된
복구/복원 계획이 필요하며 이 스크립트는 변경을 수행하거나 요청하지 않습니다.

로컬에서는 복호화/보호 일시 중지/암호화/실패/불명, 정수가 아닌 입력의 거부,
부팅 관리자 경로/오류 제거 및 실제 Windows 조회/보고를 검사했습니다.
부팅 복구는 테스트하지 않았습니다.

참조: [Microsoft GetConversionStatus](https://learn.microsoft.com/en-us/windows/win32/secprov/getconversionstatus-win32-encryptablevolume),
[GetProtectionStatus](https://learn.microsoft.com/en-us/windows/win32/secprov/getprotectionstatus-win32-encryptablevolume),
[BCDEdit /enum](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--enum).

준비 과정은 빌드 전과 USB 기록 전에 현재 시스템 볼륨의 완전 복호화 상태를 확인합니다. 암호화된 데이터가 남은 보호 해제 상태, 알 수 없는 상태, 공급자 실패 또는 상태 변경은 거부합니다. 테스트를 위해 보호 일시 중지, 복호화 또는 설정 변경을 하지 마세요. 기존 파일 수집에는 이 USB 준비 조건을 적용하지 않습니다.
