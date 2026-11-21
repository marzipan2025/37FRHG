// 개구리 재질 + 눈꺼풀(깜빡임).
// 개구리 눈은 머리 위로 튀어나온 공이라, 37RHHG 처럼 평면에 덧그리지 않고
// 눈알 공 위에 위·아래 눈꺼풀을 칠한다. 법선은 눈알 그대로라 둥근 음영이 남는다.
// 좌표: 머리 뼈 원점, 축은 기본 자세의 메시 축(x = 캐릭터 왼쪽, y = 위, z = 앞), 단위 cm.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform mat4 head_inv;                 // 월드 → 머리 좌표(m)

uniform float blink = 0.0;             // 0 뜬 눈 ~ 1 감은 눈
uniform vec3 eye_c = vec3(8.2, 10.7, 11.0);   // 왼쪽 눈알 중심(오른쪽은 x 반대). measure.gd 로 구 맞춤.
uniform float eye_r = 3.7;
uniform float seam = -0.15;            // 다 감았을 때 위·아래 눈꺼풀이 만나는 높이(반지름 단위)
uniform vec3 lid : source_color = vec3(0.45, 0.55, 0.14);       // 눈 둘레 초록(텍스처에서 잰 값)
uniform vec3 lid_line : source_color = vec3(0.17, 0.24, 0.05);  // 눈꺼풀 끝 선
uniform float line_w = 0.28;           // cm
uniform bool debug = false;            // 눈알 판정 자리를 빨강으로

// 입 벌리기: 아래턱을 정점 셰이더에서 실제로 돌려 내린다(리깅에 턱 뼈가 없음).
// 텍스처의 주황 입선(머리 좌표 y≈4.6+0.007x², x ±12 까지, 입꼬리는 머리 옆 z≈8.5 — measure.gd)보다
// 아래 점이 아래턱이다. 입꼬리 뒤 경첩(가로축)을 축으로 앞이 내려가게 돌려서, 옆에서 보면 입선(가로)과
// 내려간 턱 사이가 ㄱ자로 벌어진다. 위·아래 턱을 잇던 면은 늘어나 입 안이 되고,
// 늘어난 정도(jaw 보간값)로 윗면(입천장)·목구멍·아랫면(혀)을 나눠 칠한다.
uniform float mouth = 0.0;             // 0 다문 입 ~ 1 크게 벌린 입
uniform float mouth_y = 4.6;           // 입선 높이(가운데)
uniform float mouth_rise = 0.007;      // 옆으로 갈수록 올라가는 정도(y += rise·x²)
uniform float jaw_deg = 34.0;          // 다 벌렸을 때 턱 각도
uniform vec2 hinge = vec2(4.8, 7.0);   // 경첩 (y, z) cm
uniform float jaw_band = 1.2;          // 입선 아래 이 폭(cm)이 늘어나 입 안이 된다
uniform vec2 jaw_fade_y = vec2(-3.0, -1.0);   // 이 높이 아래(옷깃)는 따라가지 않음
uniform vec3 mouth_in : source_color = vec3(0.22, 0.04, 0.06);      // 목구멍
uniform vec3 roof_col : source_color = vec3(0.50, 0.13, 0.17);      // 입천장
uniform vec3 tongue : source_color = vec3(0.93, 0.48, 0.50);       // 혀(아랫면)
uniform vec3 lip : source_color = vec3(0.84, 0.50, 0.16);          // 아랫입술 주황

// 의상(모자·로브) 보라 색 바꾸기(37RHHG 머리카락 tint 자리). 0 = 원래 보라, 1 = tint_to.
// 색상(hue)을 돌려 음영은 그대로 두고, 보이는 밝기는 처음과 끝 사이로 곧게 잇는다.
// 고르는 색(텍스처, measure.gd): 의상은 색상 0.68~0.80·명도 0.5 이하. 물약 병은 같은 보라~분홍이지만 명도 0.6 이상이라 빠진다.
uniform float tint = 0.0;
uniform vec3 tint_from : source_color = vec3(0.24, 0.17, 0.42);   // 의상 보라(색상 0.73)
uniform vec3 tint_to : source_color = vec3(0.86, 0.30, 0.62);     // 핑크
uniform bool tint_debug = false;                                  // 바뀌는 곳을 초록으로

