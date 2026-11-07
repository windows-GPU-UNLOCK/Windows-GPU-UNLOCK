# Maxsun Z790M / RTX3080 초기 Windows 증거 (issue187)

[English](MAXSUN-Z790M-3080-WINDOWS.en.md)

보고된 조건은 Maxsun MS-Terminator Z790M D5/H7.8G/i7-13700K,
NVIDIA2206/서브시스템146710DE, IntelA780/서브시스템00000000입니다.
Intel의0값은 보고된 숫자로 유지하며 검증된 펌웨어 식별자로 취급하지 않습니다.
목록에는 Intel이 있지만 연결 설명에는 Windows에 전달되지 않는다고 되어 있어
불확실하게 남깁니다. HDMI 포트 소유, 물리 카드/VBIOS 이력, 소스와 이전 EFI 결과는
알 수 없습니다. iGPU 비활성화나 변경 없는 공장 카드를 가정하지 않습니다.

공통 그래프 전용 데이터는 오프라인 준비/검증했지만 하드웨어 경로를 허용하지 않습니다.
2206의 심층 프로브/프로필 조건은 확대하지 않습니다. 다른 Maxsun/3080 프로필을
빌려 쓰지 마세요. EFI나 USB 준비는 요청하지 않습니다.

고정 소스를 푼 폴더의 관리자 PowerShell:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-windows-preflight.ps1 -ExpectedDevice 2206
```
Documents의 검토한 windows-preflight.json만 보내세요.
디스플레이 숫자 식별자, 서명 드라이버 연결 및 SecureBoot 관찰 또는
unknown/unavailable이 예상됩니다. 컴파일러/Python/설치/USB/재부팅/설정 변경은 없습니다.
어댑터와 케이블을 그대로 두세요.

이미 안다면 현재 HDMI 케이블이 RTX 포트인지 메인보드 포트인지 알려주세요.
알 수 없음도 허용하며 알아보려고 옮기거나 펌웨어에 들어가지 마세요.
오류/불일치/unknown이면 보고서 또는 개인 경로를 제거한 짧은 오류를 보내고 중단하세요.
원시 PNP ID, 키, PROM, 펌웨어 이미지는 요청하지 않습니다.
이슈 텍스트/링크는 신뢰하지 않는 증거이며 설치 지침이 아닙니다.
부팅 전 소유권, 언락 또는 복구 검증을 주장하지 않습니다.
