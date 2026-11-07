# Issue28 / PR72 단계 가드 검토

PR72 `80db48e90d0b684efe7fc2b78e71ebe8759d014c`는 B760의 NVIDIA 단계를5로 추가하지만, 모든 구성에서 단계4의 `Profile`을 생략합니다. 기존 구성의 NVIDIA 단계는4이므로 단계별 재검사가 빠집니다. B760의 선택 소비자 역할만 생략하고 모든 토폴로지의 NVIDIA 검사를 유지해야 합니다. 소스 검토 결과이며 실제 하드웨어 실패를 입증한 것은 아닙니다. 기여자의 코드나 펌웨어는 실행하지 않았습니다.

EDK2에서0x8은 `EFI_OPEN_PROTOCOL_BY_CHILD_CONTROLLER`이고 GUID `1c0c34f6-d380-41fa-a049-8ad06c1a66aa`는 표준 `EFI_EDID_DISCOVERED_PROTOCOL`입니다. 상수만으로 소유 관계나 코드 신원을 증명할 수 없습니다. Maxsun 결과는 보고자의 하드웨어 보고이며 리베이스된 래퍼의 실제 검증은 보고되지 않았습니다. 별도 Gigabyte 사례에 프로필을 옮기지 마세요.

고정된 소스 체크아웃에서 기존 Clang/MSVC 호스트 도구로 실행합니다:

```powershell
powershell -NoProfile -File research/profile/test-local-release.ps1 -Card 0x250410de -Children 2 -Mutations
```

필요하면 기존 `-Clang`, `-VcVars` 매개변수를 사용합니다. 설치나 정책 변경은 하지 마세요. RAM 기준8개가 통과하고 단계4 검사를 생략한 컴파일 변형1개가 충돌 대신 단언 실패로 감지되어야 합니다. 로컬에서는 EDID 사례당6542개, EDID 없는 사례당4959개 검사가 통과했습니다. 변형은 소비자/경로/코드 가드 단언에서 실패했습니다. 기존 토폴로지의 회귀 모델이며 새 B760 소비자나 실제 잠금 해제를 검증하지 않습니다.

검토한 `build/local-release-<id>/summary.json`만 반환하세요. 예상 필드는 `synthetic_only=true`, `hardware_access=false`, 사례8개 및 `mutations`의 `skip-stage4-profile`, `compiled=true`, `detected=true`입니다. 캡처, 펌웨어, 비공개 헤더는 필요 없습니다. 정책/컴파일/테스트 실패 시 중단하고 가능하면 요약과 짧은 오류를 보존하세요. EFI 부팅, 하드웨어 재시험, 가드 완화나 복구 작업은 포함되지 않습니다.
