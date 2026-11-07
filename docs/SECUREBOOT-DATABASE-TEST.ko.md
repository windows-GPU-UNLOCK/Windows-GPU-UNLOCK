# Windows 전용 Secure Boot 데이터베이스 관측

[English](SECUREBOOT-DATABASE-TEST.en.md)

고정 소스를 새로 풀고 관리자 PowerShell에서 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-secureboot-databases.ps1
```

Windows를 통해 현재 Secure Boot 상태와 공개 `db`/`dbx` 변수 바이트를 읽습니다.
PK/KEK 읽기, 키 수정/등록/삭제, 설정 변경, 미디어 준비 또는 EFI 실행은 하지
않습니다. Python/LLVM/다운로드/재부팅은 필요 없습니다.

출력된 Documents 폴더의 검토한 `secureboot-databases.json`만 보내 주세요.
제한된 목록/항목 개수와 정확한 Microsoft 공개 CA 네 개의 일치 개수만 포함합니다.
사용자/알 수 없는 인증서 내용, 이름, 소유자 GUID, 해시 및 원본 변수는 내보내지
않습니다. `dbx`는 `db`와 구분하며 전체 이미지 폐기/SBAT 검사는 하지 않습니다.
불명/잘못된/접근 불가 데이터는 계속 불명이며 진행 허용이 아닙니다.

향후 신뢰 부팅 경로 조사를 위한 관측일 뿐, 서명 없는 EFI 신뢰, 서명 허용 또는
GPU 지원 증거가 아닙니다. Secure Boot를 활성 상태로 유지하고 EFI 준비/부팅이나
펌웨어 정책을 변경하지 마세요. 접근/플랫폼 지원이 없으면 작은 보고서를 보내고
중지하세요. 다른 오류는 개인 경로를 지운 짧은 오류만 보고하며 도구 설치,
권한/설정 변경 또는 하드웨어 재시도를 하지 마세요.

합성 목록, 잘못된 길이, 개인 페이로드 제거 및 모의 조회 실패를 검사했습니다.
Microsoft 공식 인증서 파일로 공개 참조의 정확한 인식도 로컬에서 검사했습니다.
소유자의 인증서/펌웨어 데이터는 저장소에 포함하지 않습니다. `-SelfTest`는
펌웨어를 조회하지 않습니다. 보고된 소스 관측값은 하드웨어 검증이 아닙니다.

참조: [Microsoft Get-SecureBootUEFI](https://learn.microsoft.com/en-us/powershell/module/secureboot/get-securebootuefi?view=windowsserver2025-ps),
[Microsoft 키 지침](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-secure-boot-key-creation-and-management-guidance?view=windows-11).
공개 DER 지문/출처 URL은 `tools/secureboot-ca-references.json`에 있으며 실행 시
네트워크 조회는 없습니다.
