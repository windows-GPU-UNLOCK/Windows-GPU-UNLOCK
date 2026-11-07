# BCD 애플리케이션 경로 관찰

[English](BCD-APPLICATION-PATH-TEST.en.md)

이전 필수 조건 보고서에서 표준 Windows 부팅 관리자 경로를 관찰하지 못한
경우에 사용합니다. 지역화된 BCDEdit 텍스트 대신 형식이 지정된 BCD
ApplicationPath 요소를 읽습니다. 복구 또는 신뢰를 증명하지 않습니다.

고정 소스 폴더의 관리자 PowerShell:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-bcd-application-path.ps1
```
출력된 Documents 폴더의 검토한 bcd-path.json만 보내주세요.
standard-windows-uefi, other, missing-or-invalid 또는 unknown이 예상됩니다.
다른 경로의 실제 값은 내보내지 않습니다. unknown도 허용됩니다.
컴파일러, Python, 설치, USB 또는 재부팅은 필요하지 않습니다.

현재 시스템 저장소의 OpenStore, Windows Boot Manager의 OpenObject,
ApplicationPath의 GetElement만 호출합니다. 설정 메서드, 저장소 가져오기/
내보내기, 부팅 항목 변경, 장치 열거, 복구 키 접근 또는 펌웨어 변경은 없습니다.
실제 경로, 개체 식별자 또는 공급자 오류를 내보내지 않습니다.
어떤 결과도 정책, 암호화, BCD 또는 Secure Boot 변경을 허용하지 않습니다.

오류 또는 unknown이면 보고서를 보내고 중단하세요. 통과하려고 권한 변경,
공급자 설치, BCD 복구 또는 설정 변경을 하지 마세요. 복구 및 EFI 실행은
별도 검토와 충분한 설명에 따른 동의가 필요합니다.

로컬 모의 테스트는 정확한 세 호출, 엄격한 boolean 반환값, 표준/기타/누락 경로,
오류 제외를 검증합니다. 실제 로컬 Windows에서는 OpenStore가 false를 반환하여
unavailable 보고서가 생성됐습니다. 성공적인 실제 BCD 읽기는 여기서 미검증입니다.

Microsoft 문서:
[OpenStore](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/bcd/openstore-bcdstore),
[OpenObject](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/bcd/openobject-bcdstore),
[GetElement](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/bcd/getelement-bcdobject),
[ApplicationPath](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/bcd/bcdlibraryelementtypes).
