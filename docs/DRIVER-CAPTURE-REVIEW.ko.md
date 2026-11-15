# 기존 캡처의 드라이버 코드 검토

[English](DRIVER-CAPTURE-REVIEW.en.md)

자동 검사기는 앞선 토폴로지 거부 이후 드라이버 코드 검사를 건너뜁니다.
이 오프라인 테스트는 최신 완료 캡처에서 기존 make-profile.py의 PE 범위,
Stop 콜백 범위, 재배치 및 코드 해시 검사를 재사용합니다. 프로필 허용과
별개인 관찰입니다. generate() 호출, proven.json 변경 또는 실행 허가는 없습니다.

Windows에 이미 설치된 Python을 사용합니다. 고정 소스를 푼 폴더의 일반 PowerShell:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\test-driver-capture.ps1
```
검토된 리소스 캡처의 DIAGnn.TXT와 IMGnn.BIN이 있는 기존 폴더를 입력하세요.
새 캡처, 컴파일러, 관리자 권한, USB 준비 또는 부팅은 필요하지 않습니다.
출력된 Documents 폴더의 검토한 driver-review.json만 보내주세요.
DIAG/PROM/IMG 및 백업 파일은 로컬에 변경 없이 보관하세요.

보고서는 캡처/코드 해시, 숫자 버전/크기, 고정 역할과 상태만 포함합니다.
드라이버 경로, 원시 이미지, 핸들, 주소, 파서 예외는 내보내지 않습니다.
정확히 알려진 NVIDIA GOP 및 EDID 파일만 검사하며 알 수 없는 드라이버는
추측하지 않습니다. 누락/거부된 이미지는 그대로 남기고 대체 파일을 만들지 마세요.

listed_nvgop_code는 전역 검토 목록의 버전과 코드 해시 일치만 뜻합니다.
이 보드의 소유권/해제, 서명 신뢰, 기기별 허용, 별도 콜드 부팅, 트랜잭션이나
Windows 복귀를 검증하지 않습니다. 허가 플래그는 모두 false입니다.
하나의 코드 지문은 프로필이 아닙니다.

unavailable/invalid이면 보고서를 보내고 중단하세요. 오류는 개인 경로를 제거한
짧은 메시지만 보내세요. 통과하려고 도구 설치, 설정 변경, 프로필 생성,
USB 준비 또는 부팅을 하지 마세요.
