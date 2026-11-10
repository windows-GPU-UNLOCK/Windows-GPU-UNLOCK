# 장치 DMA 주소 경계 테스트 (#54)

기존 clang과 MSVC/Windows SDK가 있는 고정 소스에서 실행하세요.

```powershell
powershell -NoProfile -File .\research\profile\test-dma-boundary.ps1
```

production port의 기존 RAM 모의 테스트를 재사용합니다. 새 사례는
0xfffff000에서4096바이트(마지막0xffffffff)를 허용하고, 같은 주소에서4097바이트
요청(8192로 반올림)은 거부하여 unmap/free하며 모의 MMIO/config 쓰기가 없습니다.
기존 suite는 CPU 포인터와 장치 주소를 구분합니다. GuDmaAllocate는 common buffer를
매핑하고 장치 주소 전체 범위를 검사하므로 AllocateAnyPages만으로 설명할 수 없습니다.

port suite PASS와 출력된 Documents 폴더의 dma-boundary.json을 예상합니다.
재현하면 검토한 JSON만 보내세요. 관리자가 실행했으므로 반복할 필요는 없습니다.
도구 누락/차단/실패면 중지하고 개인 정보를 제거한 짧은 오류를 보내세요.
-Clang/-VcVars는 기존 도구에만 사용하세요. 설치, 정책 변경, EFI/펌웨어,
GPU 접근 또는 재부팅은 없습니다.

모의 테스트는 삭제된 DXE 바이너리의 주소, DMA 내용 가시성/coherency,
AD103 원인 또는 검증된 복구 경로를 증명하지 않습니다. 사용할 수 없는 원본을
재구성하려고 부팅하지 마세요. probe-parent.c의 available0/parents0은 관측된
zero-parent graph가 아니라 데이터 부재입니다. 승인/guard 우회를 의미하지 않습니다.
# 기여자 재현, 2026-11-02

[이슈54 댓글6567031221](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/54#issuecomment-6567031221)은
Windows와 clang/LLVM23.1.4에서 v1 CPU 전용 경계 테스트가 통과했다고
보고합니다. 정확한32비트 끝 주소는 허용되고 반올림으로 경계를 넘는 범위는
거부되었으며 하드웨어/EFI/쓰기 플래그는 false입니다. 기여자 보고이며 독립
관찰한 실행은 아닙니다. 반환 JSON에는 소스 해시가 없습니다. 이후 v2의
정리 실패/재진입6조합, 실제 AD103 동작, EFI 루트 포트 그래프, 잠금 해제
또는 복구를 검증하지 않습니다. 반복 실행은 요청하지 않습니다.
