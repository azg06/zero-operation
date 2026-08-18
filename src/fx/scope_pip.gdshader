shader_type canvas_item;
// 高倍率狙击镜 PIP(Picture-in-Picture)镜片着色器。
// 镜内世界来自独立 OpticScope 相机渲染的 SubViewport 纹理,镜外保持主相机正常视野。
// 该层绘制于 CanvasLayer 3(主世界之上、视角模型/后处理之下),由 OpticScopeSystem
// 每帧注入镜片在根视口逻辑坐标系中的圆心/半径/过渡参数;不使用全屏镜罩贴图,
// 也不放大主相机。UV 归一化方式可自动适配任意窗口/内容缩放。

uniform sampler2D scope_tex : filter_linear;
uniform vec2 center_uv = vec2(0.5, 0.5);        // 镜片中心(根视口 UV,随枪械运动)
uniform vec2 screen_size = vec2(1920.0, 1080.0); // 根视口逻辑分辨率(像素)
uniform float radius_px = 260.0;                 // 镜片投影半径(逻辑像素)
uniform float radius_scale = 1.0;                // ADS 过渡:镜片半径缩放
uniform float alpha = 0.0;                       // ADS 过渡:整体透明度
uniform float edge_soft_px = 2.5;                // 镜片边缘柔化宽度(逻辑像素)
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.32;
uniform float edge_shade : hint_range(0.0, 1.0) = 0.30;
uniform float distortion : hint_range(0.0, 0.08) = 0.018;
uniform float reflection_strength : hint_range(0.0, 0.3) = 0.055;
uniform float time = 0.0;

void fragment() {
	// UV 是 CanvasItem 局部归一化坐标;乘以逻辑分辨率后,半径/柔边/暗角
	// 都稳定不随窗口物理像素变化。
	vec2 d = (UV - center_uv) * screen_size;
	float eff_r = max(radius_px * radius_scale, 1.0);
	float nr = length(d) / eff_r;

	if (alpha > 0.001) {
		float edge = edge_soft_px / eff_r;
		// 镜内不透明、镜外透明;镜筒实体由 Gun 在 ADS 时隐藏。
		float mask = 1.0 - smoothstep(1.0 - edge, 1.0 + edge, nr);

		// 轻量桶形光学失真(只作用于镜内采样,强度很低)
		vec2 q = d / eff_r;
		vec2 suv = vec2(0.5) + q * (1.0 + distortion * dot(q, q)) * 0.5;
		suv = clamp(suv, vec2(0.0), vec2(1.0));
		vec3 col = texture(scope_tex, suv).rgb;

		// 镜内边缘轻微暗角(非全屏暗角)
		float vig = smoothstep(0.42, 1.0, nr) * mask;
		col *= 1.0 - vignette_strength * vig;

		// 镜片边缘一圈压暗 + 极淡冷色玻璃反射(不遮挡准星)
		col *= 1.0 - edge_shade * smoothstep(0.86, 1.0, nr) * mask;
		float glint = pow(max(0.0, 1.0 - length(q - vec2(-0.42, -0.52)) * 2.15), 2.0);
		col += vec3(0.34, 0.42, 0.52) * glint * reflection_strength * mask;

		// 镜外完全透明:不遮挡主相机正常视野;镜筒实体由 Gun 在 ADS 时隐藏,
		// 因此整个镜外区域都能看到正常世界,只保留镜片圆形边界与镜内 PIP 画面。
		vec3 final_rgb = col;
		float out_alpha = alpha * mask;
		COLOR = vec4(final_rgb, out_alpha);
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	}
}
