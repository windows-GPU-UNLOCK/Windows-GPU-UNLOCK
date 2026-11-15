# Windows 호스트 검증

기존 Python3, clang, MSVC/Windows SDK가 있는 환경에서 고정 소스로 실행하세요.

```powershell
powershell -NoProfile -File .\research\pci-decode\test-decode-sync.ps1
```

도구 검색이 실패하면 기존 설치 경로를 -Python, -Clang, -VcVars로 지정하세요.
설치, 영구 PATH 수정 또는 정책 변경은 요청하지 않습니다. 자식 프로세스에서만
컴파일러 환경을 설정하고 정확한 device/chip/memory/driver 승인 테스트
(2204의 6000a 및 다른 제품군 거부 포함)를 먼저 실행합니다. 이어서 core,
adapter, capture/composition, owned-lifecycle, workspace의 다섯 RAM 모의 테스트와
컴파일된 guard mutation 테스트를 실행합니다. 새
Documents/GPU-Unlock-Decode-Host-*/run/summary.json을 생성합니다.
현재 runner는 다섯 테스트의 PASS와 34개 mutation의 정확한 예상 assertion 실패를
요구합니다. Windows에서 이 명령을 실행해도 EFI ABI/하드웨어, production 통합,
프로필 승인 또는 Windows 복귀 증거가 되지는 않습니다. 이 실행 안내 자체는
현재 통합 소스가 네이티브 Windows에서 검증되었다는 뜻이 아닙니다.
필요하면 검토한 summary.json만 보내세요. 관리자가 이미 실행한 테스트를
제보자가 반복할 필요는 없습니다. 도구 누락 또는 실패 시 중지하고 개인 정보를
제거한 짧은 오류를 보내세요. 캡처, 펌웨어, USB 준비 또는 재부팅은 없습니다.
# X870/GA104 command/cache 및 Stop 전이 (#202)

공통 RAM model에 보고된 GPU2484/f2781569, parent1022:14db(0:0:1.1),
GPU command/status00100002/cache0300, parent00100007/cache0700을 전사했습니다.
미제공 config word/BAR/supported mask/handle은 합성입니다. 비공개 전체 캡처
재현이나 해당 하드웨어 승인이 아닙니다.

research cache-only 경로는 GPU의 stale IO attribute만 제거하고 command00100002와
모든 parent 필드를 보존합니다. parent00100003/cache0300은 자체 일치하지만 정확한
before/after 비교에서 거부합니다. 보고된 stopped pair(GPU00100000/cache0 및
parent 전이)도 correction callback 없이 거부합니다. parent BME clear는 firmware
동작 보고이며 integration 허용이나 memory restore/payload/FLR/reconnect/
no-reset Windows handoff 증거가 아닙니다.

production LOCAL/CapturePermit은 그대로이며 correction research core는 연결되지
않았습니다. 다른 머신 pre-step/profile, bridge BME enable을 승인하지 않습니다.
기존 정제 Stop/snapshot-match/claim-close 코드 및 정확한 private build ID가
있으면 소스 검토에 도움이 됩니다. 새 하드웨어 실행이나 없는 post-release
artifact는 요구하지 않습니다.

## 검증 범위와 소스 식별

[독립 Windows 검증 보고](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/pull/192#issuecomment-6569927972)는
과거 소스 `e5a4326`에 고정되어 있습니다. 이후 커밋이나 현재 통합 소스를 검증한
보고가 아닙니다. 별도로 소스 작성자는 이후 문서
`8078ee9875b58f27e8721161859052bf307e9378`에서 Windows의 core 65,388개,
adapter 596,945개, capture assertion 52,197개, mutation 21개 및 family 테스트
4개 통과를 보고했습니다. 이 후속 수치 주장은 앞서 소스가 고정된 독립 보고와
다르며 현재 통합 소스의 네이티브 Windows 검증 증거가 아닙니다.

runner의 저장소 상대 경로 기반 소스 해시 24개로 식별되는 통합 실행 소스는
Linux에서만 검증했습니다.
GCC 14.2에 `-fshort-wchar`를 추가하는 wrapper로 core 119,037개,
adapter 1,541,757개, capture/composition 52,733개, owned-lifecycle 822,653개,
workspace assertion 1,553,181개, 정확한 assertion으로 검출한 mutation 34개,
runner 회귀 테스트 7개 및 family 테스트 4개가 통과했습니다. Windows 도구 체인,
EFI ABI 또는 하드웨어 적합성을 입증하지 않으며 통합 코드의 네이티브 Windows
검증은 아직 확인되지 않았습니다.

위 명령에는 command/cache fixture가 포함됩니다. summary.json에는
reported_command_cache_pair_fixture_passed=true, private_capture_replayed=false,
parent_stop_transition_admitted=false가 표시되고 hardware/EFI는 false입니다.
