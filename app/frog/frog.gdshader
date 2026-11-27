// 개구리 마법사(37FRHG) 재질. 소녀의 face.gdshader 와 따로 두되, main.gd 가 넘기는 값 이름은 같다
// (head_inv·blink·happy·tint·bloom·mouth).
// - 입 벌리기(mouth, 2026-11-23): frog.gd 가 입선·턱 밑을 잘라 아래턱 점을 UV2.x(0~1)로 표시하고 입 안 면(UV.x -3 입천장, -4 혀)을
//   덧붙였다. 정점 셰이더가 머리 좌표에서 아래턱을 경첩(입꼬리 안쪽 가로축)으로 돌린다. 윗입술 위는 움직이지 않는다.
// - 눈 깜빡임: 개구리 눈은 머리 위로 튀어나온 공이라 눈알 공 위에 위·아래 눈꺼풀을 칠한다.
//   소녀의 웃는 눈(happy)도 감은 눈으로 대신한다.
// - tint(말 모델이 Sonnet): 의상(모자·로브) 보라 → 검정, 의상의 노란(금) 장식 → 터키색(2026-11-22, 처음엔 핑크, 그다음 밝은 금색).
// - bloom(목소리 켬): 옆구리 유리병 물약 → 노랑. 병 자리는 frog.gd 가 정점 색 파랑 0 으로 표시해 둔다.
// 머리 좌표: main.gd _face_update 의 틀(머리 뼈 원점, 캐릭터 왼쪽·위·앞, 월드 단위)을 unit_scale 로 모델 단위로 바꿔 cm 로 쓴다.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform mat4 head_inv;                 // 월드 → 머리 좌표
uniform float unit_scale = 1.0;        // 월드 단위 → 모델 단위(개구리를 키운 배율의 역수)

uniform float blink = 0.0;             // 0 뜬 눈 ~ 1 감은 눈
uniform float happy = 0.0;             // 소녀의 웃는 눈. 개구리는 감은 눈으로
uniform vec3 eye_c = vec3(8.2, 10.7, 11.0);   // 왼쪽 눈알 중심 cm(오른쪽은 x 반대). 37FRHG measure.gd 로 구 맞춤.
uniform float eye_r = 3.7;
uniform float seam = -0.15;            // 다 감았을 때 위·아래 눈꺼풀이 만나는 높이(반지름 단위)
uniform vec3 lid : source_color = vec3(0.45, 0.55, 0.14);       // 눈 둘레 초록
uniform vec3 lid_line : source_color = vec3(0.17, 0.24, 0.05);  // 눈꺼풀 끝 선
uniform float line_w = 0.28;           // cm
uniform bool debug = false;            // 눈알 판정 자리를 빨강으로

// 의상 색: 색상(hue)을 돌려 음영은 남기고, 보이는 밝기는 처음과 끝 사이로 곧게.
// 의상은 색상 0.68~0.80·명도 0.5 이하. 물약 병은 같은 보라~분홍이지만 명도 0.6 이상이라 빠진다.
uniform float tint = 0.0;
uniform vec3 tint_from : source_color = vec3(0.24, 0.17, 0.42);   // 의상 보라(색상 0.73)
uniform vec3 tint_black : source_color = vec3(0.10, 0.095, 0.11); // 검정(원래 보라 가장 밝은 곳이 이 색, 그늘은 비율대로 더 어둡게)
uniform float gold_from_h = 0.095;     // 의상 금 장식 색상(모자 띠·테두리·자수, 0.08~0.11)
uniform float gold_w = 0.035;
uniform vec3 gold_to : source_color = vec3(0.19, 0.85, 0.80);     // 터키색(2026-11-22, 처음엔 밝은 금색 1.0, 0.84, 0.32)
uniform float gold_gain = 1.1;         // 밝기 올림(금색일 땐 1.35, 터키색은 형광처럼 떠서 1.1)
uniform float face_lo = -1.5;          // 금색에서 뺄 얼굴 높이(머리 좌표 cm): 입선 y≈4.7, 눈 흰자 y 8~14
uniform float face_hi = 12.5;
uniform bool tint_debug = false;

