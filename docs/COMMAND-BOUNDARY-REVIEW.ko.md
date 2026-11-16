# 기존 command 경계 검토 (#164)

고정 검토 소스에서 실행하고 기존 공개 로그 폴더를 선택하세요.

```powershell
powershell -NoProfile -File .\research\profile\test-command-log.ps1
```

기존 Python3 실행 파일로 RUN0002-fail.TXT, RUN0004-ok.TXT,
RUN0005-ok.TXT만 읽어 숫자 기록과 파일 해시를 내보냅니다. 제공된 코드 실행,
PCI/GPU/펌웨어 접근 또는 설정 변경은 없습니다. 표시된 Documents 폴더의 검토한
command-review.json만 보내세요. 누락/모호함/차단이면 중지하고 개인 정보를
제거한 짧은 오류만 보내세요. 새 로그 생성, 빌드, 기록 수정 또는 실패한
하드웨어 실험 반복을 하지 마세요.

공개 RUN0002는 started=0이지만 retained=1, DMA_live=20612입니다.
펌웨어 미시작은 할당/매핑이 없거나 완전히 정리됐다는 뜻이 아닙니다.
RUN0004/5는 transaction result0/safe1/retained0/DMA_live0을 기록합니다.
wrapper 진입 command0과 달리 transaction-original command2로 복원합니다.
이는 transaction 정리와 wrapper 진입 상태 복원을 구분하며 Windows 전달에
반드시0이 필요하다는 결론이나 독립 하드웨어 증거가 아닙니다.
로컬 패치는 timeout 기본값을 stock으로 바꾸고 명시적 U를 요구합니다.
일반 호환성/안전성 또는 upstream 승인을 의미하지 않습니다.
