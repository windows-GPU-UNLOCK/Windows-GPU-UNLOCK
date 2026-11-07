# 기존 GOP 진단 기록 (#2)

보고된 Inno3D2782/16e110de의 MaxMode14/current15/framebuffer0/0은
GOP 핸들 부재가 아니라 framebuffer 없는 GOP입니다. 회귀 fixture는 보고된
값을 연결된 패치의 GOPDIAG 문법으로 옮긴 것이며 원본 하드웨어 로그나
펌웨어 테스트가 아닙니다.

```powershell
powershell -NoProfile -File .\research\profile\test-gop-records.ps1
```

기존 Python3를 사용하며 세 테스트 OK와 PASS를 예상합니다. 관리자가 이미
실행했으므로 제보자 반복은 필요하지 않습니다. 재현하면 PASS 또는 개인 정보를
제거한 짧은 오류만 보내세요. 도구 누락/정책 차단이면 중지하세요. 설치, 새 캡처,
EFI 부팅, 자동 재시도 또는 설정 변경은 없습니다.

review-gop-records.py는 기존 텍스트 파일의 phase/index/숫자 형태와 분류만
내보냅니다. 핸들과 framebuffer 주소는 제외합니다. 대상 ancestry, geometry,
SetMode/reconnect 권한, 하드웨어 증거와 write eligibility는 미검증/false입니다.
누락, 중복, 형식 오류와 범위 초과를 거부합니다. live/partial framebuffer나
비대상 기록으로 복구를 승인하지 않습니다.

연결된 Ada PR3/4는 실행 없이 소스로 검토했습니다. PR3는 대상 SetMode 외에도
발견된 모든 GOP와 ConsoleOut을 연결합니다. PR4의 실패한 GOP 조회는 부재와
비슷하게 처리되지만 임의 서비스 실패는 부재의 증거가 아닙니다. 여기서는 두
패치를 채택하지 않습니다. 원래4070 SUPER 및 MSI4070Ti 연구는 보고된
Inno3D4070Ti 성공과 별개이며 RTX4000 전체 지원을 의미하지 않습니다.