// 옆구리 유리병 물약 색 바꾸기(37RHHG 꽃 가운데 bloom 자리). 0 = 원래 하늘색~보라~분홍, 1 = potion_to 계열.
// 병 자리는 정점 색 파랑 0 으로 표시돼 온다(main.gd POTION_MIN~MAX). 그 안에서 밝은 색(명도 0.4 이상)만 고른다:
// 같은 자리에 걸친 로브 보라는 명도 0.4 아래라 빠진다. 원래 색상 차이는 potion_spread 만큼 남겨 그라데이션을 살린다.
uniform float potion = 0.0;
uniform float potion_from_h = 0.72;   // 원래 그라데이션 가운데 색상(하늘 0.56 ~ 분홍 0.84)
uniform vec3 potion_to : source_color = vec3(0.98, 0.80, 0.16);   // 노랑
uniform float potion_spread = 0.12;
uniform bool potion_debug = false;

varying vec3 hp;      // 머리 좌표(턱 돌리기 전)
varying float jaw;    // (입선 - y)/jaw_band. 자르지 않아서 보간하면 입선과 나란한 경계가 된다.
                      // 0 위가 윗입술, 0~1 이 늘어나 입 안이 되는 띠, 1 아래는 아래턱 피부
varying float jaw_w;  // 턱이 움직이는 자리(입꼬리 앞, 옷깃 위)

void vertex() {
	vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 h = (head_inv * w).xyz * 100.0;
	hp = h;
	float line = mouth_y + mouth_rise * h.x * h.x;
	jaw = (line - h.y) / jaw_band;
	vec4 t = textureLod(albedo_tex, UV, 0.0);
	// 피부(초록·연두)만 움직인다. 옷깃의 보라·주황 테두리가 턱을 따라 찢어지지 않게.
	// 입선 근처(y>0)는 주황 입선도 아래턱이라 색을 가리지 않는다.
	float skin = max(step(0.0, h.y), step(t.b, t.g) * step(t.r * 0.9, t.g));
	jaw_w = smoothstep(jaw_fade_y.x, jaw_fade_y.y, h.y) * smoothstep(hinge.y - 2.0, hinge.y + 1.0, h.z)
		* skin * step(abs(h.x), 16.0) * step(h.y, line + 3.0);
	float wgt = clamp(jaw, 0.0, 1.0) * jaw_w;
	if (mouth > 0.001 && wgt > 0.0) {
		float a = radians(jaw_deg) * mouth * wgt;
		vec2 d = vec2(h.y - hinge.x, h.z - hinge.y);
		d = vec2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));
		vec3 h2 = vec3(h.x, hinge.x + d.x, hinge.y + d.y);
		mat4 head_m = inverse(head_inv);
		VERTEX = (inverse(MODEL_MATRIX) * (head_m * vec4(h2 * 0.01, 1.0))).xyz;
		vec3 n = mat3(head_inv) * (mat3(MODEL_MATRIX) * NORMAL);
		n = vec3(n.x, n.y * cos(a) - n.z * sin(a), n.y * sin(a) + n.z * cos(a));
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

float cover(float d) {
	float f = max(fwidth(d), 1e-4);
	return clamp(0.5 - d / f, 0.0, 1.0);
}