// 유리병 물약 색: 원래 하늘색~보라~분홍 그라데이션을 bloom_to 쪽으로 모으되 색상 차이를 bloom_spread 만큼 남긴다.
// bloom_to 는 아무 색이나 된다(37FRHG 는 말로 고른 색, 37RHHG 는 노랑). 손에 든 병·병 속 공도 같은 표시(파랑 0)라 같이 바뀐다.
// 밝기는 bloom_to 명도 비율(노랑은 예전처럼 ×1.1), 채도는 bloom_to 가 흐릴수록(흰색·회색) 더 따라간다.
uniform float bloom = 0.0;
uniform float bloom_from_h = 0.72;
uniform vec3 bloom_to : source_color = vec3(0.98, 0.80, 0.16);    // 노랑
uniform float bloom_spread = 0.12;
uniform bool bloom_debug = false;
// 뒤 병(허리에 남는 병, 정점 색 파랑 0·빨강 1) 액체만 검게(0~1). 37FRHG 가 인터넷이 끊겼거나 Claude 를 쓸 수 없을 때 켠다
// (2026-11-26 사용자 요청). bloom(두 병의 상태 색)보다 뒤에 칠한다.
uniform float back_dark = 0.0;

// 소품 들어 보이기(37FRHG preview ⑩ 책·⑪ 유리병): 소품 점은 frog.gd 가 정점 색 빨강(책 0, 병 0.5)으로 표시하고 골반에만 묶어 둔다.
// book_m·vial_m 은 월드 → 월드 변환(골반에 붙은 지금 자리 → 손에 든 자리). 단위 행렬이면 허리 그대로.
// 붙어 있던 로브 자리(정점 색 초록 책 0·병 0.5, 알파 = 기본 자세 높이 0.30~0.45 m)는 들고 있는 동안(*_away)
// 허리띠 높이는 갈색, 나머지는 로브 보라로 덮는다(아래 tint 도 그대로 먹는다).
uniform mat4 book_m = mat4(1.0);
uniform mat4 vial_m = mat4(1.0);
uniform float book_away = 0.0;
uniform float book_hide = 0.0;
// 소매 속 팔 그늘(2026-11-24): 그림자가 없어서 넓은 소매 입구로 보이는 안쪽 팔(초록)이 바깥처럼 밝았다.
// 기본 자세(T자) 머리 좌표 |x| 가 소매 끝(sleeve_x, 잰 값 약 26cm)보다 안쪽인 팔 피부를 깊이에 따라 어둡게.
uniform vec2 sleeve_x = vec2(21.0, 26.5);      // 이 사이에서 sleeve_dark → 1
uniform float sleeve_dark = 0.22;        // 책 읽기(⑫): 펼친 책(read_book.gd)을 띄우는 동안 허리 책(빨강 0)을 숨긴다
uniform float vial_away = 0.0;
uniform vec3 vial_in : source_color = vec3(0.50, 0.30, 0.72);   // 병 속(로브에 붙어 있던 뚫린 자리 안쪽 면)
uniform vec3 robe_col : source_color = vec3(0.17, 0.13, 0.32);
uniform vec3 belt_col : source_color = vec3(0.25, 0.16, 0.08);
uniform vec2 belt_y = vec2(0.352, 0.396);

// 마우스 조명(main.gd _light_set 이 방향광 방향·세기를 바꾼다): 개구리 의상은 어두운 보라라 같은 빛에도
// 명암 차이가 소녀의 절반쯤만 보였다(왼쪽·오른쪽 빛 스냅샷의 밝기 차이 0.031 대 0.057).
// 방향광만 light_gain 배로 대비를 키운다: 밝은 쪽은 더 밝게, 그늘 쪽은 더 어둡게(평균은 그대로).
uniform float light_gain = 2.0;

