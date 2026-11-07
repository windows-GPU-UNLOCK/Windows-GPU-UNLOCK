# EDID-bound 다중 child runtime 검토

issue114의 반환 JSON은 허용2개 대비 child3개를 확인합니다. 비공개 graph 자체는
독립 검증하지 않았습니다. 모니터 변경이나 추가 부팅은 요청하지 않습니다.

non-aggregate GU_HEADLESS_RESEARCH FullConsumers는 최대4개 child를 순회하며
path/PCI 부모, 동일 EDID owner, secondary child의 GOP/text consumer 부재를
검사합니다. child1개를 요구하는 aggregate fallback은 다른 전처리 분기입니다.
이전 generator/local header는 EDID-bound2개 초과를 명시적으로 거부했습니다.
runtime 용량만으로 이 guard를 완화할 수 없습니다.

기존 공통 RAM-only runner에 선택적 --card/--children selector를 추가했습니다.
기본 matrix와 기존 제외 조건은 유지합니다. 기존 host compiler 환경에서 baseline:

```text
python -I research/profile/test_local_release.py --card 0x250410de --children 2 --output <new-output-folder>
```

GA1068개 조합(bus1/2b, PCI command2/3, EDID/no-EDID)이 로컬 통과했습니다.
EDID 각6456개, no-EDID 각4961개 검사입니다. 합성 RAM fixture의 기존2-child
production code 동작이며3-child 검증, vendor firmware 실행, 기여자 하드웨어
증거가 아닙니다.

현재 공통 generator/header는 non-aggregate child1..4개를 허용합니다.
정확한 path, agent/open count, 동일 EDID owner, role/code pin, 별도 capture
일치 조건은 유지합니다. runtime은 생성된 local metadata와 관측 child 수의
정확한 일치도 요구합니다. aggregate2개 초과 및 child5개는 계속 거부합니다.
identity, MMIO, vendor transaction, recovery, write 승인을 추가하지 않습니다.

GA1063/4-child native matrix16개 조합이 RAM-only 통과했습니다. 3-child EDID는
각7249개,4-child EDID는 각7956개 검사입니다. 마지막 child의 잘못된 owner,
중복 owner, 잘못된 controller/open count mutation4개는 EDID/NVIDIA detach,
decode enable, exclusive claim 전에 중단합니다. 기존 late path/code/consumer,
EDID 누락, partial-stop 오류도 검사합니다.

기존 파일만 tools/test-existing-captures.ps1로 재검사할 수 있습니다. 나머지
검사를 통과해야 기존 count 거부가 해소되며 다른 거부가 나타날 수 있습니다.
파일1개이면 capture_count는 유지하고 hardware/write는 false입니다.
프로필 생성, 새 캡처, staging/부팅, guard override는 승인하지 않습니다.
비공개 실제 graph 및 물리 release는 미검증입니다.
