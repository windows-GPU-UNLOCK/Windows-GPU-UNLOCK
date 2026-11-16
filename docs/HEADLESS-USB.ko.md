# USB 스틱 headless 언락 — BitLocker

[English](HEADLESS-USB.en.md) | **한국어** | [README](../README.ko.md) | [내부 headless 안내](HEADLESS.ko.md)

이 페이지는 영어 [Headless USB 안내](HEADLESS-USB.en.md)의 BitLocker 절만 옮긴
것입니다. 빌드, 스틱 구성, 사용 절차는 영어 문서를 따르세요.

`stage-usb.ps1`은 C:의 BitLocker 보호가 켜져 있으면 첫 쓰기 전에 거부합니다.

## BitLocker

Secure Boot를 끈 상태에서 서명되지 않은 스틱으로 부팅하면 측정된 부팅 체인이
바뀌어 TPM이 BitLocker 키를 내주지 않습니다. 그러면 Windows Boot Manager가 복구
키를 요구하지만, headless 언락 직후에는 화면이 아직 꺼져 있어 이 화면이 보이지
않습니다. 입력이 없으면 Windows는 약 1분 뒤 의도적으로 전원을 끕니다
([Microsoft](https://learn.microsoft.com/en-us/troubleshoot/windows-client/windows-security/bitlocker-recovery-auto-shutdown-in-uefi-mode)).
스틱의 로그는 여전히 `FINAL status=0 ... clean=1`과 마지막 단계
`windows-close-files-next-then-final-verify-and-StartImage`로 끝나므로 인계 실패처럼
보입니다([#125](https://github.com/impacifist/Windows-GPU-UNLOCK/issues/125)).

스테이징 전과 매 언락 부팅 전에 복구 키를 준비하고, 관리자 PowerShell에서 보호를
일시 중단하세요. `-RebootCount 0`은 다시 시작할 때까지가 아니라 재개할 때까지
중단 상태를 유지합니다.

```powershell
manage-bde -status C:
Suspend-BitLocker -MountPoint "C:" -RebootCount 0
```

보호가 중단된 동안 볼륨 키는 디스크에 암호화되지 않은 상태로 저장되므로, 드라이브에
물리적으로 접근할 수 있는 사람은 누구나 데이터를 읽을 수 있습니다. 스틱을 더 이상
쓰지 않으면 일반 Windows 부팅에서 보호를 재개하세요.

```powershell
Resume-BitLocker -MountPoint "C:"
```

도구는 암호화 설정을 바꾸지 않습니다. `stage-usb.ps1`은 상태만 확인하며, 확인하지
못하면 멈춥니다(fail closed). 보호가 꺼짐 또는 일시 중단으로 보고될 때만 계속하고,
상태를 읽을 수 없거나 알 수 없는 값이면 첫 쓰기 전에 멈춥니다. 관리자 권한이면
`Get-BitLockerVolume`을 사용하고, 아니거나 이 cmdlet이 없거나 실패하면 Windows 셸의
BitLocker 속성을 읽습니다. "could not be verified"로 멈추면 관리자 PowerShell에서
다시 실행하고 `manage-bde -status C:`를 확인하세요.
스테이징 후 보호를 재개했거나 재부팅 횟수가 다 된 중단은 부팅 시점에 감지되지
않습니다.

스틱 언락 후 로그가 정상으로 끝났는데 약 1분 뒤 PC가 저절로 꺼지면 먼저 BitLocker를
확인하세요.

호스트 테스트: `research\headless\test-stage-usb-bitlocker.ps1`은 모의 상태로
BitLocker 검사를 확인합니다.