// 입 벌리기
uniform float mouth = 0.0;             // 0 다문 입 ~ 1 크게 벌린 입
uniform float jaw_deg = 22.0;          // 다 벌렸을 때 아래턱 각도
uniform vec2 jaw_hinge = vec2(4.5, 5.0);   // 경첩 (y, z) cm, frog.gd JAW_HINGE 와 같게
// 아랫입술 끝 둥글리기: 바깥 피부(아래로)에서 입술 위를 넘어 안쪽 아래로 말려 들어가는 반원(반지름 rim_r).
// 피부는 깊이 rim_r 안쪽이 호의 0~45°, 바닥은 입술 끝에서 호 길이만큼이 45~180°(안쪽으로 내려감), 그 뒤 2.5cm 동안
// 원래 바닥으로 돌아간다. UV2.y = 입술 끝에서의 거리(cm). 모서리 점은 양쪽 모두 45° 자리라 서로 붙어 있다.
// (처음엔 90° 모서리만 둥글려서 옆에서 보면 붉은 바닥이 혀처럼 앞으로 넓게 보였다.)
// 입꼬리 쪽(|x| rim_x 밖)은 줄인다(그쪽은 피부가 옆을 봐서 앞뒤 방향 호가 맞지 않음). 벌릴수록 바로 둥글어진다.
uniform float rim_r = 1.2;
uniform bool mouth_debug = false;      // 입 확인: 입천장 파랑, 바닥 빨강, 아래턱 피부 초록(둥글리는 곳 노랑)
uniform vec2 rim_x = vec2(6.0, 10.5);
// 입 안은 어둡고 채도 높게(2026-11-23 사용자 요청). 아랫면 가운데에 앞이 뾰족한 쐐기 모양 혀를 더 어두운 빨강으로 은은하게.
uniform vec3 palate_col : source_color = vec3(0.34, 0.03, 0.08);   // 입천장
uniform vec3 floor_col : source_color = vec3(0.58, 0.08, 0.17);    // 입 바닥
uniform vec3 tongue_col : source_color = vec3(0.44, 0.02, 0.07);   // 쐐기 혀
uniform vec2 tongue_w = vec2(0.6, 5.0);    // 혀 반폭 cm: 앞 끝 ~ 안쪽
uniform float tongue_amt = 0.7;
uniform vec3 throat_col : source_color = vec3(0.09, 0.0, 0.02);    // 목구멍(경첩 쪽)

// 모자 사라지기(2026-11-24): frog.gd 가 CUSTOM0 = (표시, 기본 자세 머리 좌표 cm)를 넣는다. 표시 1 모자, 2 정수리 덮개(yzw = 색).
// hat_off 0 → 1 로 꼭대기부터 아래로 녹아 없어지고(경계는 울퉁불퉁한 반짝이는 띠), 1 → 0 이면 아래부터 다시 생긴다.
// 덮개는 모자 안에 있어서 보통은 가려지지만, 다문 모습이 원래와 똑같게 hat_off 0 이면 아예 그리지 않는다.
uniform float hat_off = 0.0;
uniform vec2 hat_span = vec2(5.0, 39.0);       // 모자 가장 낮은 곳 ~ 꼭대기(기본 자세 머리 높이 cm)
uniform float hat_edge = 1.8;                   // 반짝이는 띠 폭 cm
uniform float hat_noise = 2.2;                  // 경계 울퉁불퉁 cm
uniform vec3 hat_glow : source_color = vec3(1.0, 0.86, 0.45);
uniform vec3 hat_spark : source_color = vec3(1.0, 0.98, 0.85);
uniform bool hat_debug = false;
uniform vec3 scalp_col : source_color = vec3(0.5, 0.65, 0.2);   // frog.gd 가 이마 평균 초록을 넣는다
uniform float scalp_gain = 0.93;                // 덮개 밝기(코 평균 대비)
uniform float scalp_sat = 1.12;                 // 덮개 채도(코 평균 대비)
uniform vec2 scalp_cut = vec2(5.5, 12.0);      // frog.gd SCALP_CUT·SCALP_CUT_Z·EYE_KEEP 와 같게
uniform vec2 scalp_cut_z = vec2(4.0, 12.0);
uniform vec3 scalp_c = vec3(0.0, 5.0, 4.3);    // frog.gd 덮개 바탕 타원체(머리 좌표 cm)
uniform vec3 scalp_r = vec3(13.0, 10.0, 13.6);
uniform float scalp_smooth = 0.85;              // 뒤·옆 이음매 띠에서 법선을 타원체 쪽으로 섞는 정도
uniform float eye_keep = 0.4;                 // 모자 빨강, 덮개 파랑(덮개는 hat_off 0 이어도 보임)

