extends Node
## 音频系统(对应 audio.js;音效为离线渲染的 WAV,与原 Web Audio 合成算法一致)
## 3A 升级:音量分层总线(Master/Music/SFX/Ambience/UI)+ 武器音效随机化
## + 地形脚步 + 低血量心跳 + 压制模糊音 + 远距离战场枪声

## 总线分层
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENCE := "Ambience"
const BUS_UI := "UI"
## 脚步独立总线(挂低通滤波):step_concrete 等采样为高频噪声合成(过零率≈12kHz),
## 直通 SFX 总线时表现为"滋滋/嘶嘶"声,低通后保留脚步声主频、去掉噪声尾巴
const BUS_STEPS := "Steps"

## 地图 → 脚步材质映射
const STEP_TERRAIN := {
	"city": "concrete", "desert": "sand", "snow": "snow",
	"bt_jungle": "grass", "bt_harbor": "concrete", "bt_peak": "snow",
}

var _cache: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _step_players: Array[AudioStreamPlayer] = []  # 脚步专用小池:不与枪声/爆炸争抢共享 2D 池(避免互相截断爆音)
var _played_3d: Array[bool] = []  # 曾播放标记:替换最远声源时跳过从未播放的闲置池成员
var _p2d := 0
var _step_i := 0
var _engine_player: AudioStreamPlayer = null
var _wind_player: AudioStreamPlayer = null
var _ambient_on := false
var _rumble_t := 0.0
var _distant_t := 0.0
var _hb_t := 0.0
var _sup_player: AudioStreamPlayer = null


func _ready() -> void:
	_setup_buses()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_players_2d.append(p)
	for i in 2:
		var ps := AudioStreamPlayer.new()
		ps.bus = BUS_STEPS
		add_child(ps)
		_step_players.append(ps)
	for i in 40:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = BUS_SFX
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_players_3d.append(p3)
		_played_3d.append(false)
	apply_volumes()


## 从 G.settings 恢复各总线音量(Master + 四条分层)
func apply_volumes() -> void:
	set_volume(G.settings.volume)
	set_bus_volume(BUS_MUSIC, G.audio_setting("music_vol", 1.0))
	set_bus_volume(BUS_SFX, G.audio_setting("sfx_vol", 1.0))
	# 脚步总线跟随 SFX 总音量滑块(独立总线只负责滤波,不改变用户音量控制)
	set_bus_volume(BUS_STEPS, G.audio_setting("sfx_vol", 1.0))
	set_bus_volume(BUS_AMBIENCE, G.audio_setting("amb_vol", 1.0))
	set_bus_volume(BUS_UI, G.audio_setting("ui_vol", 1.0))


## 创建分层总线(Master 之外的四条;环境总线挂低频滤波,远处炮火更闷)
func _setup_buses() -> void:
	for b in [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE, BUS_UI, BUS_STEPS]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
	_ensure_lowpass(BUS_AMBIENCE, 2400.0)
	# 脚步总线低通:滤除采样自带的 10kHz+ 噪声成分(滋滋声来源)
	_ensure_lowpass(BUS_STEPS, 4200.0)
	# SFX 总线 8kHz 低通:统一削掉 ADPCM 量化噪声与高频泛音(枪声主体 <4kHz,
	# 8k 截止只切 10k+ 刺耳成分,不影响枪声/爆炸响度与冲击感)
	_ensure_lowpass(BUS_SFX, 8000.0)


## 给指定总线挂低通滤波(幂等,已挂则不重复)
func _ensure_lowpass(bus: String, cutoff: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectLowPassFilter:
			return
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = cutoff
	AudioServer.add_bus_effect(idx, lp)


func _snd(snd_name: String) -> AudioStream:
	if not _cache.has(snd_name):
		_cache[snd_name] = load("res://audio/" + snd_name + ".wav")
	return _cache[snd_name]


func set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))


