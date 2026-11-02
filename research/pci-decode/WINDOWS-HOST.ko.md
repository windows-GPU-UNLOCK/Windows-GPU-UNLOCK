# Windows 호스트 검증

기존 Python3, clang, MSVC/Windows SDK가 있는 환경에서 고정 소스로 실행하세요.

```powershell
powershell -NoProfile -File .\research\pci-decode\test-decode-sync.ps1
```

도구 검색이 실패하면 기존 설치 경로를 -Python, -Clang, -VcVars로 지정하세요.
설치, 영구 PATH 수정 또는 정책 변경은 요청하지 않습니다. 자식 프로세스에서만
컴파일러 환경을 설정하고 기존 공유 core/adapter/capture 및 모든 컴파일된
테스트 전에 정확한 device/chip/memory/driver 승인 suite(2204의6000a 및
다른 제품군 거부 포함)를 실행합니다. 이어서
guard mutation 테스트를 실행합니다. 새 Documents/GPU-Unlock-Decode-Host-*/run/
summary.json을 생성합니다. PR139 병합 소스에서 전체 PASS와21개 mutation 검출을
예상합니다. 네이티브 Windows RAM 모의 테스트이며 EFI ABI/하드웨어, production
통합, 프로필 승인 또는 Windows 복귀 증거가 아닙니다. 필요하면 검토한
summary.json만 보내세요. 관리자가 이미 실행한 테스트를 제보자가 반복할 필요는
없습니다. 도구 누락/실패면 중지하고 개인 정보를 제거한 짧은 오류를 보내세요.
캡처, 펌웨어, USB 준비 또는 재부팅은 없습니다.
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

Windows에서 core65388 +adapter596945 +capture52197 assertion, compiled mutation21개,
exact-family test4개가 통과했습니다. 아래 기존 명령의 summary.json에는
reported_command_cache_pair_fixture_passed=true, private_capture_replayed=false,
parent_stop_transition_admitted=false가 표시되고 hardware/EFI는 false입니다.
