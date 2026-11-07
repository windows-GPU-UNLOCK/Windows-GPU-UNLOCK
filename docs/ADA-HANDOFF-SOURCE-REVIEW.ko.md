# 외부 Ada handoff 변경 소스 검토

2026-11-02에 소스 데이터로 검토했으며 빌드/실행하지 않았습니다.
두 외부 PR은 검토 시점에 open, unmerged입니다.

- [PR3](https://github.com/Zihao-Wu06/gpu-unlock-for-windows/pull/3),
  head698671bb3405fd38d4bea48fd4a7ea5e7b806847.
- [PR4](https://github.com/Zihao-Wu06/gpu-unlock-for-windows/pull/4),
  head724c4e806b688d3a95199f106c8d0c0732d034d7.

PR3는 GOP 진단과 firmware 동작을 결합합니다. target SetMode0 helper는
framebuffer 두 필드가0이고 device-path 부모가 target PCI handle인 경우를
요구합니다. 별도 ConnectController helper는 열거한 GOP들과 ConsoleOut에도
동작하므로 target-only ancestry 검사보다 넓습니다. 진단 구분을 인정해도
전체 reconnect를 도입할 근거는 아닙니다. mode0가 원래 화면 geometry나
모든 시스템의 복구 모드라는 증거는 없습니다.

PR4 DisplayChildNoGop는 child 속성, agent, open count, 제한된 path와 target
PCI ancestry를 검사합니다. 그러나 live framebuffer 거부는 HandleProtocol 성공,
non-null GOP/Mode, 두 framebuffer 필드 nonzero인 경우에만 실행됩니다.
lookup 오류, 성공이지만 null GOP, Mode 누락, 부분 framebuffer 정보도 ancestry
검사로 진행할 수 있습니다. ancestry는 부모를 식별할 뿐 미확인 상태를 사용하지
않는 display의 증거로 바꾸지 않습니다. 이후 helper가 성공하면 caller는 기록하지
않은 child를 허용합니다.

재사용 전 protocol 부재, lookup 오류, 잘못된 성공, mode 누락, 부분/live
framebuffer, 명확히 관측된 zero framebuffer를 구분해야 합니다. 정확한 ownership,
전체 child 관계, 동작 후 재검증과 Windows 복귀는 별도 조건입니다. fallback,
release 허가, SetMode/reconnect 호출, 프로필 또는 하드웨어 절차를 추가하지 않습니다.

issue2의 Inno3D4070Ti/Z690M 결과는 기여자 보고이며 기존4070SUPER나 MSI4070Ti를
입증하지 않습니다. 별도 미공개 Windows-userland POC는 unlock 미달성을 명시했고
검토할 구현이 없으며 이 EFI patch와 별개입니다.