varying vec3 hp;
varying vec4 hc0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	hc0 = CUSTOM0;
	if (COLOR.r < 0.75) {
		mat4 pm = COLOR.r < 0.25 ? book_m : vial_m;
		vec4 bw = pm * (MODEL_MATRIX * vec4(VERTEX, 1.0));
		VERTEX = (inverse(MODEL_MATRIX) * bw).xyz;
		NORMAL = normalize(inverse(mat3(MODEL_MATRIX)) * (mat3(pm) * (mat3(MODEL_MATRIX) * NORMAL)));
	}
	vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0);
	hp = (head_inv * w).xyz * 100.0 * unit_scale;
	if (mouth > 0.001 && UV2.x > 0.0) {
		vec3 hb = hp;
		float arc_len = rim_r * radians(135.0);
		if ((UV.x < -3.5 && UV2.y < arc_len + 2.5) || (UV.x > -3.5 && UV2.y < rim_r)) {
			float wr = (1.0 - smoothstep(rim_x.x, rim_x.y, abs(hp.x))) * min(1.0, mouth * 3.0);
			float e = UV2.y;
			vec2 off;   // (dy, dz)
			if (UV.x < -3.5) {
				float ph = radians(45.0 + 135.0 * min(e, arc_len) / arc_len);
				off = vec2(-rim_r + rim_r * sin(ph), -rim_r + rim_r * cos(ph) + min(e, arc_len));
				off *= 1.0 - smoothstep(0.0, 2.5, e - arc_len);
			} else {
				float ph = radians(45.0 * (1.0 - e / rim_r));
				off = vec2(-rim_r + rim_r * sin(ph) + e, -rim_r + rim_r * cos(ph));
			}
			hb += vec3(0.0, off * wr);
		}
		float a = radians(jaw_deg) * mouth * UV2.x;
		float ca = cos(a);
		float sa = sin(a);
		vec2 d = vec2(hb.y - jaw_hinge.x, hb.z - jaw_hinge.y);
		d = vec2(d.x * ca - d.y * sa, d.x * sa + d.y * ca);   // 앞(+z)이 아래(-y)로
		vec3 h2 = vec3(hb.x, jaw_hinge.x + d.x, jaw_hinge.y + d.y);
		mat4 head_m = inverse(head_inv);
		VERTEX = (inverse(MODEL_MATRIX) * (head_m * vec4(h2 * 0.01 / unit_scale, 1.0))).xyz;
		vec3 n = mat3(head_inv) * (mat3(MODEL_MATRIX) * NORMAL);
		n = vec3(n.x, n.y * ca - n.z * sa, n.y * sa + n.z * ca);
		NORMAL = normalize(inverse(mat3(MODEL_MATRIX)) * (mat3(head_m) * n));
	}
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

float hue_diff(float a, float b) {
	return fract(a - b + 0.5) - 0.5;
}

// 덮개·뒤통수 피부 이음매 띠의 법선을 바탕 타원체 법선 쪽으로 섞는다(머리 좌표 → 뷰). 덮개는 방향마다 가까운 피부 점까지의
// 거리로 맞춰서, 피부 메시는 챙 밑이라 원래 울퉁불퉁해서 뒤통수 아래가 이그러져 보였다(2026-11-27 사용자 지적).
vec3 scalp_normal(vec3 n, vec3 rp, mat4 view) {
	float cut = mix(scalp_cut.x, scalp_cut.y, smoothstep(scalp_cut_z.x, scalp_cut_z.y, rp.z));
	float w = (1.0 - smoothstep(cut + 1.0, cut + 4.0, rp.y)) * (1.0 - smoothstep(4.0, 8.0, rp.z)) * scalp_smooth;
	if (w <= 0.0) return n;
	vec3 g = (rp - scalp_c) / (scalp_r * scalp_r);
	vec3 gv = normalize(mat3(view) * (inverse(mat3(head_inv)) * g));
	return normalize(mix(n, gv, w));
}

