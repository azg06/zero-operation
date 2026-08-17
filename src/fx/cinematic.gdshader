// 电影级后期处理着色器(3A 画质增强)
// 组合:微对比度 / 柔和泛光 / 胶片颗粒 / 暗角 / 阴影提升
// 挂载:全屏 ColorRect(CanvasLayer layer 4.5,3D 之上 HUD 之下),设置菜单可开关
// [FIX] 色差(Chromatic Aberration)已移除:其 R/B 通道 ± 偏移采样会在物体边缘
// 产生"一红一蓝"彩色光带,属人为伪影而非真实渲染效果,永久禁用。
shader_type canvas_item;
// 屏幕纹理必须显式声明为 hint_screen_texture(canvas_item 无内置 screen_texture 标识符)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

uniform float contrast : hint_range(0.0, 1.5) = 0.22;      // 微对比度强度(0=关)
uniform float saturation : hint_range(0.0, 1.5) = 1.04;    // 饱和度
uniform float bloom_strength : hint_range(0.0, 1.0) = 0.1;  // 柔和泛光强度
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.85; // 泛光亮度阈值
uniform float grain : hint_range(0.0, 0.2) = 0.02;         // 胶片颗粒
uniform float grain_size : hint_range(1.0, 4.0) = 1.8;     // 颗粒粒度
uniform float vignette : hint_range(0.0, 1.0) = 0.2;       // 暗角强度
uniform float shadow_lift : hint_range(0.0, 0.2) = 0.012;  // 阴影提升(去死黑,防过亮)
uniform float highlight_roll : hint_range(0.0, 1.0) = 0.05; // 高光柔化

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / SCREEN_PIXEL_SIZE;

	// ---- 全通道统一采样(无色差:禁止任何 R/G/B 通道独立偏移采样) ----
	vec3 col = texture(screen_texture, uv).rgb;

	// ---- 亮度/饱和度 ----
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);

	// ---- 柔和泛光(双环采样近似高斯,极低开销) ----
	if (bloom_strength > 0.0) {
		float bloom = 0.0;
		float s1 = max(dot(texture(screen_texture, uv + vec2(-1.0, -1.0) * 1.2 / px).rgb, vec3(0.299, 0.587, 0.114)) - bloom_threshold, 0.0);
		float s2 = max(dot(texture(screen_texture, uv + vec2(1.0, -1.0) * 1.2 / px).rgb, vec3(0.299, 0.587, 0.114)) - bloom_threshold, 0.0);
		float s3 = max(dot(texture(screen_texture, uv + vec2(-1.0, 1.0) * 1.2 / px).rgb, vec3(0.299, 0.587, 0.114)) - bloom_threshold, 0.0);
		float s4 = max(dot(texture(screen_texture, uv + vec2(1.0, 1.0) * 1.2 / px).rgb, vec3(0.299, 0.587, 0.114)) - bloom_threshold, 0.0);
		float s5 = max(dot(texture(screen_texture, uv + vec2(-2.0, 0.0) / px).rgb, vec3(0.299, 0.587, 0.114)) - bloom_threshold, 0.0);
		float s6 = max(dot(texture(screen_texture, uv + vec2(2.0, 0.0) / px).rgb, vec3(0.299, 0.587, 0.114)) - bloom_threshold, 0.0);
		float s7 = max(dot(texture(screen_texture, uv + vec2(0.0, -2.0) / px).rgb, vec3(0.299, 0.587, 0.114)) - bloom_threshold, 0.0);
		float s8 = max(dot(texture(screen_texture, uv + vec2(0.0, 2.0) / px).rgb, vec3(0.299, 0.587, 0.114)) - bloom_threshold, 0.0);
		bloom = (s1 + s2 + s3 + s4 + s5 + s6 + s7 + s8) / 8.0;
		col += vec3(bloom) * bloom_strength * 1.6;
	}

	// ---- 微对比度(unsharp:原图 + 边缘差) ----
	if (contrast > 0.0) {
		vec3 blur = texture(screen_texture, uv + vec2(-1.0, 0.0) / px).rgb
			+ texture(screen_texture, uv + vec2(1.0, 0.0) / px).rgb
			+ texture(screen_texture, uv + vec2(0.0, -1.0) / px).rgb
			+ texture(screen_texture, uv + vec2(0.0, 1.0) / px).rgb;
		blur /= 4.0;
		col += (col - blur) * contrast * 1.4;
	}

	// ---- 阴影提升 + 高光压缩(filmic 轻曲线;pow>1 压缩亮部,雪地防过曝) ----
	col = pow(col, vec3(1.0 + highlight_roll * 0.5));
	col = max(col - shadow_lift * 0.15, 0.0) / (1.0 - shadow_lift * 0.3);
	col += vec3(shadow_lift * 0.35);

	// ---- 暗角 ----
	vec2 ndc = uv * 2.0 - 1.0;
	float v = smoothstep(1.25, 0.35, dot(ndc, ndc));
	col *= mix(1.0, v, vignette);

	// ---- 胶片颗粒(时间性) ----
	if (grain > 0.0) {
		float n = hash12(uv * px / grain_size + vec2(TIME * 137.0, TIME * 61.0));
		col += (n - 0.5) * grain;
	}

	col = clamp(col, 0.0, 1.0);
	COLOR = vec4(col, 1.0);
}
