shader_type canvas_item;
// FXAA 3A 级后处理抗锯齿:梯度检测 + 方向混合 + 子像素锐度 + 三档质量
// quality: 0=fast(span 4) 1=default(span 6) 2=high(span 8 + 12 点覆盖细化)
// 平滑区域(对比度不足)直接透传,避免梯度纹理被反复模糊(旧版通病)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform int quality : hint_range(0, 2) = 1;
uniform float subpix : hint_range(0.0, 1.0) = 0.75;
uniform bool debug_edges = false;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float fxaa_luma(vec3 c) {
	return dot(c, LUMA);
}

void fragment() {
	vec2 texel = SCREEN_PIXEL_SIZE;
	vec2 uv = UV;
	vec3 rgbM = texture(screen_texture, uv).rgb;
	float lumaM = fxaa_luma(rgbM);
	// 5-tap 十字采样(亮度梯度)
	vec3 rgbNW = texture(screen_texture, uv + vec2(-1.0, -1.0) * texel).rgb;
	vec3 rgbNE = texture(screen_texture, uv + vec2( 1.0, -1.0) * texel).rgb;
	vec3 rgbSW = texture(screen_texture, uv + vec2(-1.0,  1.0) * texel).rgb;
	vec3 rgbSE = texture(screen_texture, uv + vec2( 1.0,  1.0) * texel).rgb;
	float lumaNW = fxaa_luma(rgbNW);
	float lumaNE = fxaa_luma(rgbNE);
	float lumaSW = fxaa_luma(rgbSW);
	float lumaSE = fxaa_luma(rgbSE);
	float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
	float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
	float lumaRange = lumaMax - lumaMin;
	vec3 rgbOut = rgbM;
	// 平滑区域透传(阈值随亮度自适应,暗部更宽容)
	if (lumaRange >= max(0.0312, 0.0625 * lumaMax)) {
		// 边缘方向:由对角亮度差构建梯度
		vec2 dir = vec2(
			-((lumaNW + lumaNE) - (lumaSW + lumaSE)),
			 ((lumaNW + lumaSW) - (lumaNE + lumaSE)));
		// 自适应 reduce 与 span:quality 越高跨度越大、reduce 越精细
		float reduceMul = quality >= 2 ? (1.0 / 16.0) : (quality == 1 ? (1.0 / 8.0) : (1.0 / 5.0));
		float spanMax = quality >= 2 ? 8.0 : (quality == 1 ? 6.0 : 4.0);
		float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * reduceMul), 1.0 / 128.0);
		float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
		dir = clamp(dir * rcpDirMin, vec2(-spanMax), vec2(spanMax)) * texel;
		// 沿边方向 A/B 组混合(外推 vs 内插,取较平滑者)
		vec3 rgbA = 0.5 * (
			texture(screen_texture, uv + dir * (1.0 / 3.0 - 0.5)).rgb +
			texture(screen_texture, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
		vec3 rgbB = rgbA * 0.5 + 0.25 * (
			texture(screen_texture, uv - dir * 0.5).rgb +
			texture(screen_texture, uv + dir * 0.5).rgb);
		float lumaB = fxaa_luma(rgbB);
		rgbOut = (lumaB < lumaMin || lumaB > lumaMax) ? rgbA : rgbB;
		// 高画质:沿方向 12 点覆盖搜索,细化混合权重(官方 quality12 数值化版)
		if (quality >= 2) {
			vec2 dirUnit = normalize(dir);
			float bestP = 0.0;
			float bestN = 0.0;
			bool foundP = false;
			bool foundN = false;
			for (int i = 0; i < 12; i++) {
				float t = 0.5 + float(i);
				if (!foundP) {
					vec3 rgbP = texture(screen_texture, uv + dirUnit * t * texel).rgb;
					float lumaP = fxaa_luma(rgbP);
					if (lumaP < lumaMin || lumaP > lumaMax) {
						foundP = true;
						bestP = t;
					}
				}
				if (!foundN) {
					vec3 rgbN = texture(screen_texture, uv - dirUnit * t * texel).rgb;
					float lumaN = fxaa_luma(rgbN);
					if (lumaN < lumaMin || lumaN > lumaMax) {
						foundN = true;
						bestN = t;
					}
				}
			}
			float covP = foundP ? min(bestP, spanMax) : spanMax;
			float covN = foundN ? min(bestN, spanMax) : spanMax;
			float total = covP + covN;
			if (total > 1.0) {
				rgbOut = mix(rgbM, rgbA, 1.0 / total);
			}
		}
		// 子像素锐度:中心亮度与邻域均值偏差大且边缘极细时,向混合色收敛(抗闪烁)
		float lumaAvg = 0.25 * (lumaNW + lumaNE + lumaSW + lumaSE);
		float subpixAmt = clamp(abs(lumaM - lumaAvg) / (lumaRange + 1e-5) * subpix * 1.5, 0.0, 1.0);
		rgbOut = mix(rgbM, rgbOut, 1.0 - subpixAmt * 0.5);
	}
	COLOR = vec4(rgbOut, 1.0);
	if (debug_edges) {
		COLOR = vec4(vec3(lumaRange * 16.0), 1.0);
	}
}
