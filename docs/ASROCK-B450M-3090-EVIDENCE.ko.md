# ASRock B450M-HDV R4.0 / ASUS TUF RTX3090 증거 검토 (issue38)

[English](ASROCK-B450M-3090-EVIDENCE.en.md)

정확한 사례의 보고된 성공과 제한된 검토 기록입니다. 새 공통 쓰기 프로필이나
3090 전체 지원이 아닙니다. B450M-HDV R4.0/P10.10/Ryzen5500/iGPU없음,
ASUS2204/1043:87b3, 보고된VBIOS94.02.42.00.b4, PCI0000:01:00.0.
소유자는 mainfcf7ab5의 수동 휘발성 USB 실행과 정상 Windows 복귀를 보고했습니다.
처음 캡처 폴더 누락으로 HANDOFF STOPPED된 이력과 이후 실행 순서를 보존합니다.
새 부팅/캡처/벤치마크/설정 변경을 요청하지 않습니다.

공급된 파일의 다운로드 바이트 해시를 확인했습니다:
profile.json b72a45bb4d20db3573cbb65ed76309ab75732855761c6919408ca867c5d48146,
Format2영수증 b9808c56fd496d8eb24ef2ee108802e6fd1f7cf7e2f8779f6e49edd12527be9f,
트랜잭션6088dfae9132d8cd3f395a55720728ff0df330d8ad9febfd42c4343ac5600c0b,
GEMM전사64bfa5784204af0793ee438d4d6784f70b1d09c9f8f117a8f41115ac9680c5e3.

프로필/영수증의 헤더/PROM/fixture/프로필 보고서 해시가 일치하며845개 입력 행의
TreeSha256도 재계산과 일치합니다.22개 작업 결과는 의도된 거부2개를 포함해
예상값과 일치합니다. 문서 간 관계 검증이며 독립 테스트 재실행, 소스 바이트
증명 또는 실제 하드웨어 증명은 아닙니다. 업로드 데이터를 실행하지 않았습니다.

보고서는 단일 FINAL status0/transaction/attempted1/clean1,
SS0=88888888/SS1=8 의도와 pre-FLR일치, FLR성공, streaming/coherent마스크,
PCIcommand3 복원 및 BMEcommand3/cache300/pending0을 포함합니다.
5개 asset-cache cleanup의 devres_released0도 기록됐습니다.
자식의 driver_release0을 앞선 래퍼의 해제 단계에 대한 독립 증명으로 해석하지 않습니다.
Windows 복귀는 소유자 보고입니다.

보고된4096^3 GEMM중앙값은 FP16 65.27->118.01(+80.8028%),
BF16 65.26->118.52(+81.6120%),FP32 21.75->21.32(-1.9770%)입니다.
프로토콜은 전사이며 warmup3회/측정10회,PyTorch2.13.0+cu130,
양쪽 모두24GBLLM상주입니다. 원시 타이밍/독립 재현은 없습니다.
LLM-prefill/NVMe 관찰은 언락 귀속 증거에서 제외합니다.
영구/무인/재시작/절전/최대절전 검증이 아닙니다.

## 남은 소스 연결 검사: 기존 파일만 사용

원래 테스트한 소스 바깥의 새 고정 폴더를 사용하세요. 원본 소스에 새 파일을
복사하거나 프로필/테스트 영수증을 재생성하지 마세요.
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\test-profile-review.ps1
```
안내에 원래 profile-local.h와 research/profile/local/이 있는 소스 폴더를 입력합니다.
현재 고정 소스의 읽기/해시/파싱 조건을 사용하며 원본 폴더의 코드/스크립트를
실행하지 않습니다. 컴파일/테스트 실행/USB 준비/GPU/펌웨어 접근은 없습니다.
PROM을 포함한 기존 fixture는 해시를 위해 로컬에서만 읽고 업로드하지 않습니다.

새 Documents의 profile-review.json이 예상됩니다. 숫자 bus/BAR/root-port 조건과
기존 소스/헤더/fixture/22작업 연결을 확인합니다. 검토한 JSON만 보내세요.
원시 헤더/캡처/PROM/IMG는 로컬에 두세요. -OutputRoot로 기존 로컬 출력 폴더를
선택할 수 있습니다. 알 수 없음/실패 시 중단하고 통과하려고 파일 복구, 프로필/
테스트 재생성 또는 하드웨어 반복을 하지 마세요. 원본이 없으면 없다고 알려주세요.

로컬 신뢰된 헤더 파서, 중복/형식 오류 조건, 누락 증거 거부,22작업 형식/개인정보
및 출력 호스트 테스트가 통과했습니다. 소유자 원본의 검사는 아래와 같이 반환되었으며
허용/프로필 실행 코드는 변경하지 않습니다. 다음 검토는 재캡처가 아닌 조건/소스 연결입니다.

출처: [issue38](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/38),
[기존 증거 댓글](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/38#issuecomment-6562835517),
[소유자 데이터](https://gist.github.com/AiInfluenceGr/e551b2986888f3dde76fc86496f18ccd).

## 반환된 소스 검사 및 검토 단계

[반환된 검사](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/38#issuecomment-6563360698)는
원본 소스에서 HostEvidenceBindingsMatch=true,845개 입력 및22개 호스트 작업을
보고합니다. 헤더/프로필/PROM/트리 해시는 이전 파일과 같습니다. 숫자 조건은
bus1, BAR0 fb000000..fbffffff, 루트 포트 장치1/함수1입니다. 이 사례 헤더의 관찰이며
다른3090/보드에 재사용하지 않습니다. 첫 출력 폴더 거부 후 쓰기 가능한 빈 로컬
폴더를 만들었으며 소유자는 원본 변경/원본 코드 실행이 없었다고 보고했습니다.

새 로컬 문서 연결 검사는 제공된 프로필의 실제 바이트 해시, 해시 연결,
소스 행 트리 해시, 의도된 거부 작업, 재생 ID 및 숫자 범위를 확인합니다.
프로필/해시/트리/작업/개수/중복/숫자/범위 불일치 거부 테스트가 통과했습니다.
이는 제공된 문서 사이 관계를 검증하며 원본845개 소스나 하드웨어를 여기서
독립적으로 읽거나 재실행한 증거는 아닙니다.

재현용으로만 기존 profile-review.json, profile.json,
host-test-receipt-Format2.json을 함께 둔 폴더에 대해 실행할 수 있습니다:
```powershell
python -I -B .\research\profile\review-evidence-bindings.py C:\path\to\existing-evidence
```
예상 JSON은 status=consistent,845입력/22작업, 허용/하드웨어/쓰기 플래그 false입니다.
소유자 재실행이나 새 파일을 요청하지 않습니다. 재현 결과가 다르면 검토한 작은
출력이나 개인정보 제거 오류만 반환하고 중지합니다. 원본을 보존하며 프로필/테스트
재생성, 재캡처, 부팅 또는 설정 변경을 하지 않습니다.

현재 단계는 정확한 기기의 보고된 하드웨어 성공, 검토된 문서 연결 및 소유자 실행
소스 검사이며 관리자 프로필 허용 검토로 진행합니다. 이 결과로 추가 캡처/벤치마크/
인벤토리는 정당화되지 않습니다. PR188은 공유 쓰기 프로필을 설치/허용하거나
영구/무인/복구 지원을 증명하지 않습니다.
