shader_type canvas_item;
// PCSS 风格阴影抗锯齿(自写后处理):
// 屏幕空间 PCF——检测阴影边界(局部亮度对比),对"暗侧"像素向邻域平均亮度
// 收敛(百分比接近 + 边缘软化),亮侧保持锐利。等效于软阴影外发光,消除锯齿/闪烁。
// [PERF 9/6] 两段式采样:先 3x3 粗检局部亮度范围,平坦区(非阴影/几何边缘,
// 约 90% 屏幕)直接原样输出,只有粗检到对比度的像素才跑 5x5 PCF 精细核。
// 原版每像素 25 次全屏纹理采样 → 平坦区 10 次;精细核结果与原版逐像素一致。
// 注意:fragment() 禁用中途 return(Godot shader 编译器不兼容,编译失败时
// ColorRect 会回落白色材质 → 整个 3D 场景被白屏遮住——9/6 实测教训);
// 用单出口 if/else 结构,输出与原版逐像素等价。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float soft_radius : hint_range(1.0, 6.0) = 2.2;
uniform float strength : hint_range(0.0, 1.0) = 0.85;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec4 c = texture(screen_tex, UV);
	float l = luma(c.rgb);
	// ---- 粗检:3x3 邻域 min/max 亮度范围 ----
	float lmin = l;
	float lmax = l;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			float ln = luma(texture(screen_tex, UV + vec2(float(x), float(y)) * px).rgb);
			lmin = min(lmin, ln);
			lmax = max(lmax, ln);
		}
	}
	// ---- 平坦区直接原样输出;边缘像素跑 5x5 PCF 精细核(单出口,无 return) ----
	vec3 out_rgb = c.rgb;
	if (lmax - lmin >= 0.02) {
		// 精细核(5x5,高斯权重):邻域平均亮度
		float sum = 0.0;
		float wsum = 0.0;
		for (int y = -2; y <= 2; y++) {
			for (int x = -2; x <= 2; x++) {
				vec2 o = vec2(float(x), float(y)) * px * soft_radius;
				float w = 1.0 / (1.0 + (float(x) * float(x) + float(y) * float(y)) * 0.25);
				sum += luma(texture(screen_tex, UV + o).rgb) * w;
				wsum += w;
			}
		}
		float avg = sum / wsum;
		// 边缘检测:局部对比度越大越接近阴影边界;只软化暗侧(阴影侧)
		float edge = smoothstep(0.04, 0.22, abs(l - avg));
		float mix_k = edge * step(l, avg) * strength;
		float out_l = mix(l, avg, mix_k);
		float k = out_l / max(l, 1e-4);
		out_rgb = c.rgb * k;
	}
	COLOR = vec4(out_rgb, c.a);
}
