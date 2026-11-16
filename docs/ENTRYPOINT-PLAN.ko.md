# 저장소 진입점 및 정리 제안

[English](ENTRYPOINT-PLAN.en.md) | **한국어**

2026-10-30 main 커밋 `1f8776e`에 대한 과거 목록입니다. DeclanFrampton에게 배정된 Kanban 카드 **Inventory repository entry points and plan cleanup**의 제안이며 현재 파일 목록은 아닙니다. 명령을 이동, 삭제하거나 폐기하지 않습니다. 정리 계획 적용 전 관리자 합의가 필요합니다. 현재 제품 순서와 통합 상태는 [포팅 로드맵](PORTABILITY.ko.md#통합-작업-계획)을 참고하세요.

## 공개 경계 유지

| 진입점 | 현재 목적과 부수 효과 | 제안 |
|---|---|---|
| [README](../README.ko.md), [호환성](COMPATIBILITY.ko.md) | 정확한 지원 경로 선택; 실행 명령이 아님 | 경로별 대표 안내 연결 유지 |
| [collect_compatibility.py](../tools/collect_compatibility.py) | Windows 인벤토리 출력; 업로드/언락 없음 | 인벤토리 전용 유지 |
| [check-compatibility.py](../research/profile/check-compatibility.py) | 기존 캡처 오프라인 평가; 프로브 실행/프로필 생성 없음 | 스테이징과 분리 유지 |
| [new-machine.ps1](../research/profile/new-machine.ps1) | 프로브/프로필/검사/패키지 재개 흐름; USB 파일 스테이징 가능; 언락 스테이징은 `-StageUnlock` 필요 | 명령 변경은 승인되지 않았습니다. 변경 전 [최신 로드맵](PORTABILITY.ko.md#통합-작업-계획)에 따라 PR112/PR178 스택을 조정합니다. |
| [build-probe.ps1](../research/profile/build-probe.ps1) | 일반 진단 EFI 파일 로컬 빌드; 실제 EFI 부팅은 별도 하드웨어 작업 | 저수준 빌더 유지; 프런트엔드에서 재사용 |
| [Configure.ps1](../internal-boot/Configure.ps1), [Build.ps1](../internal-boot/Build.ps1) | 정확한 내부 프로필 설정 및 수동/자동 EFI 쌍 빌드 | 설정/빌드 경계 유지 |
| [Headless.ps1](../internal-boot/Headless.ps1), [Install.ps1](../internal-boot/Install.ps1) | 기존 전용 ESP 설치/등록 및 자동 부팅 정책; 부팅 구성/설정 변경 가능 | 명시적인 설치 명령 유지; 인벤토리/오프라인 검토에서 실행하지 않음 |
| [prepare_usb.py](../tools/prepare_usb.py) | 매니페스트/자산으로 새 로컬 패키지 트리 생성; 선택 USB에 쓰거나 포맷하지 않음 | 물리 스테이징과 분리 |
| [unlock/build.ps1](../unlock/build.ps1) | 자체 프로필/실험 옵션이 있는 레거시 USB 빌드 | [레거시 안내](GUIDE.ko.md)와 함께 유지; 내부 헤드리스/LOCAL과 혼용하지 않음 |
| [benchmark/run-benchmark.ps1](../benchmark/run-benchmark.ps1) | 연산 성능 측정; 사전 부팅 트랜잭션 증명과 별개 | 설정/빌드/실행/비교 분리 유지 |
| [research/headless](../research/headless/README.ko.md), [research/rtx3080](../research/rtx3080/README.md) | 경로별 실험 작업 | research에 유지; 공통 헬퍼 추출 시 진행 중 PR과 조율 |

## 비슷한 이름은 중복의 근거가 아님

레거시 `unlock`과 `internal-boot/unlock`은 래퍼와 부팅 계약이 다릅니다. 파일명만으로 빌더나 PE 검사기를 삭제/통합하지 않습니다. 허용 define, 프로필 선택, 소스 매니페스트, 출력 구조와 실패 동작을 먼저 비교하고 두 경로의 검사를 유지합니다.

캡처 빌드 매니페스트, 머신별 로컬 프로필 증거, 최상위 [SOURCE-MANIFEST.json](../SOURCE-MANIFEST.json)도 범위가 다릅니다. 최상위 파일은 과거 공개 v0.3.0 목록이며 현재 트리의 자동 갱신 매니페스트가 아닙니다. 관련 없는 문서/스테이징 변경에서 임의로 재생성하지 않습니다.

생성된 `build` 디렉터리, 자산, BIN 캡처, `research/profile/local`, 비공개 프로필 헤더와 내부 설치 상태는 [.gitignore](../.gitignore)에서 제외합니다. 정리 중 공개 문서에 옮기거나 제외 규칙을 제거하지 않습니다. 깨끗한 체크아웃에는 사용자의 비공개 자산이나 머신별 생성 프로필이 없습니다.

## 검토할 순서

1. 경로 변경 전 탐색 구조와 명령 소유권에 합의합니다. 이후 마이그레이션 중에도 기존 명령을 유지합니다.
2. 겹치는 기여자 도구 구현을 더하기 전에 PR 스택을 조정합니다. PR112는 draft이며 mergeable로 조회됐고 PR177/PR178은 open이며 기록된 base와 충돌합니다. 정확한 head와 최신 main을 비교해 기준 구현을 정하고, 브랜치 전용 기능을 main에 병합된 것처럼 설명하지 않습니다.
3. 합의 후 경로별 작은 변경을 구현합니다. 공개 명령을 대체한다면 먼저 문서화된 호환 래퍼와 한정된 전환 기간을 마련합니다. 이 제안은 폐기를 승인하지 않습니다.
4. 변경에 맞는 명령 해석, 매개변수 호환성, 출력/매니페스트 계약, 거부 경로를 검사합니다. 호스트 모의 검사는 USB 선택, EFI 실행, Windows 복구를 입증하지 않습니다.

이 과거 인벤토리 시점에는 `.github/workflows` 디렉터리가 없었습니다. 그 관찰을 현재 작업에 적용하기 전에 실제 트리를 다시 확인하세요. CI 카드는 실행기를 도입하기 전에 로컬 검사 전제 조건과 비공개 자산 의존성을 별도로 조사해야 합니다. 호스팅 워크플로 파일이 없다고 호스트 검사도 없는 것은 아닙니다.

## 남은 승인 조건

이 PR은 검토용 목록을 제공합니다. 유지/폐기/이동 계획에 관리자가 합의할 때까지 카드를 Review로 유지합니다. 파일 이동, 런타임 통합, 물리 부팅, 새 지원 적격성 확인 또는 초보자 사용 검증을 완료한 것은 아닙니다.
