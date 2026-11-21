# 37FRHG

개구리 마법사 캐릭터 시트(`reference/character_sheet.webp`)를 3D 모델로 바꿔, 37RHHG 와 같은 방식(힉스필드 3D 생성 + 리깅 → Godot 4 맥 앱, 동작은 코드)으로 화면 위를 걷게 하는 별도 프로젝트.
37RHHG 의 AI 연결·대화·말풍선·그림 버튼 메뉴 같은 인터페이스는 만들지 않는다.

## 지금 상태 (2026-11-21)

- 참조: 시트를 잘라 3배로 키운 `reference/views/front.png`·`front34.png`·`side.png`·`back.png`(1446² 흰 바탕). 측면·후면은 옆 그림의 손끝이 들어오지 않게 지움.
- 37RHHG 에서 가져온 것: `tools/rotate_glb.py`(+X → +Z), `tools/smooth_glb.py`(법선 재계산), `preview/`(걷기 확인용 Godot 프로젝트).
- 힉스필드: 기본 커넥터 "Higgsfield AI"는 모델 목록·잔액만 읽고 생성·업로드를 못 한다. 2026-11-21 사용자가 생성 도구가 있는 사용자 지정 커넥터 "Higgsfield"(`https://mcp.higgsfield.ai/mcp`, 힉스필드 웹 MCP 메뉴에서 추가)를 연결했다. 이미 열려 있던 세션에는 잡히지 않아서 새 세션에서 이어 간다. 힉스필드 웹 화면에는 3D 메뉴가 없다(3D 는 MCP 로만).
- 2026-11-21 커넥터 "Higgsfield" 연결됨(도구 `generate_3d`·`media_upload`·`media_confirm`·`jobs_wait` 등). `front.png` 업로드 완료: media_id `0b4ae21a-b86f-4d44-883e-bae8aff3b687`(업로드 URL 24시간 유효, media_id 는 계속 사용). Tripo P2(`delight`, `face_limit 30000`) 비용 34크레딧, 잔액 850.76.
- `side.png`(캐릭터 왼쪽 면, 화면 오른쪽을 봄) media_id `e6f3c1ca-e2d6-4a1f-9ea6-21745af56657`, `back.png` media_id `5a591a95-5917-453a-ab6c-1d407bd89c16` 업로드 완료.
- 다중 시점 비용(정면·왼쪽·후면 3장): Tripo H3.1 multiview 9크레딧(detailed 형태·텍스처 18), Meshy multi_image_to_3d 텍스처 30, Hunyuan3D v3(정면·후면·왼쪽 순) 15.
- 2026-11-21 H3.1 다중 시점 고품질(정면·왼쪽·후면, 18크레딧) 생성 → `models/frog_h31_raw.glb`(삼각형 28,292, 높이 0.98, 몸 정면 +X). 렌더 `out/h31_v1/`(px=정면, nx=후면, pz·nz=옆). **실패**: 머리가 앞뒤 양쪽에 얼굴이 생긴 꼴로 꼬였고 모자도 일그러짐. 원인 추정: `side.png`는 팔을 내리고 손을 가슴에 둔 자세라 정면·후면의 T자 자세와 어긋남.
- 4방향 스냅샷 도구: `tools/snap/`(Godot 프로젝트; `m.glb`를 넣고 `godot --path tools/snap --import` 후 `godot --path tools/snap` → px/pz/nx/nz.png, 모델 크기에 맞춰 화면을 잡음; pz=+Z 쪽에서 봄). PIL·trimesh 는 깔려 있지 않음.
- H3.1 다중 시점은 정면·왼쪽·후면·오른쪽 순서로만 받아서 2장이면 후면이 왼쪽으로 읽힌다. 앞뒤 2장은 Hunyuan3D v3(정면·후면·왼쪽·오른쪽 순).
- 2026-11-21 **Hunyuan3D v3 정면·후면 2장(기본값, 15크레딧) 성공** → `models/frog_hy3_raw.glb`. 정면이 이미 +Z(돌릴 필요 없음), 높이 1.16, 발바닥 y=0(노드에 X축 90° 회전이 들어 있음). 머리·모자·로브·책·물약 모두 정상, 색은 시트보다 약간 보라. 렌더 `out/hy3_v1/`(pz=정면). 재질은 metallic 0·양면이라 번들거림 없음.
- 문제: 삼각형 500,000·파일 30MB·텍스처 PNG 15MB. 앱·리깅용으로 줄여야 함(face_count 40000 으로 다시 뽑으면 19크레딧).
- 2026-11-21 같은 설정에 `face_count 40000`(19크레딧)으로 다시 생성 → **`models/frog_hy3_40k.glb`(이걸 쓴다)**: 삼각형 40,000·정점 26,007, 15MB(텍스처 PNG 14MB), 높이 1.17, 정면 +Z. 모양은 50만 면판과 거의 같고 정상. 렌더 `out/hy3_40k/`.
- 2026-11-21 `frog_hy3_40k.glb` 업로드(media_id `6531d819-4a7b-4379-96fe-892361aa244e`) → `3d_rigging`(`height_meters 1.0`, 5크레딧) → **`models/frog_rig.glb`**: 뼈 24개, 이름이 37RHHG 와 같음(Hips·Spine·Spine01·Spine02·neck·Head·Left/Right Shoulder·Arm·ForeArm·Hand·UpLeg·Leg·Foot·ToeBase 등). Armature 배율 0.01(뼈 단위 cm), 메시 높이 1.0·발바닥 y=0·정면 +Z, Hips 높이 약 0.37. 기본 클립 `Armature|clip0|baselayer` 하나 들어 있음. 텍스처 PNG 14MB 그대로. T자 기본 자세 렌더 `out/rig/` 정상.
- 스냅샷 도구는 스킨 메시면 노드 변환 대신 메시 자체 AABB 로 화면을 잡는다(Armature 0.01 배율 때문).
- 2026-11-21 걷기(`preview/`): `../models/frog_rig.glb`를 읽고 `godot --path preview -- custom`(로브 보정 없이 보려면 `nofix`, 기본 자세 `rest`) → `gif/customNN.png`, `./mkgif.sh custom` → `custom.gif`·`custom_sheet.png`(ffmpeg; PIL 없음). 왼쪽은 옆모습(-90°), 오른쪽은 -30°.
  - 리깅은 로브 전체를 다리 뼈에 거의 1.0으로, 고관절(0.336m) 위 허리까지 0.7~0.9로 묶어 놓아 그대로 걸으면 로브가 통째로 끌려갔다. `_fix_legs`: `LEG_FULL` 0.285 아래는 다리를 따르고 `LEG_NONE` 0.325 위는 Hips로. 다리 뼈 선분(허벅지·정강이·발)에서 `_leg_r(높이)` 넘게 떨어진 점(로브)은 다리를 `ROBE_FOLLOW` 0.45만 따른다. `_leg_r`은 허벅지 5.8cm, 종아리(0.13~0.18m) 6.6cm, 신발(0.10m 아래) 10cm. 초록 피부는 거리와 상관없이 다리. 거리 기준은 `preview/measure.gd`(`godot --headless --path preview -s measure.gd`, 안쪽 재는 부분은 그때그때 바꿔 씀)로 잰 값.
  - 2026-11-21 "앞으로 나간 다리의 종아리·신발이 뒤로 늘어남": 처음 기준(5.8cm 하나)이 종아리 피부(6cm까지)·신발(9cm까지)을 로브로 잘못 봤고, 리깅도 종아리·신발 목 점을 반대쪽 다리 뼈에 묶어 놓았다. 높이별 `_leg_r`로 바꾸고, 다리 살로 분류된 점은 자기 다리 사슬 밖 무게(반대쪽 다리·골반 등)를 가장 가까운 자기 다리 뼈로 옮긴다. 신발 목 뒤쪽 뾰족한 모서리는 기본 자세에도 있는 모델 모양이다.
  - 확인용 `-- dbg`: 로브·다리 분류를 색으로(초록 다리, 빨강 로브, 파랑 LEG_NONE 위).
  - 모델이 T자라 팔을 `ARM_DOWN` 50°(앞축 기준) 내리고 흔든다. 72°는 손이 왼쪽 허리의 책을 뚫었고 58°도 스쳐서, 책을 지우는 대신 팔을 벌렸다(2026-11-21). 정면·뒷면 확인은 `FRONT=1 godot --path preview -- custom`. 스킨의 bind 이름이 비어 있어서 뼈는 `skin.get_bind_bone` → `sk.get_bone_name`으로 찾는다.
  - 결과: 다리가 로브 사이로 걷고 자락은 조금만 흔들림, 책·물약은 허리에 붙어 따라감. 소매 속 팔 겹침 같은 세부는 아직 안 봄.