void fragment() {
	vec3 c = (texture(albedo_tex, UV) * albedo_col).rgb;
	if ((potion > 0.001 || potion_debug) && COLOR.b < 0.5) {
		vec3 h = rgb2hsv(c);
		vec3 ht = rgb2hsv(potion_to);
		float w = smoothstep(0.22, 0.32, h.z) * smoothstep(0.12, 0.22, h.y);
		if (potion_debug) {
			c = mix(c, vec3(0.0, 1.0, 0.0), w * 0.8);
		} else {
			float nh = fract(ht.x + hue_diff(h.x, potion_from_h) * potion_spread);
			vec3 end = hsv2rgb(vec3(nh, clamp(mix(h.y, ht.y, 0.5), 0.0, 1.0), clamp(h.z * 1.1, 0.0, 1.0)));
			c = mix(c, mix(c, end, potion), w);
		}
	}
	if (tint > 0.001 || tint_debug) {
		vec3 h = rgb2hsv(c);
		vec3 hf = rgb2hsv(tint_from);
		vec3 ht = rgb2hsv(tint_to);
		float w = (1.0 - smoothstep(0.06, 0.09, abs(hue_diff(h.x, hf.x))))
			* smoothstep(0.18, 0.28, h.y) * (1.0 - smoothstep(0.5, 0.6, h.z));
		if (tint_debug) {
			c = mix(c, vec3(0.0, 1.0, 0.0), w * 0.8);
		} else {
			float dh = hue_diff(ht.x, hf.x);
			vec3 end = hsv2rgb(vec3(fract(h.x + dh), clamp(ht.y + (h.y - hf.y) * 0.5, 0.0, 1.0), h.z * ht.z / hf.z));
			vec3 oc = hsv2rgb(vec3(fract(h.x + dh * tint), mix(h.y, clamp(ht.y + (h.y - hf.y) * 0.5, 0.0, 1.0), tint), h.z * mix(1.0, ht.z / hf.z, tint)));
			vec3 lw = vec3(0.299, 0.587, 0.114);
			float want = mix(dot(c, lw), dot(end, lw), tint);
			oc *= want / max(dot(oc, lw), 1e-4);
			float top = max(oc.r, max(oc.g, oc.b));
			if (top > 1.0) oc = mix(vec3(want), oc, (1.0 - want) / max(top - want, 1e-4));
			c = mix(c, oc, w);
		}
	}
	vec3 e = vec3(eye_c.x * sign(hp.x), eye_c.yz);
	vec3 q = hp - e;
	float dist = length(q);
	// 눈알 표면 근처(둘레 피부는 어차피 초록이라 조금 넓게 잡아도 티 나지 않음).
	if (dist < eye_r + 0.5 && q.z > -eye_r * 0.6) {
		if (debug) c = mix(c, vec3(1.0, 0.0, 0.0), 0.5);
		if (blink > 0.001) {
			float y = q.y / max(dist, 1e-3);
			// 눈꺼풀 끝은 가운데가 조금 더 내려온 호(옆으로 갈수록 위로).
			float bend = 0.18 * (q.x * sign(hp.x) / eye_r) * (q.x * sign(hp.x) / eye_r);
			float up_t = mix(1.05, seam, blink) + bend * blink;
			float lo_t = mix(-1.05, seam, blink) + bend * blink;  // 같은 호라서 다 감으면 빈틈 없이 만남
			// 거리(cm)로 바꿔 경계를 부드럽게: 위 눈꺼풀은 y > up_t, 아래는 y < lo_t.
			float du = (up_t - y) * eye_r;
			float dl = (y - lo_t) * eye_r;
			float m = max(cover(du), cover(dl));
			c = mix(c, lid, m);
			float ln = max(cover(abs(du) - line_w), cover(abs(dl) - line_w * 0.7));
			c = mix(c, lid_line, ln * step(dist, eye_r + 0.25));
		}
	}
	// 입 안: 입선 아래 jaw_band 띠가 늘어난 자리. 윗면(입천장)·목구멍·아랫면(혀), 아래 끝은 주황 아랫입술.
	if (mouth > 0.001 && jaw > 0.0 && jaw < 1.0 && jaw_w > 0.3) {
		vec3 roof = roof_col * mix(1.0, 0.7, smoothstep(0.0, 0.45, jaw));
		vec3 fl = tongue * mix(0.85, 1.0, smoothstep(0.55, 0.9, jaw));
		vec3 inside = mix(roof, fl, cover(0.5 - jaw));
		inside = mix(inside, mouth_in, cover(abs(jaw - 0.5) - 0.06));
		inside = mix(inside, lip, cover(0.93 - jaw));
		c = mix(c, inside, smoothstep(0.0, 0.3, mouth) * cover(-jaw) * cover(jaw - 1.0));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
