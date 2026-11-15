# 이슈 114: 사용자 입회 GA106 자원/PROM 캡처 1회

[English](ZOTAC-GA106-CAPTURE.en.md) | **한국어**

Gigabyte B650M DS3H BIOS F21, Ryzen 5 7600, Zotac RTX 3060 Twin Edge
`2504 / 19da:2630`, 보고된 활성 AMD 보조 어댑터용입니다. 모니터 3개를 NVIDIA에
연결한 상태와 AMD 출력의 케이블 없는 상태를 유지하세요. AMD는 공급자/존재만
확인하며 정확한 PCI 튜플은 검증하지 않고 AMD MMIO도 읽지 않습니다.

기존 `c403e8f` 진단은 심층 읽기 전에 NVIDIA 신원을 거부했습니다. 새 테스트는
기존 일반 GA106 읽기 경로에 **추가 EFI 핀**을 적용합니다. 장치 `250410de`,
subsystem `263019da`, segment 0, bus 1, device/function 0입니다. 일반 경로의
다른 허용 ID도 추가 핀과 다르면 거부합니다. 기존 class/command, 16 MiB BAR0
자원, 인터페이스/상태 검사를 유지합니다. 캡처 전용이며 프로필 생성/언락 준비는 없습니다.

## 새로운 범위

실시간 검사를 통과하면 PCI 자원/속성/부모 상태를 읽고 다음 BAR0 DWORD 16개를
각각 한 번 읽습니다.

```text
000000 108154 108170 108180 108354 118128 118234 110100
1183a4 1fa828 8219c0 822804 823804 82381c 823820 824140
```

1 MiB PROM 창 `300000..3ffffc`도 한 번 읽어(직접 MMIO 읽기 최대 **262,160회**)
PROM.BIN으로 저장하고 CPU 메모리의 로드된 펌웨어 드라이버 이미지를 복사합니다.
소유권/GOP 정보를 기록한 뒤 기존 Windows 인계를 시도하며 기존 코드처럼 EFI
watchdog을 끕니다. 진단은 GPU/PCI 쓰기, decode 활성화, 드라이버 해제, GPU reset,
GPU 펌웨어 업로드/실행, 언락을 추가하지 않습니다. 읽기에도 부작용이나 멈춤이
있을 수 있습니다. 화면/입력/펌웨어/Windows가 실패할 수 있고 복구는 입증되지
않았습니다. 수동 전원 종료/USB 제거가 필요할 수 있으며 자동 재시도/롤백은 없습니다.

## 한 번 준비하고 실행

고정 소스를 새 폴더에 풀고 Python/LLVM과 여유 공간 **256 MB** 이상의 기존
FAT32 USB 데이터 장치를 사용하세요. Secure Boot는 이미 꺼져 있어야 합니다.
소스 폴더에서 관리자 PowerShell로 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-zotac-ga106.ps1
```

USB 문자를 입력하고 새 범위를 수락할 때만 **ACCEPT-MMIO**를 입력하세요.
Windows에 보고된 플랫폼/NVIDIA 튜플/AMD 존재, 현재 Windows ESP, USB 신원을
확인한 뒤 핀 적용 이미지를 빌드하고 PE/소스 manifest, 기존 부트로더 백업,
최종 복사본을 검증합니다. 기존 `RTX3090-UNLOCK`은 같은 볼륨에서 보존용 이름으로
바꾸고 새 실행용 폴더/표식을 만듭니다. 포맷/재부팅하지 않으며 자체 표식이 있으면
재준비를 거부합니다. 오류/불일치/정책 차단 시 개인 경로를 지운 짧은 메시지를
보고하고 중단하세요. 설정 변경이나 우회를 하지 마세요.

**READY** 후 완전히 종료하고 USB를 한 번 직접 선택하세요. Shift 키는 필요
없으며 수집 후 Windows 시작이 예상됩니다. 2분 내 Windows가 시작하지 않으면
전원을 끄고 USB를 제거한 뒤 평소 Windows Boot Manager를 선택하세요. 복구 실패
시 중단하세요. 성공처럼 보여도 근거 검토 전까지 같은 실행을 반복하지 마세요.

## 파일 하나 회신

Windows에서 필요하면 USB를 다시 연결하고 같은 스크립트로 수집하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-zotac-ga106.ps1 -Collect
```

표시된 문서 폴더의 **report.json**만 검토해 첨부하고 **Windows 직접 시작** 또는
**수동 복구 필요**를 알려주세요. 원본 DIAG/PROM/IMG/EFI와 보존 폴더는 로컬에
남기고 수집 후 USB를 제거하세요. Python이 잘못 선택되면 `-Python`으로 기존
정상 실행 파일 경로를 지정할 수 있습니다.

보고서는 적합성 결과와 개인정보를 제한한 캡처 표식을 포함합니다. 성공 캡처가
하나뿐이면 일치하는 캡처 두 개가 필요한 경로이므로 `needs_data`/`capture_count`가
나올 수 있습니다. **지금 두 번째 캡처를 만들지 마세요.** 허용 범위 거부 표식만으로
어느 검사가 실패했는지 알 수 없으며 쓰기 권한도 부여하지 않습니다. 이후는
근거/코드 적합성 검토와 별도 범위의 프로필 단계이며 자동 언락이 아닙니다.

유지관리자 CPU/모의 검사는 새 소스 폴더와 개발자 컴파일 환경에서
`research/profile/test-zotac-probe.ps1`로 실행합니다(선택적 `-VcVars` 경로).
테스트용 Windows GUID는 가짜이므로 해당 산출물을 준비하거나 부팅하지 마세요.

준비 과정은 빌드 전과 USB 기록 직전에 시스템 볼륨의 완전 복호화를 확인합니다. 보호 해제만으로 충분하지 않습니다. 암호화/전환/알 수 없는 상태 또는 공급자 실패이면 설정 변경 없이 중단합니다. 테스트를 위해 보호 일시 중지나 복호화를 하지 마세요. 기존 파일 수집은 계속 가능합니다.
# 준비 단계 identity 수정

Resource configuration schema2는 companion PCI display adapter를 vendor뿐 아니라
device/subsystem까지 고정합니다. issue114는 NVIDIA2504/263019DA와 함께
AMD1002:164E / D0001458을 요구합니다. 누락/중복, 다른 AMD device/subsystem,
불완전/wildcard companion 데이터, 이전 schema1은 staging 전에 거부합니다.
companion이 없는 구성은 세 필드를 모두 null로 유지하며 source/config revision을
함께 사용해야 합니다. 준비 조건만 제한하며 MMIO/release/unlock 허가를 추가하지
않습니다. 케이블 없는 iGPU의 preboot 복구를 입증하거나 재캡처를 요청하지 않습니다.
별도 issue172 게시 보류는 유지됩니다.
