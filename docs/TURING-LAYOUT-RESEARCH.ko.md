# Turing 레이아웃 입력: CPU 전용 연구

이슈115는 RTX2080Ti를 문의합니다. 고정 [Linux 소스7eb51bcc](https://github.com/Zagitta/gpu-unlock/tree/7eb51bccae0a0b7e599e084d971170e9a1e82d0c)는
Turing을 experimental로 표기하며 명시적 TU102 계열을 포함합니다. Windows
검증은 아닙니다. 현재 Windows gpu-family.h에는 TU102 허용이 없으며
vendor 주석의 공유 TU102 함수 이름만으로 계열 지원을 얻을 수 없습니다.

줄 끝을 정규화하면 layout_610.c/h는 같습니다. 입력 계약은 다릅니다.
Turing은 Ampere framebuffer/MMU 입력 대신 범위의 크기/스케일/ECC로
사용 가능한 framebuffer를 계산합니다. 연구 전용 헤더는 주어진 정수의
산술과 VGA fallback, 잘못된 값/sentinel 거부를 모델링합니다. 알 수 없는
범위 비트는 Linux 읽기 코드보다 엄격히 거부합니다. 실제 캡처로 이 제한이나
펌웨어 준비 상태를 검증하지 않았습니다. 합성0x2c8은44 곱하기2^28바이트
(11GiB) 예시이며 실제 RTX2080Ti 레지스터 관찰값이 아닙니다.

실제 빌드는 이 헤더를 포함하지 않습니다. 기존 layout_610.c, 카드 목록,
MMIO 읽기, 펌웨어/페이로드, 드라이버 해제 또는 잠금 해제는 변경하지 않습니다.

기존 clang/MSVC와 고정 소스에서 실행합니다.

```powershell
powershell -NoProfile -File .\research\turing\test-layout-inputs.ps1
```

-Clang/-VcVars는 기존 도구 경로에만 사용합니다. 예상은 합성 범위2016조합,
VGA/sentinel/알 수 없는 값 거부 및 변경하지 않은 레이아웃 계산기의 PASS,
새 Documents 폴더의 turing-layout.json입니다. Passed=true이며 하드웨어/
캡처 증거/EFI/프로필/쓰기 플래그는 false입니다. 재현한다면 JSON만 공유하세요.
관리자는 이미 실행했습니다. Python, 컴파일러 설치, 캡처 파일, GPU 조회,
EFI, 재부팅, 설정 변경은 없습니다. 실패하거나 하드웨어/허용 플래그가
true이면 중단하고 하드웨어 재시도는 하지 마세요.

독립된 산술 연구이며 Turing 트랜잭션이 아닙니다. 펌웨어 descriptor/loader/
FWSECv2, 정확한 카드/보드/cold 핀, 소유권, 해제, 정리/Windows 복귀 및
동일 조건 성능은 별도 검토 단계입니다. 다른 카드 레지스터를 옮기거나 Ampere
프로필을 부팅해서 채우지 마세요.

## 연구 v2 메타데이터 후속 작업

같은 실행기는 합성 descriptor 바이트로 `fwsec-v2-metadata.h`도 검사합니다.
secure/nonsecure IMEM 분리, 정확한 descriptor+이미지 경계 및 잘림/오버플로/
범위/미검토 필드 거부79개를 검사합니다. 실패 출력은0입니다. 보고서는
turing-layout-input-model-v2, MetadataRefusalCases=79입니다.
이슈115에 전달한 v1 결과/핀은 별도 결과로 유지합니다.

v2를 계속 거부하는 실제 vbios_610.c의 확장이 아닙니다. 고정 Linux
descriptor 계약의 연구용 부분집합이며 generic-loader entry/DMEM base0,
미검토 tail 필드0 및 secure 코드의 존재를 의도적으로 요구합니다. 실제
펌웨어에는 다른 검토 계약이 필요할 수 있으며 실제 Turing 펌웨어로 가정을
검증하지 않았습니다. 펌웨어 자산의 요구/복사/출력은 없습니다. 컨테이너 탐색,
서명/인증 검증, 로더 통합, 이미지 패치 또는 실행은 구현하지 않았습니다.
실제 v3 동작과 카드 가드는 그대로입니다.
