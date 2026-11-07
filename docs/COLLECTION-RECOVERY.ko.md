# 기존 캡처 수집 오류 복구

Windows 수집 호스트만 변경합니다. 출력 폴더/Python 선택 오류를 해결하려고
하드웨어를 부팅/재빌드/USB 기록/반복 실행하지 마세요.

Get-Command가 여러 응용프로그램을 반환해도 PATH 우선순위의 기존 Python 하나만
선택합니다. 앱 별칭/누락/잘못된 경로는 중단합니다. -Python으로 이미 사용하는
정상 인터프리터를 지정할 수 있습니다. 설치나 영구 PATH/설정 변경은 없습니다.

Documents 폴더 생성 실패 시 -OutputRoot로 기존 쓰기 가능한 로컬 폴더를
선택하세요. 그 아래 고유 폴더를 생성하며 자동 대체나 캡처 USB 출력은 하지 않습니다.
그래프 수집 예:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue173 -Collect -OutputRoot "$env:TEMP"
```
리소스 수집도 같은 -OutputRoot를 받습니다. 이미 제공한 보고서가 사용 가능하면
이름만 바꾸려고 다시 수집하지 마세요. 원본 경로와 캡처 바이트는 변경하지 않습니다.
검토한 graph-summary.json 또는 report.json만 보내세요. 오류/unknown이면
개인 경로를 제거한 짧은 오류를 보내고 중단하세요. 권한/보호 설정/PATH/소스를
변경하지 마세요.

로컬 테스트는 다중 Python, 잘못된 형식/별칭/누락 거부, 대체 출력, 차단된 쓰기,
캡처 보존과 오류 제외를 검증합니다. 실제 검사기의 합성 거부 데이터 출력과
issue31 태그도 실행했습니다. 소유자 하드웨어/Windows 복구는 여기서 미검증입니다.
