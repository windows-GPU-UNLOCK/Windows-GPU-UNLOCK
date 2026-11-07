Windows에서 `powershell -NoProfile -File tools/test-display-identities.ps1`을 실행하세요. Documents/GPU-Unlock-Display-*/display-identities.json만 보내 주세요. 이름과 장치 인스턴스 접미사는 제외하고 열거자 종류와 PCI ID만 기록합니다. 준비 검사를 우회하거나 USB로 부팅하지 마세요. 그래프 준비용 Python과 LLVM은 FAT32 USB가 아닌 Windows 호스트에 설치합니다.

스키마2는 첫 역슬래시 앞의 짧은 열거자 토큰도 기록합니다(문자/숫자/밑줄/하이픈, 최대32자). 뒤의 모든 식별자 구성 요소는 제외하며 GUID/잘못된 접두사는 형태 이름만 기록합니다. 알 수 없는 버스를 식별하기 위한 것이며 EFI 준비 허용을 뜻하지 않습니다. 작은 JSON을 공유 전에 검토하세요.
