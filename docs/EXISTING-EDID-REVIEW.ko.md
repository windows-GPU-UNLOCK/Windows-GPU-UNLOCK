# 기존 EDID binding 검토 (#144)

```powershell
powershell -NoProfile -File .\tools\test-existing-edid.ps1
```

기존의 완전한 DIAG00/01.TXT 폴더를 선택하세요. 기존 Python3만 사용하며
-Python으로 설치된 정상 실행 파일을 지정할 수 있습니다. IMG/PROM은 불필요합니다.
공유 complete-graph/binding 파서를 재사용하고 CRLF를 지원합니다.
EDID_DISCOVERED와 EDID_ACTIVE의 BY_DRIVER edge를 따로 보고합니다. 숫자는
고유 이미지가 아니라 관측된 edge 수입니다. GUID/version은 펌웨어 메타데이터이며
release fingerprint 또는 검증된 소스 ID가 아닙니다.

#144의 공개 EDID_DISCOVERED owner는 version16,
605ced2c-583b-4171-9311-aa6e146b1a4b, reviewed_mouse_identity_match=false를
예상합니다. 이는 다른 ID로 bound 상태이지 부재가 아닙니다. no-EDID/detach
승인은 false를 유지하며 release 이후 생존 여부를 증명하지 않습니다.
누락/모호한 binding 또는 불완전 캡처는 검토를 중지합니다.

표시된 Documents 폴더의 검토한 edid-review.json만 보내세요. 사용할 수 없거나
차단/실패하면 중지하고 개인 정보를 제거한 짧은 오류를 보내세요. 새 캡처,
GU_NO_EDID_DRIVER gate 완화, 설정 변경 또는 펌웨어 부팅은 하지 마세요.
원본 캡처, 포인터, 이미지와 PROM은 비공개로 유지하세요. 로컬 테스트는 보고된
GUID/version의 합성 소유권 데이터이며 Dell 결과를 독립 검증하거나2560을 승인하지 않습니다.
# Issue144 반환 owner 수정

두 번째 same-build pair의 반환 metadata는 EDID_DISCOVERED owner를
e1ff8a3d-0a1f-49c2-67d3-930bcaee7798/version16으로 식별합니다.
파일마다 discovered BY_DRIVER1, active BY_DRIVER0입니다. 함께 존재하는
605ced2c-583b-4171-9311-aa6e146b1a4b/version16 이미지는 해당 edge owner가
아닙니다. 이전 연관 설명을 수정하며 존재/version만으로 ownership을 판단하지
않습니다. 반환 hash는 사용자 관찰이며 비공개 DIAG를 독립 재해시한 것이 아닙니다.

새 합성 two-image 회귀는 binding 순서를 뒤집어도 첫 same-version 이미지가 아닌
실제 edge의 owner를 선택하도록 검사합니다. 테스트4개가 통과합니다. foreign
binding은 no-EDID와 구분하며 generator의 identity 거부를 유지합니다. 첫 pair의
zero count는 no-EDID 취급이나 post-release 부재를 승인하지 않습니다. 원본 이미지,
새 캡처, 프로필 재생성, BME 변경 또는 하드웨어 실행은 요청하지 않습니다.

기존 Python만 사용하는 선택적 재현:
`python -I -m unittest discover -s research/profile -p test_edid_bindings.py`.
예상4개 OK; 재현한 경우 PASS 또는 정제된 짧은 실패만 반환하세요. 오류/tool/policy
차단 시 설치나 정책 변경 없이 중단합니다. 반환 metadata로 수정할 수 있으므로
반복은 필요하지 않습니다.
