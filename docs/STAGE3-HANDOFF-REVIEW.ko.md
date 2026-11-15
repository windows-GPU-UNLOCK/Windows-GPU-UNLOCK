# Stage3 인계: 소스 검토와 DMA 유지 테스트

이슈21의 공개 stage3 압축 파일은40,139바이트이며 SHA256은
`6b1087e4ec42835475bfb3c5781f2d9a9b52865614bb75f27a9cdba7321624cc`입니다.
데이터로만 검토했고 빌드하거나 실행하지 않았습니다. 소스는 FE 서브시스템
검사 전에 첫3090을 선택하고 MMIO 상태를 무시합니다. 성공했지만 짧거나 높은
DMA 매핑을 Unmap 없이 해제하며 정리 시 Unmap/FreeBuffer 결과를 무시합니다.
이는 소스 관찰이며 실제 장비에서 실패했다는 증거가 아닙니다. 현재 port.c는
MMIO 결과, 장치 DMA 주소, 불확실한 자원 유지 처리를 이미 검사합니다.
이전 shim을 채택하거나 복사하지 않습니다.

기존 test_port.c를 확장해 부분/높은/정렬되지 않은 성공 매핑과
Unmap/FreeBuffer 실패의6조합을 검사합니다. 자원 유지, Unmap 실패 뒤 조기
해제 금지, 거부된 재할당의 출력0, 재진입 시 추가 Map/Unmap/Free 금지 및
GPU/PCI 쓰기 없음을 검증합니다. 테스트 정리 코드는 실제 재시도 경로가 아닙니다.

기존 clang/MSVC로 선택적으로 재현합니다.

```powershell
powershell -NoProfile -File .\research\profile\test-dma-boundary.ps1
```

-Clang/-VcVars는 기존 도구 경로에만 사용하세요. 예상은 native PASS 및 새
Documents/dma-boundary.json의 Test=dma32-rounded-boundary-v2,
InvalidMapCleanupFailureCases=6, RetainedMappingRetryRefused=true,
HardwareAccess=false, EfiExecuted=false, WriteEligible=false입니다.
재현한다면 JSON만 공유하세요. 관리자는 이미 실행했습니다. 실패하거나
하드웨어/쓰기 플래그가 true이면 중단합니다. 의존성 설치, EFI 부팅, 이전
인계 재실행, 파티션 또는 설정 변경은 하지 마세요.

지연 패치5바이트 외 동일 빌드라는 기여자 보고는 여기서 독립 재현하지
않았습니다. 절전 유지/최대 절전 초기화 보고는 해당 구현/장비에 한정되며
현재 지원이나 복귀 신뢰성을 입증하지 않습니다. 펌웨어 소유자는 unknown이며
AMD 화면 경로로 unbound를 입증할 수 없습니다. 원 기여자는 크레딧을 원하지
않았습니다. 개인 이름을 추가하거나 새 공개 저장소를 요구하지 마세요.
전체 소스/출처와 정확한 장비 통합 검토는 별도 과제입니다.
