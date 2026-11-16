# Windows 수집기 테스트

[English](COLLECTOR-TEST.en.md) | **한국어**

#27, #110, #127, #130에서 보고된 Unicode 읽기 스레드 오류를 확인합니다.
모의 검사를 실행한 다음 Windows 하드웨어 목록을 수집합니다. Windows,
Python, 일반 PowerShell 창이 필요합니다. 관리자 권한, 재부팅, USB, EFI,
펌웨어 설정 변경은 필요하지 않습니다.

다운로드한 소스 폴더에서 다음 **명령 하나**를 실행하세요.

```powershell
powershell -NoProfile -File .\tools\test-collector.ps1
```

실행 정책으로 차단되면 중단하고 개인 정보를 지운 짧은 오류를 알려주세요.
정책 변경, 파일 차단 해제, process bypass 또는 다른 실행 경로로 우회하지 마세요.
스크립트가 시작되지 않으면 result.json이 없는 것이 정상입니다.
소스 hash나 ZIP manifest는 publisher trust를 입증하지 않습니다.

예상 결과는 `Result: PASS`입니다. 스크립트가 새
`문서\GPU-Unlock-Collector-Test-<id>` 폴더 위치를 표시합니다.
`inventory.json`의 예상 값은 `collection_complete: true`,
`assessment.status: not-assessed`, `can_unlock: false`입니다.
`UnicodeDecodeError`가 나타나지 않아야 합니다. GPU 잠금 해제나 하드웨어
지원을 검증하는 테스트는 아닙니다.

**회신할 자료:** 해당 폴더의 `result.json`, `inventory.json`을 검토한 뒤
기존 이슈에 첨부하고 Unicode 오류가 나타났는지 알려주세요. 전체 시스템 보고서,
펌웨어 이미지, 개인 경로가 보이는 스크린샷은 첨부하지 마세요. 수집기는 모델과
버전 필드만 선택하고 장치 인스턴스 접미사를 제거하지만 게시 전에 파일을 확인하세요.

결과가 `PARTIAL` 또는 `FAILED`이면 `result.json`과 생성된 경우
`inventory.json`을 보내주세요. 폴더가 생성되지 않았다면 개인 경로를 지운 짧은
오류 메시지만 보내주세요. 거기서 중단하세요. 재실행이나 설정 변경은 필요하지 않습니다.

## 기여자 확인

2026-11-01 [#27의 B550M / MSI 1462:5136 보고자](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/27#issuecomment-6558655010)는
프랑스어 Windows 11 Enterprise 빌드 26100에서 일반 사용자 권한으로 재부팅이나
설정 변경 없이 실행하여 Unicode 오류 없는 `PASS`를 보고했습니다.
검토한 첨부 파일의 수집기 SHA-256은
`1c25e3195222a586108ce8f2b60fa42750f56e927a6c3f4c58839eb8df212a2e`이며,
두 프로세스 종료 코드는 0, 목록 수집은 완료, `can_unlock`은 false였습니다.
이는 해당 기여자의 수집기 실행 보고만 확인합니다. 다른 환경 및 GPU 언락
검증은 별도입니다.

[#19의 Lenovo 1052 보고자](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/19#issuecomment-6559414071)도
프랑스어 Windows 11 IoT Enterprise LTSC 빌드 26100에서 관리자 권한이나 설정
변경 없이 이전 Unicode 오류 없는 PASS를 보고했습니다. 검토한 두 첨부는 같은
수집기 해시, 종료 코드 0, 완전한 목록, 예상 GPU `2504 / 1043:881d`와 일치합니다.
두 번째 기여자 수집기 확인이며 EFI나 언락 검증은 아닙니다.
# 일본어 Windows 디코딩 보고 (#201)

공통 회귀는 실제 child process의 UTF-8 일본어 inventory와 0x83으로 시작하는
CP932 stderr를 검사합니다. Dell 2504/c9741028은 합성 fixture이며 사용자 시스템의
재현이나 프로필 지원 증거가 아닙니다. PR176의 기존 binary subprocess capture가
이 경로를 수정합니다. 같은 launcher가 Windows inventory 전에 회귀를 실행합니다.
Secure Boot를 활성화 상태로 유지하세요. PASS는 firmware 경로나 프로필 승인이 아닙니다.

#201 사용자는 실행 전 unsigned-script 정책 차단을 보고하고 요청대로 중단했습니다.
결과 파일은 생성되지 않았으며 일본어 호스트 수집기 실행은 미검증입니다.
해당 정책에서 신뢰되는 publisher/signing 배포 경로가 확인되지 않았습니다.
이는 배포 선행 조건이며 새 inventory 실행이나 정책 완화 요청이 아닙니다.
