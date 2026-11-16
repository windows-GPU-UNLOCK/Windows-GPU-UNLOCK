# 호환성 확장 로드맵과 검증 관문

[English](PORTABILITY.en.md) | **한국어**

이 문서는 **모든 PC에서 언락을 보장한다는 선언이 아니라**, 지원 가능한 구성을 늘리면서 안전하고 이해하기 쉬운 사용자 흐름을 만드는 단계별 계획입니다. 현재 기능과 성공 기록은 정확한 장비·경로별 근거에 묶여 있습니다. 모든 GPU나 펌웨어에서 동작한다고 약속할 수 없습니다.

## 목표와 근거 구분

제품 방향은 탐색·증거 수집을 폭넓게 쓰기 쉽게 하고, 언락은 자체 검증 관문을 통과한 정확한 구성에서만 허용하는 것입니다.

| 근거 단계 | 의미 | 다음 단계로 자동 승격되지 않는 이유 |
|---|---|---|
| Windows 인벤토리 | Windows에서 수집한 하드웨어·드라이버 정보 | 부팅 전 경로·소유권·호환성 판정이 아님 |
| 기존 캡처의 오프라인 검사 | 제공 파일이 자동 LOCAL 경로의 구조·입력 조건에 맞는지 확인 | 출처·완전성·별도 완전 종료 여부를 독립 증명하지 못함 |
| 읽기 전용 EFI 캡처 | 제한된 펌웨어 상태와 PCI/GOP 관계를 관찰 | 진단 EFI도 멈추거나 Windows로 복귀하지 않을 수 있고 언락 적격성을 주지 않음 |
| 로컬 프로필과 호스트 시험 | 한 장비의 캡처·자산·소스에 대한 생성·거부·실패 경로 검증 | 합성/RAM 시험은 실기기 부팅·복구·성능 증거가 아님 |
| 정확한 경로의 실기기 검증 | 특정 빌드/카드/보드/BIOS/화면 경로의 실제 결과 | 다른 장비나 빌드로 일반화할 수 없음 |
| 반복성·릴리스 자격 | 지정 구성에서 재현·복구·배포 범위를 확인 | 각 단계에 별도 근거와 검토가 필요함 |

## 호스트 포팅과 GPU 지원 분리

기존 `unlock/port.*` 트랜잭션은 특정 RTX 3090과 AMD 화면 경로를 중심으로 작성됐습니다. 이후 정확한 장비 프로필과 제한된 LOCAL 탐색/생성 경로가 추가됐지만, 서로 다른 계층과 근거입니다. 아래 표는 기존 구현의 예이며 현재 모든 프로필 구현 목록은 아닙니다. ASUS 보드나 AMD CPU 자체가 언락 알고리즘은 아닙니다. Intel 호스트, 다른 보드 제조사와 화면 경로는 GPU 트랜잭션과 별도로 조사할 수 있지만, AMD Radeon이나 Intel 외장 GPU에는 별도 언락 구현이 필요합니다.

| 포팅 계층 | 기존 구현의 예 | 개발 방향 | 필요한 근거 |
|---|---|---|---|
| 장치 탐색 | 기존 코드의 `01:00.0` BDF 고정 | PCI 후보 탐색과 모호하지 않은 단일 대상 선택 | 다른 segment/BDF, 중복 후보와 읽기 실패 거부 |
| BAR 접근 | `GU_BAR0_BASE`, `BarCheck` descriptor/base 검사 | descriptor 유형·크기·범위·정렬 검증, 탐색 자원 고정 | 32/64-bit descriptor, overflow/truncation, relocation, identity 재확인 |
| 화면 분리 | 기존 AMD GOP 경로 고정 | GOP ancestry를 실제 PCI 장치에 연결해 대상과 분리 증명 | Intel/AMD GOP, console forwarding, 잘못된 경로, 대상 GPU GOP 거부 |
| GPU 정책 | PCI/subsystem/revision, chip/VRAM/PROM/firmware 식별 | provenance와 state/selector가 고정된 검토 프로필 | identity, PROM/firmware, memory/WPR, cold-state 거부 |
| 트랜잭션 보호 | ownership, decode 복구, BME, DMA, FLR, cleanup | 모든 단계를 동일한 장치/프로필에 바인딩 | fault injection, timeout, cleanup 실패, 자원 잔류, 동일 부팅 재시도 금지 |
| Windows 인계 | 기존 ASUS firmware 복귀와 reset 없는 Boot Override | 검증된 경로 문서화; direct chainload는 별도 조사 | 플랫폼별 no-reset, 실패 처리, Windows driver recovery |

