# 이슈92: Parsec 미확인 상태의 정확한 그래프 준비

보고된 구성은 B550M AORUS ELITE / FHb /5900X /2208:40851458,
EAGLE OC GV-N308TEAGLE-OC-12GD, 공장 VBIOS94.02.71.40.49,
NVIDIA HDMI입니다. 사용자는 소스 c403e8f0002ec69fc162a145d8172b2782ec9645와
참조 릴리스 v0.3.1을 구분했습니다. EFI/거부 로그는 없으므로 요구하지 않습니다.

새 issue92 설정은 공통 그래프 전용 엔진을 사용합니다. Parsec0.45.0.0의
펌웨어 ID는 검토되지 않았습니다. null/ROOT/SWD 픽스처는 서명된 드라이버
라벨을 넣어도 거부합니다. 제거/비활성/가드 우회는 하지 마세요. 소프트웨어
화면은 복구나 부팅 전 소유권 증거가 아닙니다.

고정 소스에서 선택적 CPU/파일 전용 명령을 실행합니다. 컴파일러는 불필요합니다.

```powershell
powershell -NoProfile -File .\research\profile\test-graph-offline.ps1 -Machine issue92 -PackagedFixture
```

예상은 PASS 및 새 Documents 폴더의 graph-build-test.json입니다. 선택 설정
issue92와 SHA256, ConfigurationTests/MockStagingTests=pass,
FixtureOnly=true, HardwareTested=false, WriteEligible=false를 확인합니다.
재현한다면 JSON만 공유하세요. 관리자는 이미 실행했습니다. 모의 백업/읽기
검증/캡처 보존은 임시 파일을 사용하며 실제 미디어를 사용하지 않습니다.
하드웨어 조회, EFI 실행, 설치, 설정 변경 또는 재부팅은 없습니다. zero-GUID
픽스처를 준비하거나 부팅하지 마세요. 오류나 하드웨어/쓰기 플래그 true이면
중단하고 설정을 유지합니다. 준비/거부 검증이며 잠금 해제 허용이나 참석형
실행 제안이 아닙니다.
