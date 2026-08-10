shader_type canvas_item;
// PCSS 风格阴影抗锯齿(自写后处理):
// 屏幕空间 PCF——检测阴影边界(局部亮度对比),对"暗侧"像素向邻域平均亮度
// 收敛(百分比接近 + 边缘软化),亮侧保持锐利。等效于软阴影外发光,消除锯齿/闪烁。

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
	// PCF 核(5x5,高斯权重):邻域平均亮度
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
	// 边缘检测:局部对比度越大越接近阴影边界
	float edge = smoothstep(0.04, 0.22, abs(l - avg));
	// 只软化暗侧(阴影侧):暗像素向平均收敛;亮侧保持锐利
	float mix_k = edge * step(l, avg) * strength;
	float out_l = mix(l, avg, mix_k);
	float k = out_l / max(l, 1e-4);
	COLOR = vec4(c.rgb * k, c.a);
}
