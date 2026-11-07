# 기존 캡처 보고서 출처

Issue114 댓글6570205099는 topology_scope 해소를 보고하지만 첨부34257674/34257675를 독립적으로 읽으면 outside_scope 및 자식3개/허용2개가 남아 있습니다. 두 관찰을 모두 보존하며, 지정 소스/실행에서 생성된 파일이라고 단정하지 않습니다. 새 캡처나 부팅을 요청하지 않습니다.

v2 실행기는 무작위 run_id, 실행기/검사기/생성기/범위 파일의 SHA256, report.json의 정확한 바이트 해시를 기록합니다. 실행 후 소스 해시를 다시 비교하고 변경되면 거부합니다. 로컬 출처 확인용이며 인증된 증명이나 하드웨어/콜드 부팅 증명이 아닙니다. 보고서 해시는 두 파일의 연결만 확인하며 입력의 출처는 증명하지 못합니다. v1 파일도 증거로 보존하되 소스 출처는 미확인입니다.

고정 체크아웃에서 같은 기존 캡처 폴더로 실행합니다:

```powershell
powershell -NoProfile -File tools/test-existing-captures.ps1
```

보고된 자식3개 입력의 예상 결과: topology_scope 해소, 캡처1개의 capture_count 유지, hardware_tested/write_eligible false. 여기서는 비공개 입력을 재실행하지 않았습니다. 로컬 `python research/profile/test_capture_receipt.py`는 빈 픽스처로 실제 실행기를 두 번 실행해 고유 ID, 보고서/소스 해시 및 개인 경로 미포함을 확인합니다. 기여자의 캡처 검증은 아닙니다.

새로 출력된 한 결과 폴더의 검토한 report.json과 result.json만 함께 반환하세요. result의 test는 existing-capture-refusal-v2여야 합니다. 선택적 -OutputRoot는 기존 쓰기 가능한 출력 폴더를 지정하며 정책/설정 변경이 아닙니다. 차단이나 소스/검사 실패 시 중단하고 result.json이 있으면 보존해 짧은 정제 오류를 보고하세요. 설치, EFI, 새 캡처, 모니터 변경, 자동 재시도는 없습니다.

인터프리터는 일반 명령 우선순위대로 첫 Application 일치 항목을 선택하며 실행 경로를 합치지 않습니다. 실제 실행기 테스트는 신뢰된 대체 조회로 여러 일치 항목도 검사하고 PATH 변경이나 Python 설치는 하지 않습니다. 명시적 -Python도 사용할 수 있습니다.
