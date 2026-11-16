# 기존 로컬 드라이버 허용 목록 변경 검토

#165의 원래 테스트 소스, 생성 프로필과 영수증을 그대로 보존하세요.
별도로 압축 해제한 고정 검토 소스에서 실행하세요.

```powershell
powershell -NoProfile -File .\research\profile\test-profile-review.ps1
```

물어보면 원래 테스트한 소스 폴더를 선택하세요. 신뢰된 검토 스크립트가
프로필과 기존 호스트 영수증/소스 연결을 확인합니다. 그 폴더의 코드를
실행하거나 빌드, 준비, 부팅하지 않습니다. 저장된 proven.json의 버전/해시를
검토 소스와 global, family, card 범위별로 비교합니다. 숫자 ID와 해시만
내보내며 evidence 문자열/경로는 제외합니다. 차이는 검토 버전 기준이며 원래
upstream diff의 증거가 아닙니다. 드라이버 승인 또는 안전성 증거도 아닙니다.

#165의 공개 변경과 일치하면 global 및 family/GA106에 60014/1226b2cb... 추가를
예상합니다. 삭제 행은 소스 버전 차이일 수 있습니다. 메모리 0x3000은
12288 MiB입니다. HardwareIndependentlyVerified, RecoveryVerified,
WriteEligible, DriverEnvelopeComparison.AdmissionGranted는 false를 유지합니다.

출력된 Documents 폴더의 검토한 profile-review.json만 보내세요. 기존 증거/소스가
불일치하거나 사용할 수 없으면 중지하고 개인 정보를 제거한 짧은 오류를 보내세요.
통과하려고 파일 수정, 프로필 재생성, 호스트 테스트 재실행 또는 하드웨어 반복을
하지 마세요. 설정 또는 케이블 변경은 필요하지 않습니다.
