# 기존 NVIDIA 펌웨어 코드 검토

Issue203은 이미 완전한 캡처2개와 GA106/6000a driver_scope 거부를 보고했습니다. 새 캡처를 요청하거나 GA102 허용 항목을 GA106에 복사하지 않습니다. 현재 main fd8bbea의 코드8924ba488419e5d82b524d10e8dd63bfe886f077026fae1a9cc03e25b920b276/6000a는2204 전용이며 GA106은60010입니다. 보고된 접두부만으로 전체 코드 신원을 검증할 수 없습니다.

```powershell
powershell -NoProfile -File tools/test-existing-nvgop-code.ps1
```

기존 DIAG/IMG 폴더를 선택합니다. make-profile의 바인딩/PE/재배치/코드 범위 검사를 재사용합니다. 이미지를 데이터로만 읽고 전체 이미지/코드 해시, 버전, 코드 길이/RVA와 Stop 오프셋을 내보냅니다. matching_family_code_entries는 체크아웃 범위만 의미하며 현재 업스트림이나 카드 자격이 아닙니다. 메모리 주소, 개인 경로, 원시 펌웨어는 반환하지 않습니다. 해시는 바이트 신원이며 드라이버 해제 동작이나 하드웨어 안전성 증명이 아닙니다.

출력 폴더의 검토한 nvgop-code-review.json만 반환하세요. 예상 test는 existing-nvgop-code-v1, code_only true, hardware_verified/driver_release_verified/write_eligible false입니다. 기존 캡처 간 정확한 해시/메타데이터 일치는 검토 증거이며 허용 판정이 아닙니다. 미확인/변경 코드는 미검토 상태입니다. 오류/정책 차단/파일 누락 시 중단하고 원본을 보존해 짧은 정제 오류를 보고하세요. 설치, 설정 변경, 새 EFI/캡처, 프로필 플래그, 하드웨어 실험은 없습니다.

로컬 합성 테스트3개가 통과했습니다: 전체 신원/가족 구분, 중복/누락/잘린 이미지/코드 밖 Stop 거부, 승인 거짓/개인정보 필드. 실제 PowerShell 실행기도 합성 저장 이미지로 통과했습니다. 기여자 파일은 여기서 재실행하지 않았습니다.