기존 코드는 [`port.h`](../unlock/port.h), [`port.c`](../unlock/port.c), [`checks.c`](../unlock/checks.c), [`app.c`](../unlock/app.c), [`ownership.c`](../unlock/ownership.c), [`vendor/unlock_610.c`](../unlock/vendor/unlock_610.c)에 있습니다. 단순히 AMD ID나 BDF/PROM 상수만 바꾸면 나머지 가정은 해결되지 않습니다.

## 현재 구현 단계

이 절은 현재 구현 성숙도를 설명하며 실행 순서가 아닙니다. 의존성을 반영한 작업 순서는 아래 [통합 작업 계획](#통합-작업-계획)을 따릅니다.

1. **인벤토리와 다국어 안내 — 구현됨.** Windows 인벤토리, 기존 캡처 오프라인 검사, 수동 호환성 보고와 근거 제한을 영어·한국어로 제공합니다. 이 입력들은 언락을 허용하지 않습니다.
2. **일반 사전 부팅 진단 탐색 — 일부 구현됨.** 프로필 없는 generic read-only probe(`-DGU_PROBE_GENERIC`, [새 장비 절차](NEW-MACHINE.en.md))는 제한된 범위에서 NVIDIA 화면 장치, console graph, PROM 및 드라이버 이미지를 기록할 수 있습니다. 이 경로는 장비·펌웨어에 제한이 있고 EFI가 멈추거나 복귀하지 못할 수 있습니다. 초보자용 capture-only 진입점, 명확한 거부 사유와 캡처 뒤 멈추는 흐름은 아직 통합 작업입니다.
3. **장비별 LOCAL 프로필 생성 — 좁은 범위에서 구현됨.** `make-profile.py`는 `research/profile/proven.json`의 결합 GPU/VRAM/driver-code tuple과 완전 일치하는 캡처·콘솔 범위만 허용합니다. 생성 헤더는 장비 전용이며 검토 프로필이나 하드웨어 qualification이 아닙니다. 쓰기 가능한 LOCAL 빌드에는 현재 소스와 묶인 호스트 시험 증거가 필요합니다.
4. **새 장비 실기기 검증 — 별도 근거 필요.** 정확한 현재 build/장비/경로의 감독된 부팅, 실패 동작, Windows/화면 복구가 필요합니다. host/display 시험은 이를 대신하지 않습니다.
5. **더 넓은 배포 — 향후 근거 필요.** 호환성 행렬에는 source/package hash, GPU/subsystem/PROM/firmware profile, board/BIOS, 화면 경로와 Windows driver/build를 결합해 기록해야 합니다. 제보, mock-tested 프로필, 실기기 검증 프로필은 별도 상태입니다.

권장 실행 순서는 아래 통합 작업 계획표에 한 번만 정의합니다. 이 페이지의 현재 구현 단계는 성숙도 분류이고, Project 작업 맵은 카드별 owner/status를 연결합니다.

## 현재 진행 위치

- Project 5에는 공유 계약·도구 검사기·캡처 자산 분리 카드가 Review, selector/복구 계약이 Ready, 프로필 자격 행렬과 설치 도구가 In Progress, 초보자 실기기 흐름이 Awaiting Hardware입니다. 과거 PR/시험 기록은 실제 현재 소스와 대조해야 합니다.
- `release/parent-baseline-intake`는 main에 병합되지 않은 작업 브랜치입니다. 이 브랜치는 aggregate release host fixture, 합성 topology runner와 관련 research/top-level README 문서를 변경했습니다. PCI ancestry 연구는 깊이 2~16, 두 루트 유형과 일부 segment 값의 합성 RAM 경로를 시험했습니다. native Clang compile-guard/mutation 단계는 완료되지 않았고 실기기 검증도 아닙니다.
- 확인 시점에 PR112는 draft, PR177/PR178은 open이며 검토된 head는 승인됐지만 기록된 base와 충돌, PR188은 병합 상태였습니다. 통합 전 PR 상태를 다시 확인해야 합니다.

## 다음 우선 작업

1. PR112와 PR177/PR178의 중복·소유권·통합 기준을 최신 `main`과 비교해 결정하고 Project 카드의 오래된 상태를 정리합니다. 경쟁 capture frontend를 추가하기 전에 이 결정을 마칩니다.
2. 공유 진단/evidence 계약과 담당을 합의합니다.
3. selector 불변조건·거부 사례와 Windows 인계/복구 행렬을 호스트 음성 시험으로 마무리합니다.
4. native Clang이 준비되면 PCI parent-audit의 남은 compile-guard/mutation 검증을 완료합니다. MSVC 호스트 경로 실행은 유용한 C/RAM 근거지만 Clang 전용 suite 통과는 아닙니다.
5. `new-machine.ps1` 재실행 시 `-StageUnlock` 없이도 프로필/시험/패키지로 이어지는 동작을 안내하고, 진정한 capture-only 중단점·취소 경계를 통합 계약에 포함합니다.
6. 공유 evidence schema 합의 후 CI와 자격 행렬을 갱신합니다. 호스트 결과를 실기기 qualification으로 표시하지 않습니다.
7. 정확한 결합 프로필을 보수적으로 유지·확장하고, 음성 사례와 source-bound 전체 replay를 보존합니다.
8. 별도 승인이 있을 때만 정확한 현행 build/profile/route를 실기기에서 감독 시험하고 Windows/화면 복구와 반복성을 기록합니다.
9. 계약 안정화 뒤 exact source/package hash, 지원 범위와 복구 제한을 릴리스 계약에 반영합니다.

PR112와 PR177/PR178은 contributor tool 영역에서 겹치거나 연관됩니다. PR112는 mergeable 상태이고 PR177/PR178은 기록된 오래된 base와 충돌합니다. 최신 `main`과 정확한 base/head를 대조하고, 유지할 구현과 maintainer 결정을 기록한 뒤 통합합니다.

## 통합 작업 계획

소프트웨어 단계의 완료는 별도로 요구되는 실기기 근거를 대신하지 않습니다.

| 순서 | 작업 패키지 | 완료 근거와 의존성 |
|---|---|---|
| 0 | 기여자 도구 통합 기준 조정 | PR112/PR177/PR178 범위와 담당·기준 commit을 정하고 최신 `main`과 충돌을 해결합니다. 관련 PR의 검토된 계약은 보존하며 branch-only 기능을 main/release 기능처럼 안내하지 않습니다. |
| 1 | 공유 계약 합의 | 진단·버전·evidence·ownership·review·release/version 경계를 합의합니다. 도구 검사기, capture-only 분리와 manifest 작업의 전제입니다. |
| 2 | 핵심 안전 계약 | selector 불변조건·거부 사례와 Windows 인계/복구 행렬을 호스트 음성 시험으로 검토합니다. 근거 없는 복구 경로는 계속 미확인으로 둡니다. |
| 3 | 남은 호스트 검증 | native Clang compile-guard와 mutation suite를 실행합니다. MSVC로 빌드한 경로 테스트는 Clang 전용 suite의 통과로 간주하지 않습니다. |
| 4 | 안전한 사용자 탐색 | 인벤토리, 오프라인 검사, 읽기 전용 캡처, LOCAL 생성, 패키지 빌드와 실제 스테이징을 분리합니다. 미래 capture-only 경로는 사전 제공 unlock PROM/driver 자산 없이 가능해야 하지만(프로브 자체는 PROM/IMG 관측값을 수집할 수 있음), 사전 부팅 캡처에는 검토된 compiler·선택 USB·입회 부팅이 필요합니다. 현재 `new-machine.ps1`은 `-Assets`를 요구하며 캡처 후 재실행하면 `-StageUnlock` 없이도 package를 빌드하고, 해당 스위치는 USB 복사만 제어합니다. |
| 5 | 재현 가능한 evidence | 캡처/evidence schema, provenance, 사용자가 보고한 부팅/Windows 결과를 합의한 뒤 clean-host CI와 artifact/hash 검사를 추가합니다. hash나 완료 로그만으로 실제 성공을 추론하지 않습니다. |
| 6 | 정확한 프로필 확장 | GPU/보드/BIOS/화면 경로별 결합 튜플을 한 번에 하나씩 review·음성 시험·source-bound replay와 함께 검토합니다. 기존 거부 동작을 보존합니다. |
| 7 | 정확한 실기기 경로 qualification | 필요한 승인을 받은 뒤 한 정확한 build/profile/route에서 감독된 부팅, 실패, Windows/화면 복구와 반복성을 별도로 기록합니다. mock/PE/host 결과는 이 관문을 닫지 않습니다. |
| 8 | verified package와 선택적 공유 | 소스/패키지 hash, 지원 범위, 자산과 복구 제한을 릴리스 계약에 포함하고, 결과 공유는 비식별화·미리보기·오프라인 경로를 유지합니다. |

### Project 5 작업 맵

아래 상태는 2026-11-17 Project 5 조회 결과입니다. 계획 상태이며, 카드의 구현이 현재 `main`에 포함됐다는 증거는 아닙니다.

| 로드맵 작업 | 기존 Project 5 카드 | 현재 상태 / 바로 할 일 |
|---|---|---|
| 통합·공유 계약 | [Project 5 카드](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIcEU) — Agree component ownership and shared interface contracts | **Review.** PR112/PR178 담당과 통합 경로를 정하고 진단/evidence 계약에 필요한 maintainer 합의를 받습니다. |
| 핵심 안전·인계 | Audit unlock selector invariants and fail-closed transitions; Define recovery and Windows handoff contracts | **Ready.** 소스 근거 불변조건과 호스트 음성 시험부터 하고 경로별 실패·복구 행렬을 정합니다. |
| 사용자 발견 흐름 | Add a prerequisite doctor; Separate capture-only setup; Publish EN/KO walkthrough; Guide first-time capture; Guided installation; Persist session/resume | **Review / Awaiting Hardware / In Progress.** 로컬 메모를 공개 PR head와 대조하고 clean-host 검증과 실제 입회 캡처·복귀 근거를 분리합니다. |
| Evidence·릴리스 재현성 | Standardise manifests/reports; Simplify intake; Expand host CI; Define release/package contract | **Review / Backlog.** provenance/사용자 결과 schema를 합의하고 통합 트리의 시험과 정확한 패키지 근거를 연결합니다. |
| 정확한 장비/프로필 qualification | [Profile/support matrix](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIc3o); [Aggregate topology](https://github.com/users/impacifist/projects/5?pane=issue&itemId=PVTI_lAHOBAf6zs4BpFxHzhEIc0E) | **In Progress / Review.** 합성 브랜치 결과를 장비 근거와 구분하고 native-Clang guard/mutation을 마칩니다. |
| 연구 조율 | Coordinate AD104 RTX 4070 Ti; Coordinate EVGA RTX 3090 | **Backlog.** 겹치는 실험을 시작하기 전에 기존 기록을 core owner와 대조합니다. |

구현 PR이 병합돼도 acceptance 조건이나 maintainer 결정이 남으면 Review 상태일 수 있습니다. 코드·브랜치·호스트 시험만으로 Done 처리하지 않습니다.

## 초보자 작업 경로

| 순서 | 사용자 단계 | 경계 |
|---|---|---|
| 1 | Windows 인벤토리 또는 수동 보고 | EFI 부팅이 필요 없으며 모르는 값은 미상으로 둡니다. |
| 2 | 기존 캡처 오프라인 검사 | 사용자가 이미 가진 파일만 읽습니다. `candidate`는 LOCAL 경로의 입력 조건 통과이지 언락 승인이나 캡처 출처 증명이 아닙니다. |
| 3 | 선택적 읽기 전용 EFI 캡처 | 별도 입회 펌웨어 작업이며 멈추거나 Windows로 복귀하지 않을 수 있습니다. 보고에 필수는 아닙니다. |
| 4 | LOCAL 프로필 생성 및 source-bound 호스트 시험 | 결합된 proven envelope 안에서만 진행하며, 통과해도 실기기 자격은 생기지 않습니다. |
| 5 | 패키지 빌드와 실제 스테이징 | 현재 `new-machine.ps1`은 `-Assets` 인수를 요구합니다. 캡처 단계에서 그 자산으로 프로브를 만들거나 스테이징하지는 않지만, 캡처 후 재실행하면 `-StageUnlock` 없이도 프로필/호스트 시험/패키지를 빌드합니다. 이 스위치는 언락 패키지/자산의 USB 복사만 허용합니다. |
| 6 | 정확한 장비의 실기기 검증 | 별도 승인과 근거가 필요하며, 실패 동작·Windows/화면 복구·반복성을 따로 기록합니다. |

따라서 현재 스크립트를 쓰는 캡처-only 사용자는 `-Assets` 인수를 준비해야 하고, 두 번째 호출 이후 프로필/패키지 단계로 진행하지 말고 멈춰야 합니다. 별도 capture-only 흐름은 불필요한 언락 자산과 프로필/패키지 단계를 없앨 수 있지만, 사전 부팅 캡처에 필요한 compiler·선택한 USB·입회 부팅 요구까지 없애지는 않습니다. 실제 capture-only 분리/취소 경계는 PR112/PR178 통합 계약에 포함할 작업입니다.

## 쓰기 가능한 EFI 확장 전 합격 기준

- 알 수 없는 장치, 잘못된 읽기, malformed path, 미지원 layout 또는 중복 후보는 arm, PCI/MMIO write, BME 활성화, ownership 해제, DMA 할당이나 FLR을 일으키지 않아야 합니다.
- BDF/BAR 위치 탐색은 달라질 수 있지만 identity, descriptor bounds, snapshot consistency를 유지하고 트랜잭션 중 변경은 fail-closed 해야 합니다.
- GOP 하나가 더 있거나 vendor 이름이 같다는 사실만으로 대상과 화면 분리를 입증할 수 없습니다. no-iGPU, multi-GPU, hybrid laptop 경로에는 별도 설계가 필요합니다.
- 잘못된 subsystem/revision, PROM/firmware digest, cold state, selector 변경과 memory/WPR 범위를 거부하는 프로필 시험을 유지합니다. 기본/unknown 프로필은 비쓰기 상태여야 합니다.
- one-shot 확인, 단계별 guard, timeout/retry containment, driver ownership, decode 복구, DMA 수명, FLR 정리와 안전하지 않은 복귀 시 `STOP / POWER OFF`를 보존합니다.
- mock 통과는 소프트웨어 근거입니다. 실기기 지원에는 정확한 build/profile provenance, 완전한 정리, Windows driver recovery와 통제된 전후 측정이 별도로 필요합니다.
- 기존 `test_checks.c`, `test_port.c`, `test_3090_preflight.c`와 transaction/ownership 음성 시험을 보존합니다. 기대값을 바꿀 때는 대체 불변조건을 구현하고 독립적으로 검증해야 합니다.
- 안정성·실제 애플리케이션 성능·반복 부팅은 mock/host 통과와 별도의 근거로 기록합니다.

기기 모델명 일치, 인벤토리 제보 또는 빌드 성공만으로 하드웨어 지원이 추가되지는 않습니다. Firmware 재배포와 기존 라이선스 제한도 유지합니다.

실제 부팅, USB 스테이징, GPU 상태 변경, firmware/BCD/ESP 설정은 이 계획이나 호스트 테스트 통과로 승인되지 않습니다. 호환성·자격 확대에는 별도 근거와 필요한 승인이 적용됩니다.
