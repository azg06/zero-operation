class_name ImgDraw
## 图像绘制助手(对应 map.js 中的 Canvas 2D 绘制)

## 半透明矩形(混合填充)
static func alpha_rect(img: Image, x: float, y: float, w: float, h: float, color: Color) -> void:
	if w <= 0 or h <= 0:
		return
	var block := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	block.fill(color)
	block.resize(int(w), int(h), Image.INTERPOLATE_NEAREST)
	img.blend_rect(block, Rect2i(0, 0, int(w), int(h)), Vector2i(int(x), int(y)))


## 缩放贴印(缩放 src 后混合到目标区域)
static func stamp(img: Image, src: Image, x: int, y: int, w: int, h: int) -> void:
	var tmp := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	tmp.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i.ZERO)
	tmp.resize(w, h, Image.INTERPOLATE_BILINEAR)
	img.blend_rect(tmp, Rect2i(0, 0, w, h), Vector2i(x, y))


static var _circle_cache: Dictionary = {}


## 半透明圆(基于缓存圆贴图)
static func alpha_circle(img: Image, cx: float, cy: float, r: float, color: Color) -> void:
	var key := str(color.to_html())
	var circle: Image = _circle_cache.get(key)
	if circle == null:
		circle = Image.create(128, 128, false, Image.FORMAT_RGBA8)
		circle.fill(Color(0, 0, 0, 0))
		for py in 128:
			for px in 128:
				var dx := px - 63.5
				var dy := py - 63.5
				if dx * dx + dy * dy <= 63.5 * 63.5:
					circle.set_pixel(px, py, color)
		_circle_cache[key] = circle
	stamp(img, circle, int(cx - r), int(cy - r), int(r * 2), int(r * 2))


static var _gradient_cache: Dictionary = {}


## 径向渐变圆(战痕/雪斑)
static func gradient_circle(img: Image, cx: float, cy: float, r: float, stops: Array) -> void:
	var key := ""
	for s in stops:
		key += str(s[0]) + s[1].to_html()
	var grad: Image = _gradient_cache.get(key)
	if grad == null:
		grad = Image.create(128, 128, false, Image.FORMAT_RGBA8)
		grad.fill(Color(0, 0, 0, 0))
		for py in 128:
			for px in 128:
				var dx := px - 63.5
				var dy := py - 63.5
				var d := sqrt(dx * dx + dy * dy) / 63.5
				if d <= 1.0:
					var col: Color = stops[stops.size() - 1][1]
					for i in stops.size() - 1:
						var t0: float = stops[i][0]
						var t1: float = stops[i + 1][0]
						if d >= t0 and d <= t1:
							var f := 0.0 if t1 - t0 < 1e-6 else (d - t0) / (t1 - t0)
							col = (stops[i][1] as Color).lerp(stops[i + 1][1], f)
							break
					grad.set_pixel(px, py, col)
		_gradient_cache[key] = grad
	stamp(img, grad, int(cx - r), int(cy - r), int(r * 2), int(r * 2))


## 单像素混合
static func blend_px(img: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var dst := img.get_pixel(x, y)
	var a := color.a
	img.set_pixel(x, y, Color(
		dst.r * (1 - a) + color.r * a,
		dst.g * (1 - a) + color.g * a,
		dst.b * (1 - a) + color.b * a,
		minf(1.0, dst.a + a)))


## 粗线(沿线段逐点混合,裂纹等用)
static func thick_line(img: Image, x0: float, y0: float, x1: float, y1: float, w: float, color: Color) -> void:
	var dx := x1 - x0
	var dy := y1 - y0
	var thick_len := sqrt(dx * dx + dy * dy)
	if thick_len < 0.001:
		return
	var steps := int(thick_len)
	var hw := w * 0.5
	for i in steps:
		var t := float(i) / steps
		var px := x0 + dx * t
		var py := y0 + dy * t
		for oy in range(-int(hw), int(hw) + 1):
			for ox in range(-int(hw), int(hw) + 1):
				if ox * ox + oy * oy <= hw * hw:
					blend_px(img, int(px) + ox, int(py) + oy, color)


## 噪点
static func noise_speckle(img: Image, n: int, alpha: float) -> void:
	var s := img.get_width()
	for i in n:
		var white := randf() > 0.5
		blend_px(img, randi() % s, randi() % s,
			Color(1, 1, 1, randf() * alpha) if white else Color(0, 0, 0, randf() * alpha))


## 照片平铺(对应 tileDraw)
static func tile_draw(img: Image, photo: Image, tiles: int) -> void:
	var s := img.get_width()
	var ts := int(s / float(tiles))
	var scaled := Image.create(photo.get_width(), photo.get_height(), false, Image.FORMAT_RGBA8)
	scaled.blit_rect(photo, Rect2i(0, 0, photo.get_width(), photo.get_height()), Vector2i.ZERO)
	scaled.resize(ts, ts, Image.INTERPOLATE_BILINEAR)
	for ty in tiles:
		for tx in tiles:
			img.blend_rect(scaled, Rect2i(0, 0, ts, ts), Vector2i(tx * ts, ty * ts))


## 全局透明度覆盖(纯色以 alpha 混合整幅)
static func overlay(img: Image, color: Color) -> void:
	var block := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	block.fill(color)
	block.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_NEAREST)
	img.blend_rect(block, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)


static func to_texture(img: Image) -> ImageTexture:
	var tex := ImageTexture.new()
	tex.set_image(img)  # set_image 自动生成 mipmap,并设置 linear 过滤(Godot 4.7)
	return tex
