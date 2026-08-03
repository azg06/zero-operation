shader_type canvas_item;
// FXAA 测试着色器:0=原样透传(校准管线) 1=轻量 FXAA(quality9) 2=边缘可视化
// 注意:Godot 4 fragment 处理器不允许 return,全部用 if/else 结构
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform int mode : hint_range(0, 2) = 1;
uniform float strength : hint_range(0.5, 2.0) = 1.0;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float fxaa_luma(vec3 c) {
	return dot(c, LUMA);
}

void fragment() {
	vec2 texel = SCREEN_PIXEL_SIZE;
	vec2 uv = UV;
	vec3 rgbM = texture(screen_texture, uv).rgb;
	vec3 outCol = rgbM;
	if (mode != 0) {
		float lumaM = fxaa_luma(rgbM);
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
		if (mode == 2) {
			outCol = vec3(lumaRange * 18.0);
		} else if (lumaRange >= max(0.0312, 0.0625 * lumaMax)) {
			vec2 dir = vec2(
				-((lumaNW + lumaNE) - (lumaSW + lumaSE)),
				 ((lumaNW + lumaSW) - (lumaNE + lumaSE)));
			float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (1.0 / 32.0), 1.0 / 128.0);
			float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
			dir = clamp(dir * rcpDirMin, vec2(-6.0), vec2(6.0)) * texel;
			vec3 rgbA = 0.5 * (
				texture(screen_texture, uv + dir * (1.0 / 3.0 - 0.5)).rgb +
				texture(screen_texture, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
			vec3 rgbB = rgbA * 0.5 + 0.25 * (
				texture(screen_texture, uv - dir * 0.5).rgb +
				texture(screen_texture, uv + dir * 0.5).rgb);
			float lumaB = fxaa_luma(rgbB);
			vec3 rgbOut = (lumaB < lumaMin || lumaB > lumaMax) ? rgbA : rgbB;
			outCol = mix(rgbM, rgbOut, clamp(strength, 0.0, 1.0));
		}
	}
	COLOR = vec4(outCol, 1.0);
}
