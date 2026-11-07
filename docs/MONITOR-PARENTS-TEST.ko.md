# Windows 모니터 장치 부모 관계 관찰

[English](MONITOR-PARENTS-TEST.en.md)

이 Windows 읽기 전용 진단은 모니터의 장치 부모 링크를 따라 비디오 컨트롤러와의
관계를 확인합니다. 케이블, MUX, 드라이버, 펌웨어 설정이나 전원 상태를 변경하지
않습니다. 물리적 화면 경로, 부팅 전 GOP 소유권 또는 잠금 해제를 검증하지 않습니다.

고정된 소스 ZIP을 푼 폴더에서 PowerShell을 열고 실행하세요. 관리자 권한,
컴파일러, Python, USB 또는 재부팅은 필요하지 않습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-monitor-parents.ps1
```

출력된 Documents 폴더에서 검토한 monitor-parents.json만 보내주세요.
숫자로 된 활성/출력 기술 정보와 associated, unknown, ambiguous, cycle,
hop-limit 상태가 예상됩니다. API 또는 접근 권한이 없으면 unavailable도
정상적인 관찰 결과입니다. 출력 기술 숫자만으로 화면 경로를 증명하지 않습니다.
부모 탐색은16단계, 모니터32개, 어댑터16개로 제한됩니다. 장치 인스턴스 ID,
이름, 일련번호와 오류 메시지는 내보내지 않습니다. 일치한 PCI 공급업체/장치/
서브시스템 숫자만 남깁니다.

오류 또는 unknown 결과 후에는 중단하세요. 생성된 작은 보고서 또는 개인 경로를
제거한 짧은 오류만 보내세요. 테스트를 통과하려고 설치, 정책 변경, 가상 어댑터
비활성화 또는 화면/펌웨어 설정 변경을 하지 마세요.

로컬 자체 테스트는 부모 일치, 개인정보 제외, 읽기 실패/다중 부모, 순환,
중복 어댑터, WMI 접미사 및 범위 제한을 검증합니다. 로컬 Windows 보고서 실행과
기여자의 하드웨어 관찰은 별개의 증거입니다.
