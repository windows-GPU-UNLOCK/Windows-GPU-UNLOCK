# 로컬 프로필 잠금 해제의 현재 USB 요구 이유 (191)

수동 부팅 메뉴 선택과 로드된 이미지의 미디어 ID는 다른 입력입니다. USB 빌드는
EFI를 읽은 볼륨의 장치 경로를 검사하며 사용자의 선택 방식을 조회하지 않습니다.
내부 미디어를 수동 선택해도 USB 경로 노드가 없으면 그 빌드는 거부합니다.

이는 강제된 배포/볼륨 연결 조건이지 USB 하드웨어가 안전하거나 내부 미디어가
본질적으로 위험하다는 일반 주장이 아닙니다. GU_USB_MEDIA/GU_USB_PROBE의
handoff Prepare()는 OwnDevice에서 로그/자식 볼륨을 정하고 USB 경로를 요구하며,
별도 고정된 Windows ESP를 유일하게 찾고 windows==own을 거부하고 로드된 Windows
이미지 DeviceHandle을 확인합니다. 검증된 자식 바이트도 같은 실험 볼륨에서
DeviceHandle을 맞춰 로드합니다. 이는 검증된 배포 표면과 함께 볼륨/자식/복귀 경로를
연결하는 조건이며 GPU/펌웨어/복구 안전을 증명하지 않습니다.

소스에는 GuInternalPartition과 유일한 파티션 검색을 쓰는 내부 분기도 있습니다.
하지만 생성된 로컬 프로필 쓰기 경로를 내부 미디어에서 허용하지는 않습니다.
Get-LocalProfile은 UsbOnly=true이며 build.ps1은 이런 프로필의 ExperimentalUnlock을
UsbMedia 없이 빌드하지 않습니다. 기존 내부/고정 프로필 코드를 다른 로컬 프로필에
그대로 재사용할 수 없습니다. USB 제거는 구체적인 복구 방법이지만 내부 복사본을
수동 선택하는 것만으로 볼륨/복귀 조건을 검증하지 않습니다.

내부 로컬 프로필 경로는 별도 검토된 빌드/배포 조건, 파티션/볼륨/자식 연결,
소스/증거 영수증, 정리/Windows 복귀 및 복구 테스트가 필요하며 하드웨어 허용 조건을
바꾸면 안 됩니다. 이 문서는 로드맵 약속이나 우회/설치 지침을 제공하지 않습니다.

기존 LLVM/MSVC/Python만 쓰는 오프라인 네이티브 생산 헤더 테스트:
```powershell
powershell -NoProfile -File .\research\profile\test-media-contract.ps1
```
예상10검사/실패0입니다. InternalAllowed일 때만 고정 내부 경로 허용, USB 필수 거부,
별도 Windows ID, 정상 USB, 잘못된/다중 인스턴스/null 경로 거부를 검사합니다.
EFI가 아닌 RAM 전용 네이티브 모의를 컴파일하며 펌웨어/GPU/디스크 API를 호출하지
않습니다. 로컬 통과는 내부 부팅/복구 검증이 아닙니다. 도구 누락/실패 시 설치,
정책 변경 또는 부팅 없이 중지합니다. 확인용 소유자 재실행/파일은 필요하지 않으며
재현 결과가 다를 때만 짧은 개인정보 제거 출력/오류를 반환합니다.

소스: internal-boot/boot/media.h,handoff.c Prepare/LoadUnlock;
internal-boot/unlock/app_io.c UsbPath;local-profile.ps1 Get-LocalProfile;build.ps1.