- 다음: 걷기 값 다듬기(필요하면) → `app/`(37RHHG 창·이동·혼자 돌아다니기·조명만). 텍스처는 JPG 로 줄일 것.

## 계획 (37RHHG 순서 그대로)

1. 정면 이미지 → `tripo_p2_image_to_3d`(`delight: true`, `face_limit: 30000`, 약 34크레딧). 필요하면 다중 시점(`tripo_h3_1_multiview_to_3d`, 정면·왼쪽·후면·오른쪽 순)과 비교.
2. 결과가 +X 를 보면 `tools/rotate_glb.py`로 +Z 정면으로 돌린 뒤 `3d_rigging`(5크레딧). 리깅은 +Z 정면을 가정한다.
3. `preview/`에서 걷기를 코드로 맞춘다(2등신이라 기성 동작은 안 맞음). 이 캐릭터는 긴 로브라 다리 가중치(로브 자락)가 37RHHG 치마와 같은 문제를 낼 것.
4. `app/`: 37RHHG 의 창·이동·혼자 돌아다니기·조명만 가져오고 talk.gd·말 도우미(bubble)·메뉴 버튼·목소리·업데이트는 뺀다.

## 알아둘 것 (37RHHG 에서)

- 생성 전에는 비용을 먼저 확인하고 사용자에게 물은 뒤 진행한다.
- 형태 스무딩은 쓰지 말 것(UV 가 밀려 눈 텍스처가 번짐). 법선 재계산만 안전.
- Tripo 재질은 PBR 때문에 번들거린다 → metallic 0, roughness 1, 노멀맵 끔.
