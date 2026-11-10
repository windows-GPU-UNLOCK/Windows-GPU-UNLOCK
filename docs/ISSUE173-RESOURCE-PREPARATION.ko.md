# Issue173 resource 준비: 하드웨어 실행 미승인

MEG Z790 ACE(MS-7D86), BIOS1.G0, i9-13900K, segment0/bus1/device0/fn0의
EVGA2216/48973842와 Intel8086:A780/7D861462를 고정합니다. 기존 보고 graph
hash c1222d54c5487273fa6e9553e78ba8c57bfa5fe4100c14f27eeeedc738f2c242에서
얻은 pin입니다. NVIDIA command3/BAR081000000은 관찰이며 resource-map 증거가 아닙니다.

소스는 정확한 pin/명시적 bus1 generic diagnostic build에서만 이 tuple을 허용합니다.
unpinned generic, 다른 bus,403F1458은 MMIO 전에 거부합니다. PR118의 다른 카드
하드웨어 증거를 차용하거나 일반2216/profile/write 승인을 추가하지 않습니다.
graph 구성 데이터만으로 이 경계를 활성화할 수 없습니다.

RAM mock: generic269개, exact-pin4개 build 각14개, 다른 bus/board build 각2개
거부 검사 통과. pin 누락, unlock/release/auto-bus 조합, 변조 manifest를 거부합니다.
정확한 board/BIOS/target/companion 준비 mock도 통과합니다. sample Windows GUID
이미지는31744 bytes, AMD64, imports0, NX/dynamic-base이며 SHA256은
32ad49b611ae6d7e1a67ac2e288e5bee785fc003cd79e33d595ef246972c797b입니다.
사용자 이미지가 아니므로 staging/부팅하면 안 됩니다.

기존 Python/LLVM/MSVC host 환경의 새 source 폴더에서 공통 offline runner를
선택적으로 재현할 수 있습니다.

```powershell
powershell -NoProfile -File .\research\profile\test-zotac-probe.ps1 -FixtureMachine issue173
```

기존 -Clang/-LldLink/-VcVars로 이미 설치된 도구를 선택합니다. tool/policy 차단 시
설치/정책 변경 없이 중단합니다. mock, 금지 build, PE/manifest 그룹 PASS가
예상되며 재현한 경우 PASS 또는 정제된 짧은 오류만 반환합니다. 반복은 필요하지
않습니다. clang21.1.6의 최종 sample11111111 GUID 이미지 SHA256은
b95e146eff7d55ffde13151184dd6f131163c1c5c6999474739339d16212b365입니다.
compiler/GUID에 따라 bytes가 달라질 수 있으며 사용자 실행 증거가 아닙니다.

공통 준비 script의 backup/archive/readback/no-repeat gate와 acceptance prompt를
사용하며 실제 media는 staging하지 않았습니다. 향후 attended 제안에는 PCI
resource/attribute/parent callback, 고정 BAR0 DWORD16개, 최대1MiB PROM-window 읽기,
loaded-image CPU 복사, 읽기 부작용/firmware·display·input hang/Windows 복귀 실패,
수동 stop/recovery를 별도로 설명해야 합니다. MMIO 실행 허가, driver release,
reset/GPU write, firmware 실행/upload, profile 생성, unlock은 승인하지 않습니다.
자동 reboot/retry, 설정/케이블/iGPU 변경, graph 재캡처도 하지 않습니다.

실행 절차 전 최신 이슈, source/build/증거 수집을 다시 검토하고 해당 informed
acceptance를 받아야 합니다. Secure Boot/encryption 정책은 바꾸지 않고 확인합니다.
Intel header/BME 관찰은 복구 화면 증거가 아닙니다.

target BAR0 DWORD offset16개는000000,108154,108170,108180,108354,118128,
118234,110100,1183a4,1fa828,8219c0,822804,823804,82381c,823820,824140입니다.
PROM window300000..3ffffc이며 총 최대262160개 읽기입니다. 기존 Windows handoff는
EFI watchdog을 해제합니다. 향후 동의한 실행에서도 TV off/Intel enabled/케이블을
유지하고 Documents 오류 이력 때문에 기존 alternate local OutputRoot로 검토한
report.json만 수집합니다. 원본 DIAG/PROM/IMG/EFI/backup은 로컬 보존합니다.
2분 내 Windows가 시작하지 않으면 제안 복구는 power-off/USB 제거/정상 Windows
Boot Manager이며 미검증입니다. 복구 실패 시 중단하고 검토 없이 반복하지 않습니다.

기존 issue172 template은 sample GUID로 독립 재빌드하여 이전 personalized bytes와
완전히 일치했습니다. source hash metadata만 갱신하며 게시/acceptance 보류는 유지합니다.