## 分层总线音量(设置界面实时生效)
func set_bus_volume(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


func get_bus_volume(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(idx)) if idx != -1 else 1.0


func unlock() -> void:
	pass  # Godot 无需手势解锁


## 播放 2D 音效(玩家自身 / UI),可指定总线
func _play_2d(stream_name: String, vol := 1.0, pitch := 1.0, bus := BUS_SFX) -> void:
	var p := _players_2d[_p2d]
	_p2d = (_p2d + 1) % _players_2d.size()
	# 池复用前先 stop:直接换流会残留旧流缓冲(采样不连续 → 咔哒/嘶声)
	p.stop()
	p.stream = _snd(stream_name)
	p.bus = bus
	p.volume_db = linear_to_db(maxf(vol, 0.001))
	p.pitch_scale = pitch
	p.play()


## 播放 3D 定位音效(空间化:距离衰减 + 左右声道)
func _play_3d(stream_name: String, pos: Vector3, ref_dist := 10.0, max_dist := 130.0, vol := 1.0, pitch := 1.0) -> void:
	if G.camera == null:
		return
	var d := G.camera.global_position.distance_to(pos)
	if d > max_dist:
		return
	# 优先复用空闲 player;全部占用时替换"离听者最远"的声源(近距音不被远距音顶掉)
	var p: AudioStreamPlayer3D = null
	for pl in _players_3d:
		if not pl.playing:
			p = pl
			break
	if p == null:
		# 替换"离听者最远"的声源(近距音不被远距音顶掉);跳过从未播放、锚在 (0,0,0) 的闲置池成员
		var far := -1.0
		for i in _players_3d.size():
			if not _played_3d[i]:
				continue
			var pl := _players_3d[i]
			var pd := G.camera.global_position.distance_to(pl.global_position)
			if pd > far:
				far = pd
				p = pl
	# 池复用先 stop 旧流:直接换流会残留旧流缓冲,采样不连续 → 咔哒/嘶声
	p.stop()
	p.stream = _snd(stream_name)
	p.bus = BUS_SFX
	p.unit_size = ref_dist
	p.max_distance = max_dist
	p.volume_db = linear_to_db(maxf(vol, 0.001))
	p.pitch_scale = pitch
	p.global_position = pos
	_played_3d[_players_3d.find(p)] = true
	p.play()


# ==================== 枪声(音量/音高微随机,避免机械感) ====================
func shoot(kind: String, pos: Vector3, is_player: bool) -> void:
	var snd := "shoot_" + kind
	if kind == "dmr":
		snd = "shoot_dmr"
	elif not ["rifle", "smg", "lmg", "sniper", "pistol", "shotgun"].has(kind):
		snd = "shoot_rifle"
	var pv := Utils.rand(0.94, 1.06)
	var vv := Utils.rand(0.9, 1.1)
	if is_player:
		_play_2d(snd, 0.9 * vv, pv)
		# 3D 环境尾音:玩家枪声也带空间反射,更有层次
		_play_3d(snd, pos, 26, 150, 0.2, Utils.rand(0.9, 1.08))
	else:
		_play_3d(snd, pos, 14, 160, vv, pv)


func rpg_fire(pos: Vector3) -> void:
	_play_3d("rpg_fire", pos, 20, 200, Utils.rand(0.9, 1.1), Utils.rand(0.95, 1.05))


func dry_fire() -> void:
	_play_2d("dry_fire", 1.0, Utils.rand(0.95, 1.05))


func bolt() -> void:
	_play_2d("bolt", 1.0, Utils.rand(0.93, 1.07))


func reload(stage: int) -> void:
	_play_2d("reload_" + str(stage), Utils.rand(0.9, 1.1), Utils.rand(0.96, 1.04))


# ==================== 命中反馈 ====================
func hit(head: bool) -> void:
	_play_2d("hit_head" if head else "hit")


func kill_confirm(head: bool) -> void:
	_play_2d("kill_head" if head else "kill")


func hurt() -> void:
	_play_2d("hurt")


## 脚步音随地形材质变化(混凝土/沙地/草地/雪地)+ 音量/音高随机
## 滋滋声修复:脚步采样(尤其 step_concrete)含大量 10kHz+ 噪声成分,
## 大幅压低音量(行走 0.18-0.24 / 疾跑 0.26-0.32,原 0.55-1.2)并走低通总线,
## 音高随机收窄(0.96-1.04)减少重采样噪声,独立小池避免截断共享 2D 池
func step(run: bool) -> void:
	var mat: String = STEP_TERRAIN.get(G.current_map, "concrete")
	var snd := "step_" + mat
	if randf() < 0.35:
		snd = "step"  # 混入基础脚步,进一步打破重复感
	var v := Utils.rand(0.18, 0.24) if not run else Utils.rand(0.26, 0.32)
	v *= Utils.rand(0.8, 1.0)  # 每步音量微随机,避免节拍感
	var p := _step_players[_step_i]
	_step_i = (_step_i + 1) % _step_players.size()
	p.stream = _snd(snd)
	p.volume_db = linear_to_db(maxf(v, 0.001))
	p.pitch_scale = Utils.rand(0.96, 1.04)
	p.play()


## 爆炸:3D 衰减 + 近距离 3A 分层(次声冲击 rumble → 火球 explosion → 0.15s 碎屑层)
## 超远距离转为环境闷响
func explosion(pos: Vector3) -> void:
	_play_3d("explosion", pos, 40, 260)
	if G.camera != null and G.player != null and G.player.alive:
		var d := G.camera.global_position.distance_to(pos)
		if d > 260:
			# 超出 3D 衰减范围:环境总线低频闷响(战场纵深)
			_play_2d("rumble", Utils.rand(0.4, 0.75), Utils.rand(0.72, 0.9), BUS_AMBIENCE)
		elif d < 45:
			# 次声冲击(低音 rumble)+ 火球主体(explosion)同时爆发
			_play_2d("rumble", Utils.rand(0.5, 0.9), Utils.rand(0.5, 0.68))
			_play_2d("explosion", Utils.rand(0.45, 0.8), Utils.rand(0.55, 0.75))
			# 0.15s 延迟补碎屑/迸裂层(跳弹金属 + 弹落声合成,低音量随机)
			get_tree().create_timer(0.15).timeout.connect(func():
				_play_2d("ricochet", Utils.rand(0.2, 0.4), Utils.rand(1.15, 1.5))
				_play_2d("grenade_bounce", Utils.rand(0.25, 0.45), Utils.rand(0.9, 1.3)))


func ricochet(pos: Vector3) -> void:
	_play_3d("ricochet", pos, 8, 60, 1.0, Utils.rand(0.76, 1.24))


func grenade_bounce(pos: Vector3) -> void:
	_play_3d("grenade_bounce", pos, 8, 50)


## 占领/失守:原音 + 上行/下行提示音分层叠加
func capture(good: bool) -> void:
	_play_2d("capture_good" if good else "capture_bad", 0.9)
	_play_2d("cap_tone_win" if good else "cap_tone_lose", 0.75)


func ui() -> void:
	_play_2d("ui", Utils.rand(0.95, 1.05), Utils.rand(0.97, 1.03), BUS_UI)


func ui_hover() -> void:
	_play_2d("ui_hover", 0.45, Utils.rand(0.9, 1.1), BUS_UI)


func deploy_sting() -> void:
	_play_2d("deploy_sting", 1.0, 1.0, BUS_MUSIC)


func win() -> void:
	_play_2d("win", 1.0, 1.0, BUS_MUSIC)


func lose() -> void:
	_play_2d("lose", 1.0, 1.0, BUS_MUSIC)


# ==================== 载具引擎 ====================
func engine_start() -> void:
	if _engine_player != null:
		return
	_engine_player = AudioStreamPlayer.new()
	var s: AudioStreamWAV = _snd("engine_loop")
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	_engine_player.stream = s
	_engine_player.bus = BUS_SFX
	_engine_player.volume_db = linear_to_db(0.09)
	add_child(_engine_player)
	_engine_player.play()


func engine_update(speed: float) -> void:
	if _engine_player == null:
		return
	var f := 42.0 + absf(speed) * 7.5
	# 滋滋声消除:原公式音高无上限,吉普 17m/s 时 pitch≈4.03×,engine_loop 的
	# ADPCM 量化噪声与发动机谐波被整体抬进 8-16kHz 形成持续"嘶/嗡";钳制上限 1.6
	_engine_player.pitch_scale = clampf(f / 42.0, 0.05, 1.6)
	_engine_player.volume_db = linear_to_db(maxf(0.09 + minf(absf(speed) * 0.006, 0.06), 0.0))


func engine_stop() -> void:
	if _engine_player == null:
		return
	_engine_player.stop()
	_engine_player.queue_free()
	_engine_player = null


# ==================== 环境音 ====================
## 开旷地图(风感强):沙漠 / 雪地 / 海边码头
const WIND_OPEN_MAPS := ["desert", "snow", "bt_harbor"]
## 滋滋声排查:用户反馈持续的刺耳噪声/嘶嘶声,默认关闭环境风噪循环
## (wind_loop.wav 为纯噪声采样,循环端点不干净时被感知为电流声;置回 true 即恢复)
const WIND_ENABLED := false


## 风音量:0.6 基础,夜间图弱化、开旷图增强;WIND_ENABLED=false 时静音
func _wind_volume() -> float:
	if not WIND_ENABLED:
		return 0.0
	var v := 0.6
	var md = MapsData.M().get(G.current_map)
	if md != null:
		if md.night:
			v = 0.35
		elif G.current_map in WIND_OPEN_MAPS:
			v = 0.75
	return v


func _update_wind_volume() -> void:
	if _wind_player != null:
		_wind_player.volume_db = linear_to_db(_wind_volume())


func start_ambient() -> void:
	_ambient_on = true
	if _wind_player != null:
		_update_wind_volume()  # 换图后刷新风量(夜间弱/开旷强)
		return
	if not WIND_ENABLED:
		return  # 风噪已关闭:不创建 wind 循环(远处闷响/远距枪声氛围层不受影响)
	_wind_player = AudioStreamPlayer.new()
	var s: AudioStreamWAV = _snd("wind_loop")
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	_wind_player.stream = s
	_wind_player.bus = BUS_AMBIENCE
	_wind_player.volume_db = linear_to_db(_wind_volume())
	add_child(_wind_player)
	_wind_player.play()


func stop_ambient() -> void:
	_ambient_on = false
	if _wind_player != null:
		_wind_player.stop()
		_wind_player.queue_free()
		_wind_player = null


func _process(delta: float) -> void:
	var p = G.player
	# 远处闷响(战场氛围)
	if _ambient_on and G.state == "playing":
		_rumble_t -= delta
		if _rumble_t <= 0:
			_rumble_t = Utils.rand(3.0, 8.0)
			if randf() < 0.4:
				_play_2d("rumble", Utils.rand(0.6, 1.4), Utils.rand(0.8, 1.2), BUS_AMBIENCE)
		# 远距离枪声(随机触发,3D 空间化环绕战场)
		# 滋滋声消除:触发间隔 2.5-7s → 6-12s、音量 0.55 → 0.3(ADPCM 小采样高频量化噪声明显,降低出现密度与响度)
		_distant_t -= delta
		if _distant_t <= 0:
			_distant_t = Utils.rand(6.0, 12.0)
			if randf() < 0.7 and p != null and G.camera != null:
				var ang := randf() * TAU
				var r := Utils.rand(70.0, 160.0)
				_play_3d("distant_gun", p.pos + Vector3(cos(ang) * r, 2, sin(ang) * r), 60, 320, 0.3, Utils.rand(0.85, 1.05))
	# 动态反馈:低血量心跳 + 压制模糊音
	if p != null and p.alive:
		var hp: float = p.health
		_hb_t -= delta
		if hp < 35 and _hb_t <= 0:
			# 血量越低心跳越快越响
			var deficit := clampf((35.0 - hp) / 35.0, 0, 1)
			_hb_t = lerpf(1.35, 0.55, deficit)
			# 心跳上限收窄:低血量时最高 0.85,避免与脚步/枪声叠加削波
			_play_2d("heartbeat", 0.42 + deficit * 0.43, Utils.rand(0.96, 1.04), BUS_SFX)
		if p.suppression > 0.35:
			_start_suppressed()
		else:
			_stop_suppressed()
	else:
		_stop_suppressed()


## 压制模糊音(循环,压制时开启)
## 滋滋声复核:该 1.2s 噪声循环直通 SFX 高频刺耳,改走低通环境总线并降音量(闷响化,贴合"耳鸣"设定)
func _start_suppressed() -> void:
	if _sup_player != null:
		return
	_sup_player = AudioStreamPlayer.new()
	var s: AudioStreamWAV = _snd("suppressed")
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	_sup_player.stream = s
	_sup_player.bus = BUS_AMBIENCE
	_sup_player.volume_db = linear_to_db(0.55)
	add_child(_sup_player)
	_sup_player.play()


func _stop_suppressed() -> void:
	if _sup_player == null:
		return
	_sup_player.stop()
	_sup_player.queue_free()
	_sup_player = null