float cover(float d) {
	float f = max(fwidth(d), 1e-4);
	return clamp(0.5 - d / f, 0.0, 1.0);
}

void fragment() {
	if (book_hide > 0.5 && COLOR.r < 0.25) discard;
	vec3 c = (texture(albedo_tex, UV) * albedo_col).rgb;
	vec3 glow = vec3(0.0);
	// 같은 코 색을 넣어도 덮개(둥글게 위를 봄)는 코보다 조금 밝고 흐리게 보여서 채도·밝기를 맞춘다(렌더에서 잰 값).
	vec3 bald = rgb2hsv(scalp_col);
	bald = hsv2rgb(vec3(bald.x, clamp(bald.y * scalp_sat, 0.0, 1.0), bald.z * scalp_gain));
	if (hc0.x > 1.5) {
		if (hat_off <= 0.0 && !hat_debug) discard;
		// 자르는 선 아래는 원래 피부가 덮으므로 그리지 않는다. 뒤쪽 아래는 피부(목)가 옷깃 속에 없어 덮개가 타원체대로
		// 옷깃 밖까지 나와서, 옷깃 윗부분을 가려 끊긴 것처럼 보였다(2026-11-24 사용자 지적).
		if (hc0.z < mix(scalp_cut.x, scalp_cut.y, smoothstep(scalp_cut_z.x, scalp_cut_z.y, hc0.w)) - 0.3) discard;
		c = hat_debug ? vec3(0.0, 0.3, 1.0) : bald;
		NORMAL = scalp_normal(NORMAL, hc0.yzw, VIEW_MATRIX);
	} else if (hc0.x < 0.5 && hat_off > 0.0 && UV.x >= 0.0) {
		// 민머리: 자르는 선 위 피부는 눈두덩만 남기고 지운다(덮개가 대신). 선 아래 3cm 와 눈두덩의 초록은 덮개 색으로 이어 준다
		// (챙 밑 그늘이 칠해져 있어서).
		vec3 rp = hc0.yzw;
		float cut = mix(scalp_cut.x, scalp_cut.y, smoothstep(scalp_cut_z.x, scalp_cut_z.y, rp.z));
		float eye_d = length(rp - vec3(eye_c.x * sign(rp.x), eye_c.yz)) - eye_r;
		if (rp.y > cut && (eye_d > eye_keep || rp.y > eye_c.y + eye_r)) discard;
		// 눈알 뒤·위쪽은 초록 눈두덩으로(민머리 그림처럼 뒤에서 보면 초록 혹 두 개)
		vec3 qn = normalize(rp - vec3(eye_c.x * sign(rp.x), eye_c.yz));
		float lidb = (1.0 - smoothstep(0.05, 0.25, dot(qn, normalize(vec3(0.0, -0.15, 1.0))))) * step(eye_d, 0.4);
		if (!FRONT_FACING) lidb = step(eye_d, 0.4);   // 눈알은 뒤가 뚫린 껍데기라 뒤에서 보면 안쪽 흰자가 보였다
		vec3 hv = rgb2hsv(c);
		vec3 ref = rgb2hsv(scalp_col);
		// 입선 위 초록 피부(얼굴·볼·이마) 전체를 덮개와 같은 코 색으로: 텍스처에 칠해진 명암·광택이 덮개와 달라
		// 눈 사이·옆에 경계선이 보였다(2026-11-24 사용자 요청). 콧구멍·입선·눈알은 초록이 아니라 그대로.
		// 뒤·옆(z 가 작은 쪽)은 옷깃까지 내려가며 바꾼다: 선 아래 뒤통수에 챙 그늘·밝은 줄이 칠해져 있어
		// 덮개와의 경계가 들쭉날쭉하게 보였다(2026-11-27 사용자 지적). 얼굴 앞(입·턱)은 그대로 5.2 부터.
		float y_lo = mix(-8.0, 5.2, smoothstep(3.0, 6.5, rp.z));
		float k = smoothstep(y_lo, y_lo + 1.2, rp.y) * smoothstep(0.2, 0.8, eye_d)
			* (1.0 - smoothstep(0.06, 0.12, abs(hv.x - ref.x)));
		k = max(max(k, smoothstep(0.0, 0.15, hc0.x)), lidb) * hat_off;   // 모자와 이어져 있던 삼각형의 남은 쪽(그늘)·눈알 뒤
		c = mix(c, bald, k);
		if (FRONT_FACING) NORMAL = scalp_normal(NORMAL, rp, VIEW_MATRIX) * k + NORMAL * (1.0 - k);
	} else if (hc0.x > 0.5) {
		vec3 rp = hc0.yzw;
		float hh = rp.y + (vnoise(rp * 0.28) - 0.5) * 2.0 * hat_noise + (vnoise(rp * 0.9 + 7.0) - 0.5) * 0.8;
		float lvl = mix(hat_span.y + hat_noise + 1.0, hat_span.x - hat_noise - hat_edge, hat_off);
		if (hh > lvl) discard;
		float band = 1.0 - smoothstep(0.0, hat_edge, lvl - hh);
		band *= step(0.001, hat_off) * step(hat_off, 0.999);
		// 띠 안의 반짝이: 0.7cm 칸마다 한 번씩 깜빡임
		vec3 cell = floor(rp / 0.7);
		float tw = hash3(cell + floor(TIME * 9.0 + hash3(cell) * 9.0));
		float spark = step(0.82, tw) * smoothstep(0.0, 0.6, band);
		if (!FRONT_FACING) c *= 0.6;    // 지워진 위쪽으로 보이는 모자 안쪽은 조금 어둡게
		c = mix(c, hat_glow, band * 0.85);
		glow = hat_glow * band * 1.4 + hat_spark * spark * 2.5;
		if (hat_debug) c = vec3(1.0, 0.0, 0.0);
	}
	// frog.gd 가 덧붙인 것: UV x -2 = 앞 병 뒤 로브 구멍 막는 판(로브 보라),
	// UV x -1 = 병 속을 메우는 공(y = 병 가운데 기준 높이 -1~1): 아래 진보라 → 자홍 → 연보라 → 하늘색(텍스처에서 잰 병 색).
	if (UV.x < -4.5) {
		// 정수리 덮개(UV x -5): 색은 위에서 hc0 로 정함
	} else if (UV.x < -2.5) {
		// 입 안: 입천장(-3)·혀(-4), 경첩 쪽으로 갈수록 목구멍 색
		if (UV.x < -3.5) {
			c = floor_col;
			// 혀는 경첩(UV.y 1)에서 입술 쪽으로 60% 까지(앞 끝 UV.y 0.4, 2026-11-23 사용자 요청)
			float hw = mix(tongue_w.x, tongue_w.y, smoothstep(0.4, 0.9, UV.y));
			float tm = (1.0 - smoothstep(hw - 0.5, hw + 0.5, abs(hp.x))) * smoothstep(0.38, 0.46, UV.y);
			c = mix(c, tongue_col, tm * tongue_amt);
			c = mix(c, throat_col, smoothstep(0.45, 1.0, UV.y));
		} else {
			c = mix(palate_col, throat_col, smoothstep(0.25, 1.0, UV.y));
		}
	} else if (UV.x < -1.5) {
		c = robe_col;
	} else if (UV.x < -0.5) {
		float t = UV.y;
		c = mix(vec3(0.29, 0.12, 0.50), vec3(0.45, 0.14, 0.62), smoothstep(-1.0, -0.5, t));
		c = mix(c, vec3(0.61, 0.24, 0.69), smoothstep(-0.5, -0.15, t));
		c = mix(c, vec3(0.55, 0.42, 0.70), smoothstep(-0.15, 0.1, t));
		c = mix(c, vec3(0.30, 0.55, 0.72), smoothstep(0.1, 0.35, t));
		c = mix(c, vec3(0.22, 0.48, 0.65), smoothstep(0.35, 1.0, t));
	}
	// 든 병(빨강 0.5)의 뒷면, 로브 쪽에 칠해져 있던 그늘(어둡고 갈색(코르크·끈)이 아닌 색)은 병 속 색으로 덮는다.
	if (vial_away > 0.0 && COLOR.r > 0.25 && COLOR.r < 0.75) {
		vec3 hv = rgb2hsv(c);
		bool shade = hv.z < 0.3 && !(hv.x > 0.03 && hv.x < 0.16 && hv.y > 0.3);
		if (!FRONT_FACING || shade) c = mix(c, vial_in, vial_away);
	}
	float away = COLOR.g < 0.25 ? book_away : vial_away;
	if (away > 0.0 && COLOR.r > 0.75 && COLOR.g < 0.75) {
		float yy = 0.30 + COLOR.a * 0.15;
		float bw = smoothstep(belt_y.x - 0.003, belt_y.x + 0.003, yy) * (1.0 - smoothstep(belt_y.y - 0.003, belt_y.y + 0.003, yy));
		c = mix(c, mix(robe_col, belt_col, bw), away);
	}
	// 뒤 병(정점 색 파랑 0, 빨강 1 = 허리에 남는 병)의 흐린 분홍 띠(보라 액체와 위 유리 사이)는 지운다:
	// 위쪽 빈 유리와 같은 하늘색으로(2026-11-23 사용자 요청, 액체는 아래 보라만). 밝기는 그대로.
	if (COLOR.b < 0.5 && COLOR.r > 0.75) {
		vec3 hv = rgb2hsv(c);
		// 색상 0.62 부터(분홍 띠 위 경계의 흰빛 줄도). 채도는 위 유리와 같게 0.73(처음 0.55 는 더 밝아 보였다).
		float pk = smoothstep(0.62, 0.66, hv.x) * (1.0 - smoothstep(0.96, 0.99, hv.x))
			* (1.0 - smoothstep(0.42, 0.52, hv.y)) * smoothstep(0.5, 0.6, hv.z);
		c = mix(c, hsv2rgb(vec3(0.56, 0.73, hv.z)), pk);
		if (bloom_debug) c = mix(c, vec3(1.0, 0.0, 1.0), pk);
	}
	if ((bloom > 0.001 || bloom_debug) && COLOR.b < 0.5) {
		vec3 h = rgb2hsv(c);
		vec3 ht = rgb2hsv(bloom_to);
		// 병 옆 로브(같은 보라, 더 어둡고 흐림)가 물드는 것을 막으려고 밝기·채도 문턱을 높였다(예전 0.22~0.32·0.12~0.22).
		float w = smoothstep(0.30, 0.40, h.z) * smoothstep(0.18, 0.28, h.y);
		// 병 아래 보라·자홍 액체만(색상 약 0.68~0.96). 위쪽 하늘색(빈 유리, 색상 약 0.55)은 그대로(2026-11-23 사용자 요청).
		w *= smoothstep(0.62, 0.68, h.x) * (1.0 - smoothstep(0.96, 0.995, h.x));
		if (bloom_debug) {
			c = mix(c, vec3(0.0, 1.0, 0.0), w * 0.8);
		} else {
			float nh = fract(ht.x + hue_diff(h.x, bloom_from_h) * bloom_spread);
			float ns = clamp(mix(h.y, ht.y, mix(0.85, 0.5, smoothstep(0.1, 0.3, ht.y))), 0.0, 1.0);
			float nv = clamp(h.z * clamp(ht.z / 0.72, 0.15, 1.1), 0.0, 1.0);
			vec3 end = hsv2rgb(vec3(nh, ns, nv));
			c = mix(c, mix(c, end, bloom), w);
		}
	}
	if (back_dark > 0.001 && COLOR.b < 0.5 && COLOR.r > 0.75) {
		vec3 h = rgb2hsv(c);
		// 액체 고르기는 bloom 과 같다(보라·자홍, 로브는 문턱으로 빠짐; 위쪽 하늘색 빈 유리는 그대로).
		float w = smoothstep(0.30, 0.40, h.z) * smoothstep(0.18, 0.28, h.y)
			* smoothstep(0.62, 0.68, h.x) * (1.0 - smoothstep(0.96, 0.995, h.x));
		// 먹물 같은 검정: 밝기를 0.12 배로 낮추고 채도를 줄여 원래 명암(유리 반사)만 희미하게 남긴다.
		vec3 ink = hsv2rgb(vec3(h.x, h.y * 0.35, h.z * 0.12));
		c = mix(c, ink, w * back_dark);
	}
	if (tint > 0.001 || tint_debug) {
		vec3 h = rgb2hsv(c);
		vec3 hf = rgb2hsv(tint_from);
		// 의상(모자·로브) 보라 → 검정. 명도 비율은 남겨 주름이 보이게 한다.
		float w = (1.0 - smoothstep(0.06, 0.09, abs(hue_diff(h.x, hf.x))))
			* smoothstep(0.18, 0.28, h.y) * (1.0 - smoothstep(0.5, 0.6, h.z));
		// 의상의 노란(금) 장식 → gold_to(터키색). 얼굴(주황 입선·눈 흰자)과 유리병(정점 색 파랑 0)은 뺀다.
		// 벨트·신발·코르크 같은 갈색은 명도가 낮아 빠진다.
		bool face = hp.y > face_lo && hp.y < face_hi && hp.z > -6.0 && abs(hp.x) < 17.0;
		float g = (1.0 - smoothstep(gold_w, gold_w + 0.025, abs(hue_diff(h.x, gold_from_h))))
			* smoothstep(0.3, 0.42, h.y) * smoothstep(0.3, 0.42, h.z)
			* (face ? 0.0 : 1.0) * step(0.5, COLOR.b);
		if (tint_debug) {
			c = mix(c, vec3(0.0, 1.0, 0.0), w * 0.8);
			c = mix(c, vec3(1.0, 0.0, 1.0), g * 0.8);
		} else {
			vec3 black = tint_black * (h.z / max(hf.z, 1e-3));
			c = mix(c, black, w * tint);
			vec3 gold = hsv2rgb(vec3(rgb2hsv(gold_to).x, mix(h.y, rgb2hsv(gold_to).y, 0.7), clamp(h.z * gold_gain, 0.0, 1.0)));
			c = mix(c, gold, g * tint);
		}
	}
	vec3 e = vec3(eye_c.x * sign(hp.x), eye_c.yz);
	vec3 q = hp - e;
	float dist = length(q);
	float lids = max(blink, happy);
	if (dist < eye_r + 0.5 && q.z > -eye_r * 0.6) {
		if (debug) c = mix(c, vec3(1.0, 0.0, 0.0), 0.5);
		if (lids > 0.001) {
			float y = q.y / max(dist, 1e-3);
			// 눈꺼풀 끝은 가운데가 조금 더 내려온 호(옆으로 갈수록 위로). 위·아래가 같은 호라 다 감으면 빈틈 없이 만난다.
			float bx = q.x * sign(hp.x) / eye_r;
			float bend = 0.18 * bx * bx;
			float up_t = mix(1.05, seam, lids) + bend * lids;
			float lo_t = mix(-1.05, seam, lids) + bend * lids;
			float du = (up_t - y) * eye_r;
			float dl = (y - lo_t) * eye_r;
			c = mix(c, lid, max(cover(du), cover(dl)));
			float ln = max(cover(abs(du) - line_w), cover(abs(dl) - line_w * 0.7));
			c = mix(c, lid_line, ln * step(dist, eye_r + 0.25));
		}
	}
	if (mouth_debug) {
		if (UV.x < -3.5) c = vec3(1.0, 0.0, 0.0);
		else if (UV.x < -2.5) c = vec3(0.0, 0.2, 1.0);
		else if (UV2.x > 0.0) c = UV2.y < rim_r ? vec3(1.0, 0.9, 0.0) : vec3(0.0, 0.8, 0.2);
	}
	if (UV.x >= 0.0 && hc0.x < 0.5 && abs(hc0.y) > 12.0 && hc0.z > -18.0 && hc0.z < -1.0) {
		vec3 sv = rgb2hsv(c);
		float green = smoothstep(0.12, 0.17, sv.x) * (1.0 - smoothstep(0.36, 0.42, sv.x)) * smoothstep(0.2, 0.3, sv.y);
		c *= mix(1.0, mix(sleeve_dark, 1.0, smoothstep(sleeve_x.x, sleeve_x.y, abs(hc0.y))), green);
	}
	ALBEDO = c;
	EMISSION = glow;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float lambert = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (lambert * light_gain - (light_gain - 1.0) * 0.5) / PI;
}
