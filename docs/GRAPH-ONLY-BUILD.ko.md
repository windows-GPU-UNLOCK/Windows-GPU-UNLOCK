# 그래프 전용 진단 빌드 검토

[English](GRAPH-ONLY-BUILD.en.md) | **한국어**

#33을 위한 개발 준비입니다. EFI 부팅 지침이 아닌 **빌드 전용 테스트**입니다.
PATH에 Python과 LLVM(`clang`, `lld-link`)이 필요합니다.
압축을 푼 소스 폴더에서 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\build-graph-only.ps1 -Fixture
```

예상 메시지는 `Graph-only build verified`입니다.
`internal-boot\boot\build\graph-only`의 `manifest.json`, `pe-verification.json`을
검토한 뒤 보내주세요. EFI 바이너리나 펌웨어는 첨부하지 마세요.
도구 누락, 컴파일 오류, 실행 정책 차단 시 개인 경로를 지운 짧은 오류만 보내고
중단하세요. 이 선택적 검사를 위해 도구를 설치하거나 정책을 변경하지 마세요.

**모의 이미지 파일을 부팅 장치에 복사하거나 실행하지 마세요.** Windows 파티션
GUID가 비어 있으므로 검증된 Windows 인계가 불가능합니다. 빌드 스크립트는 USB를
준비하거나 부팅 항목을 생성하거나 설정을 바꾸지 않습니다.

별도 그래프 구성은 심층 읽기 진단 및 드라이버 해제 소스를 제외합니다.
향후 별도 검토한 장비 전용 계획으로 부팅한다면 프로토콜/열기 기록, 경로,
GOP 모드 정보, 콘솔 변수, 64바이트 PCI 헤더를 읽고 새 로그를 쓴 뒤 기존 Windows
인계를 시도하는 범위입니다. GPU MMIO/PROM 읽기, 드라이버 이미지 덤프, 드라이버
해제, 언락은 하지 않습니다. 펌웨어 호출과 복귀 경로는 실기기로 검증하지 않았고,
완전한 로컬 프로필 캡처도 아닙니다.

빌드는 출력 폴더의 별도 생성 헤더를 사용하며 기존 설정의 `platform-config.h`를
덮어쓰지 않습니다. 별도 `-WindowsEspGuid` 빌드도 검토된 개발용이며 매체 준비나
부팅 허가가 아닙니다. 문서와 manifest는 소스 범위를 설명하며 특정 펌웨어의
안전한 동작을 입증하지 않습니다.
