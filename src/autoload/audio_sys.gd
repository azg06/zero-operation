extends Node
## 音频系统(对应 audio.js;音效为离线渲染的 WAV,与原 Web Audio 合成算法一致)
## 3A 升级:音量分层总线(Master/Music/SFX/Ambience/UI)+ 武器音效随机化
## + 地形脚步 + 低血量心跳 + 压制模糊音 + 远距离战场枪声

## 总线分层
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENCE := "Ambience"
const BUS_UI := "UI"
const BUS_VOICE := "Voice"
## 脚步独立总线(挂低通滤波):step_concrete 等采样为高频噪声合成(过零率≈12kHz),
## 直通 SFX 总线时表现为"滋滋/嘶嘶"声,低通后保留脚步声主频、去掉噪声尾巴
const BUS_STEPS := "Steps"

## 武器 id → 专属枪声文件(audio/guns 子目录);无专属音的武器回退通用 shoot_* 采样
const GUN_SOUND_FILES := {
	"m4": "m4a1_single_shot", "ak": "ak47", "scar": "scar_h", "aug": "aug_a3",
	"ump": "ump45", "deagle": "deserteagle", "g17": "glock17", "m93r": "m93r",
	"p226": "p226", "p90": "p90", "mp5": "mp5", "pkm": "pkm", "rpd": "rpd",
	"m249": "m249", "awm": "awm", "m24": "m24", "svd": "svd", "m1014": "m1014",
	"spas12": "spas12", "m1911": "m1911",
	# [8/10 武器扩充] 10 把新枪专属枪声(audiocpp 生成,已裁剪为单发)
	"g36c": "g36c", "ak74": "ak74", "famas": "famas", "vector": "vector",
	"pp19": "pp19", "mg42": "mg42", "m60": "m60", "m110": "m110",
	"m40": "m40", "g3": "g3",
	# [8/10 武器扩充 v2] 17 把新枪专属枪声(audiocpp 生成,单发变体筛选 + 裁剪 1s)
	"mpx": "mpx", "mp7": "mp7", "pp2000": "pp2000", "mk48": "mk48",
	"negev": "negev", "mg3": "mg3", "m82a1": "m82a1", "l115": "l115",
	"sv98": "sv98", "m2010": "m2010", "sks": "sks", "m1a": "m1a",
	"g28": "g28", "mk14": "mk14", "m14": "m14", "ar10": "ar10", "fal": "fal",
}
## 响度补偿:源 wav 实测这 4 个枪声素材峰值过低(ump45=0.089/-21dB、aug_a3=0.114/-18.8dB、
## p90=0.114/-18.8dB、glock17=0.130/-17.7dB,其余 16 个 0.17-1.0 正常),运行时按文件名增益
## (不预处理 wav),补偿后估算峰值≈0.25-0.3,与其他枪听感一致;键必须对应 GUN_SOUND_FILES 值
const GUN_GAIN := { "ump45": 3.0, "aug_a3": 2.2, "p90": 2.2, "glock17": 2.0,
	"m249": 1.2, "m60": 1.9, "negev": 1.5, "mk48": 1.15, "rpd": 1.2 }
## 换弹动作音效:动作名 -> audio/reload 下的文件名(由 audio.cpp Stable Audio SFX 生成)
const RELOAD_ACTION_FILES := {
	"mag_out": "mag_out",
	"mag_in": "mag_in",
	"ammo_pouch": "ammo_pouch",
	"drum_pouch": "drum_pouch",
	"belt_pouch": "belt_pouch",
	"bolt_cycle": "bolt_cycle",
	"slide_release": "slide_release",
	"shell_grab": "shell_grab",
	"shell_insert": "shell_insert",
	"shotgun_pump": "shotgun_pump",
	"rocket_remove": "rocket_remove",
	"rocket_load": "rocket_load",
	"drum_unlock": "drum_unlock",
	"drum_detach": "drum_detach",
	"drum_insert": "drum_insert",
	"drum_lock": "drum_lock",
	"cover_open": "cover_open",
	"cover_close": "cover_close",
	"belt_out": "belt_out",
	"belt_in": "belt_in",
	"belt_lock": "belt_lock",
	# 枪族区分版本
	"mag_out_ak": "mag_out_ak",
	"mag_in_ak": "mag_in_ak",
	"mag_out_smg": "mag_out_smg",
	"mag_in_smg": "mag_in_smg",
	"mag_out_pistol": "mag_out_pistol",
	"mag_in_pistol": "mag_in_pistol",
	"mag_out_sniper": "mag_out_sniper",
	"mag_in_sniper": "mag_in_sniper",
	"ammo_pouch_pistol": "ammo_pouch_pistol",
	"ammo_pouch_smg": "ammo_pouch_smg",
	"ammo_pouch_sniper": "ammo_pouch_sniper",
	"bolt_cycle_ak": "bolt_cycle_ak",
	"bolt_cycle_smg": "bolt_cycle_smg",
	"bolt_cycle_sniper": "bolt_cycle_sniper",
	"bolt_cycle_lmg": "bolt_cycle_lmg",
	"cover_open_heavy": "cover_open_heavy",
	"cover_close_heavy": "cover_close_heavy",
	"belt_out_heavy": "belt_out_heavy",
	"belt_in_heavy": "belt_in_heavy",
	"belt_lock_heavy": "belt_lock_heavy",
	# [9/10] 新泵动霰弹枪逐发装填独立采样
	"shell_grab_rem870": "shell_grab_rem870", "shell_insert_rem870": "shell_insert_rem870",
	"shell_grab_m590": "shell_grab_m590", "shell_insert_m590": "shell_insert_m590",
	"shell_grab_win1897": "shell_grab_win1897", "shell_insert_win1897": "shell_insert_win1897",
}
## 各动作采样的响度补偿:把合成素材拉到游戏内统一听感(峰值越低增益越大)
const RELOAD_ACTION_GAIN := {
	"shell_grab": 5.0, "shell_insert": 1.6, "ammo_pouch": 1.6, "belt_pouch": 2.0,
	"drum_pouch": 1.7, "slide_release": 1.2, "mag_out": 1.2, "mag_in": 1.2,
	"bolt_cycle": 1.4, "rocket_remove": 1.0, "rocket_load": 1.3, "drum_detach": 1.0,
	"drum_unlock": 1.0, "drum_lock": 1.1, "cover_open": 1.0, "cover_close": 1.0,
	"drum_insert": 1.0, "shotgun_pump": 1.0, "belt_out": 1.0, "belt_in": 1.0,
	"belt_lock": 1.2,
	"mag_out_ak": 1.2, "mag_in_ak": 1.0, "mag_out_smg": 1.3, "mag_in_smg": 1.4,
	"mag_out_pistol": 1.0, "mag_in_pistol": 1.0, "mag_out_sniper": 1.0, "mag_in_sniper": 1.0,
	"ammo_pouch_pistol": 2.5, "ammo_pouch_smg": 2.2, "ammo_pouch_sniper": 1.3,
	"bolt_cycle_ak": 1.0, "bolt_cycle_smg": 1.4, "bolt_cycle_sniper": 1.2, "bolt_cycle_lmg": 1.0,
	"cover_open_heavy": 1.0, "cover_close_heavy": 1.0, "belt_out_heavy": 1.0,
	"belt_in_heavy": 1.0, "belt_lock_heavy": 1.3,
	# [9/10] 新泵动/左轮动作采样响度补偿(按实测峰值统一到 -3~0 dBFS 听感)
	"pump_back_rem870": 1.0, "pump_fwd_rem870": 1.0, "pump_finish_rem870": 1.3,
	"pump_back_m590": 1.1, "pump_fwd_m590": 1.0, "pump_finish_m590": 1.7,
	"pump_back_win1897": 1.1, "pump_fwd_win1897": 1.05, "pump_finish_win1897": 1.0,
	"revolver_open_python": 1.2, "revolver_close_python": 1.4, "revolver_eject_python": 1.5,
	"revolver_round_python": 2.2, "revolver_insert_python": 1.6, "revolver_loader_python": 1.0,
	"revolver_hammer_python": 1.5, "revolver_rotate_python": 2.2,
	"revolver_open_sw686": 1.7, "revolver_close_sw686": 2.2, "revolver_eject_sw686": 1.7,
	"revolver_round_sw686": 2.8, "revolver_insert_sw686": 2.3, "revolver_loader_sw686": 1.6,
	"revolver_hammer_sw686": 2.4, "revolver_rotate_sw686": 2.5,
	"revolver_open_sw500": 1.1, "revolver_close_sw500": 1.8, "revolver_eject_sw500": 2.1,
	"revolver_round_sw500": 1.6, "revolver_insert_sw500": 2.0, "revolver_loader_sw500": 2.5,
	"revolver_hammer_sw500": 1.8, "revolver_rotate_sw500": 2.5,
	"shell_grab_rem870": 5.5, "shell_insert_rem870": 1.4,
	"shell_grab_m590": 2.9, "shell_insert_m590": 1.1,
	"shell_grab_win1897": 4.8, "shell_insert_win1897": 1.4,
}
## [9/10] 程序化合成枪声/机械声(启动时一次性生成并缓存,零每帧开销,不占用磁盘资源)。
## 每种新武器按名字确定性生成独立波形;不复制任何已有枪声文件。
const GEN_GUN_IDS := {
	"rem870": "shotgun_870", "m590": "shotgun_590", "win1897": "shotgun_1897",
	"python": "revolver_357", "sw686": "revolver_357s", "sw500": "revolver_500",
}
const GEN_ACTION_NAMES := {
	"pump_back_rem870": "mech_pump_back", "pump_fwd_rem870": "mech_pump_fwd", "pump_finish_rem870": "mech_pump_lock",
	"pump_back_m590": "mech_pump_back_heavy", "pump_fwd_m590": "mech_pump_fwd_heavy", "pump_finish_m590": "mech_pump_lock_heavy",
	"pump_back_win1897": "mech_pump_back_old", "pump_fwd_win1897": "mech_pump_fwd_old", "pump_finish_win1897": "mech_pump_lock_old",
	"pump_back_m1014": "mech_pump_back", "pump_fwd_m1014": "mech_pump_fwd", "pump_finish_m1014": "mech_pump_lock",
	"pump_back_spas12": "mech_pump_back_heavy", "pump_fwd_spas12": "mech_pump_fwd_heavy", "pump_finish_spas12": "mech_pump_lock_heavy",
	"revolver_open_python": "rv_open", "revolver_close_python": "rv_close", "revolver_eject_python": "rv_eject",
	"revolver_round_python": "rv_round", "revolver_loader_python": "rv_loader", "revolver_insert_python": "rv_insert",
	"revolver_hammer_python": "rv_hammer", "revolver_rotate_python": "rv_rotate",
	"revolver_open_sw686": "rv_open_light", "revolver_close_sw686": "rv_close_light", "revolver_eject_sw686": "rv_eject_light",
	"revolver_round_sw686": "rv_round_light", "revolver_loader_sw686": "rv_loader_light", "revolver_insert_sw686": "rv_insert_light",
	"revolver_hammer_sw686": "rv_hammer_light", "revolver_rotate_sw686": "rv_rotate_light",
	"revolver_open_sw500": "rv_open_heavy", "revolver_close_sw500": "rv_close_heavy", "revolver_eject_sw500": "rv_eject_heavy",
	"revolver_round_sw500": "rv_round_heavy", "revolver_loader_sw500": "rv_loader_heavy", "revolver_insert_sw500": "rv_insert_heavy",
	"revolver_hammer_sw500": "rv_hammer_heavy", "revolver_rotate_sw500": "rv_rotate_heavy",
	"inspect_grab": "inspect_grab",
}
## 载具类型 → [音频文件, 参考距离, 最大距离](audio/vehicles 子目录)
const VEH_SOUND_FILES := {
	"tank": ["tank_gun", 25, 280],
	"apc": ["ifv_autocannon", 18, 190],
	"aa": ["aa_gun", 18, 190],
	"heli": ["attack_heli", 20, 220],
	"jet": ["fighter_missile", 24, 250],
}
## 载具类型 → 引擎采样前缀(audio/engines 子目录,<prefix>_engine_v<N>.wav,按 N 升序为档位)。
## 素材复用:apc 用 ifv 素材;heli/jet 为空中类型(aircraft.gd 自管,此处仅注册供参考)
const ENGINE_GEAR_FILES := {
	"tank": "tank", "ifv": "ifv", "apc": "ifv",
	"aa": "aa", "jeep": "jeep", "heli": "heli", "jet": "fighter",
}

## 地图 → 脚步材质映射
const STEP_TERRAIN := {
	"city": "concrete", "desert": "sand", "snow": "snow",
	"bt_jungle": "grass", "bt_harbor": "concrete", "bt_peak": "snow",
}

var _cache: Dictionary = {}
var _gen_cache: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _step_players: Array[AudioStreamPlayer] = []  # 脚步专用小池:不与枪声/爆炸争抢共享 2D 池(避免互相截断爆音)
var _played_3d: Array[bool] = []  # 曾播放标记:替换最远声源时跳过从未播放的闲置池成员
var _p2d := 0
var _step_i := 0
var _eng_players: Array[AudioStreamPlayer] = []   # 引擎 A/B 双 player(档位交叉淡化交替)
var _eng_streams: Array[AudioStreamWAV] = []      # 当前载具类型的档位采样(按档位升序)
var _eng_gear := -1                               # 当前档位索引
var _eng_active := 0                              # 当前档位所在 player 下标(0/1 交替)
var _eng_fade_in_t := 0.0                         # 新档淡入剩余时长(>0 时音量由计时器爬升)
var _eng_tween: Tween = null                      # 旧档淡出 tween(0.15s → -60dB 后停)
var _eng_gain := 1.0                              # 响度补偿:地面引擎类型增益(aa=1.8/jeep=1.5/其余 1.0)
var _ambient_on := false
var _rumble_t := 0.0
var _distant_t := 0.0
var _hb_t := 0.0
var _sup_player: AudioStreamPlayer = null
var _voice_player: AudioStreamPlayer = null


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
	# 对白人声专用播放器:独立总线,不参与枪声/爆炸共享池争夺
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = BUS_VOICE
	add_child(_voice_player)
	for i in 40:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = BUS_SFX
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_players_3d.append(p3)
		_played_3d.append(false)
	apply_volumes()
	_preload_hot()


## [PERF] 预加载高频音效(枪声/命中/击杀/换弹):消除战斗中首次播放的加载尖峰
## (实测 bot 开火 max 1545µs 来自 audio/guns 首次 ResourceLoader.load,预载后归零)
func _preload_hot() -> void:
	for v in GUN_SOUND_FILES.values():
		_snd(v, "guns")
	for v in RELOAD_ACTION_FILES.values():
		_snd(v, "reload")
	# [9/10] 新武器音效启动时预载:优先 audio/guns|reload 的 AI 合成文件,缺失回退程序化合成缓存
	for wid in GEN_GUN_IDS:
		if ResourceLoader.exists("res://audio/guns/" + wid + ".wav") or ResourceLoader.exists("res://audio/guns/" + wid + ".ogg"):
			_snd(wid, "guns")
		else:
			_gen_snd("fire_" + wid)
	for an in GEN_ACTION_NAMES:
		if ResourceLoader.exists("res://audio/reload/" + an + ".wav") or ResourceLoader.exists("res://audio/reload/" + an + ".ogg"):
			_snd(an, "reload")
		else:
			_gen_snd(an)
	for k in ["shoot_rifle", "shoot_smg", "shoot_lmg", "shoot_sniper", "shoot_pistol", "shoot_shotgun", "shoot_dmr",
			"hit", "hit_head", "kill", "kill_head", "dry_fire", "bolt",
			"reload_0", "reload_1", "reload_2", "reload_3", "rpg_fire"]:
		_snd(k)
	for e in VEH_SOUND_FILES.values():
		_snd(e[0], "vehicles")


## 从 G.settings 恢复各总线音量(Master + 四条分层)
func apply_volumes() -> void:
	set_volume(G.settings.volume)
	set_bus_volume(BUS_MUSIC, G.audio_setting("music_vol", 1.0))
	set_bus_volume(BUS_SFX, G.audio_setting("sfx_vol", 1.0))
	# 脚步总线跟随 SFX 总音量滑块(独立总线只负责滤波,不改变用户音量控制)
	set_bus_volume(BUS_STEPS, G.audio_setting("sfx_vol", 1.0))
	set_bus_volume(BUS_AMBIENCE, G.audio_setting("amb_vol", 1.0))
	set_bus_volume(BUS_UI, G.audio_setting("ui_vol", 1.0))
	# 对白人声跟随 SFX 音量滑块(人声需要清晰,不做低通)
	set_bus_volume(BUS_VOICE, G.audio_setting("sfx_vol", 1.0))


## 创建分层总线(Master 之外的四条;环境总线挂低频滤波,远处炮火更闷)
func _setup_buses() -> void:
	for b in [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE, BUS_UI, BUS_STEPS, BUS_VOICE]:
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


## 音频加载:优先 .ogg(体积压缩),缺失时回退 .wav(循环音效仍为 wav);两者都缺返回 null
func _snd(snd_name: String, sub := "") -> AudioStream:
	var key := (sub + "/" if sub != "" else "") + snd_name
	if sub == "gen":
		return _gen_snd(snd_name)
	if not _cache.has(key):
		var base := "res://audio/" + (sub + "/" if sub != "" else "") + snd_name
		var p := ""
		if ResourceLoader.exists(base + ".ogg"):
			p = base + ".ogg"
		elif ResourceLoader.exists(base + ".wav"):
			p = base + ".wav"
		_cache[key] = load(p) if p != "" else null
	return _cache[key]


## [9/10] 名字确定性哈希:同一声源每次启动波形一致,不同武器/动作音色不同。
func _gen_hash(s: String) -> int:
	var h := 17
	for i in s.length():
		h = (h * 131 + s.unicode_at(i)) % 1000003
	return h


func _gen_snd(snd_name: String) -> AudioStream:
	if _gen_cache.has(snd_name):
		return _gen_cache[snd_name]
	var s := _synth_gen(snd_name)
	_gen_cache[snd_name] = s
	return s


## 程序化合成:枪声为低频爆鸣 + 噪声冲击 + 金属尾音;机械声为短促金属 click/rattle。
## 16-bit 22.05kHz 单声道,启动时一次性构建并缓存,运行时零合成开销。
func _synth_gen(snd_name: String) -> AudioStream:
	var sr := 22050
	var h := _gen_hash(snd_name)
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var dur := 0.42
	var body := 0.0
	var ring_f := 620.0
	var ring_amp := 0.18
	var low_f := 68.0
	var low_amp := 0.55
	var noise_amp := 0.5
	var attack := 0.003
	var band := 0.72
	if snd_name.begins_with("fire_"):
		var wid := snd_name.trim_prefix("fire_")
		var kind: String = GEN_GUN_IDS.get(wid, "shotgun")
		if kind.begins_with("shotgun"):
			dur = 0.52
			body = 7.5
			ring_f = 340.0 + float(h % 90)
			ring_amp = 0.12
			low_f = 44.0 + float(h % 21)
			low_amp = 0.85
			noise_amp = 0.38
			band = 0.5
		elif kind == "revolver_500":
			dur = 0.46
			body = 13.0
			ring_f = 780.0
			ring_amp = 0.22
			low_f = 95.0
			low_amp = 0.7
			noise_amp = 0.85
			band = 0.82
		else:
			dur = 0.4
			body = 16.0
			ring_f = 690.0 + float(h % 130)
			ring_amp = 0.2
			low_f = 150.0
			low_amp = 0.38
			noise_amp = 0.82
			band = 0.76
	elif snd_name.begins_with("pump_"):
		dur = 0.3
		body = 26.0
		ring_f = 290.0
		ring_amp = 0.08
		low_f = 80.0
		low_amp = 0.32
		noise_amp = 0.6
		band = 0.4
	elif snd_name.begins_with("revolver_"):
		dur = 0.22 if "rotate" in snd_name or "round" in snd_name else 0.3
		body = 34.0
		ring_f = 980.0 + float(h % 420)
		ring_amp = 0.3 if "hammer" in snd_name else 0.16
		low_f = 130.0
		low_amp = 0.14
		noise_amp = 0.55
		band = 0.82
	else:
		dur = 0.16
		body = 40.0
		ring_f = 520.0
		ring_amp = 0.1
		low_f = 110.0
		low_amp = 0.1
		noise_amp = 0.3
		band = 0.7
	var n := int(sr * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	var phase2 := 0.0
	var t := 0.0
	for i in n:
		t = float(i) / float(sr)
		var nz := rng.randf() * 2.0 - 1.0
		lp += (nz - lp) * band
		lp2 += (lp - lp2) * 0.35
		var env := exp(-t * body)
		var atk := clampf(t / maxf(attack, 0.0005), 0.0, 1.0)
		phase = fmod(phase + TAU * low_f / float(sr), TAU)
		phase2 = fmod(phase2 + TAU * ring_f / float(sr), TAU)
		var v := lp * noise_amp * env * atk \
			+ sin(phase) * low_amp * env \
			+ sin(phase2) * ring_amp * exp(-t * (body * 0.55))
		# 机械动作音在采样中段做第二声 click(开/关/装填的两段金属碰撞)
		if not snd_name.begins_with("fire_"):
			var t2 := t - dur * 0.44
			if t2 >= 0.0 and t2 < 0.02:
				var c := (1.0 - t2 / 0.02)
				v += nz * c * 0.5
		v = tanh(v * 1.15)
		data.encode_s16(i * 2, clampi(int(v * 31500.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sr
	s.stereo = false
	s.data = data
	return s


func set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))


## 分层总线音量(设置界面实时生效)
func set_bus_volume(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


## 对白人声:播放 audio/voice/<id>.wav(战役台词行ID)。
## 独立 Voice 总线 + 专用播放器:不被枪声/爆炸共享池截断,新台词打断旧台词;
## 文件缺失时静默跳过(不影响文字字幕)。返回音频时长(秒),未播放返回 0。
func voice(id: String) -> float:
	if id.is_empty():
		return 0.0
	var s: AudioStream = _snd(id, "voice")
	if s == null:
		return 0.0
	_voice_player.stop()
	_voice_player.stream = s
	_voice_player.play()
	return s.get_length()


## 对白音频时长(秒):仅查询不播放,供字幕/过场节奏同步;文件缺失返回 0
func voice_duration(id: String) -> float:
	if id.is_empty():
		return 0.0
	var s: AudioStream = _snd(id, "voice")
	return s.get_length() if s != null else 0.0


## 立即停止当前对白(过场跳过/切章/中止时调用,防台词残留到战斗或结算屏)
func voice_stop() -> void:
	if _voice_player != null:
		_voice_player.stop()


## 播放 2D 音效(玩家自身 / UI),可指定总线;sub 指定 audio/ 下子目录
func _play_2d(stream_name: String, vol := 1.0, pitch := 1.0, bus := BUS_SFX, sub := "") -> void:
	var p := _players_2d[_p2d]
	_p2d = (_p2d + 1) % _players_2d.size()
	# 池复用前先 stop:直接换流会残留旧流缓冲(采样不连续 → 咔哒/嘶声)
	p.stop()
	p.stream = _snd(stream_name, sub)
	p.bus = bus
	p.volume_db = linear_to_db(maxf(vol, 0.001))
	p.pitch_scale = pitch
	p.play()


## 播放 3D 定位音效(空间化:距离衰减 + 左右声道);sub 指定 audio/ 下子目录
func _play_3d(stream_name: String, pos: Vector3, ref_dist := 10.0, max_dist := 130.0, vol := 1.0, pitch := 1.0, sub := "") -> void:
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
	p.stream = _snd(stream_name, sub)
	p.bus = BUS_SFX
	p.unit_size = ref_dist
	p.max_distance = max_dist
	p.volume_db = linear_to_db(maxf(vol, 0.001))
	p.pitch_scale = pitch
	p.global_position = pos
	_played_3d[_players_3d.find(p)] = true
	p.play()


# ==================== 枪声(音量/音高微随机,避免机械感) ====================
func shoot(kind: String, pos: Vector3, is_player: bool, suppressed := false) -> void:
	var snd := "shoot_" + kind
	if kind == "dmr":
		snd = "shoot_dmr"
	elif not ["rifle", "smg", "lmg", "sniper", "pistol", "shotgun"].has(kind):
		snd = "shoot_rifle"
	var pv := Utils.rand(0.94, 1.06)
	var vv := Utils.rand(0.9, 1.1)
	if is_player:
		if suppressed:
			# 消音器枪声:复用现有采样大幅降音量 + 降音高(亚音速闷响感),无独立消音采样
			_play_2d(snd, 0.26 * vv, Utils.rand(0.78, 0.88))
			_play_3d(snd, pos, 26, 150, 0.04, Utils.rand(0.8, 0.92))
		else:
			_play_2d(snd, 0.9 * vv, pv)
			# 3D 环境尾音:玩家枪声也带空间反射,更有层次
			_play_3d(snd, pos, 26, 150, 0.2, Utils.rand(0.9, 1.08))
	else:
		_play_3d(snd, pos, 14, 160, vv, pv)


## 武器专属枪声:命中 GUN_SOUND_FILES 注册表的武器播放 audio/guns 专属采样,
## 参数与 shoot() 一致(音量/音高微随机 + 消音分支);无专属音的武器回退 shoot(kind)
func shoot_weapon(weapon_id: String, kind: String, pos: Vector3, is_player: bool, suppressed := false) -> void:
	var generated := GEN_GUN_IDS.has(weapon_id)
	var file_name := weapon_id if generated else ""
	var use_file: bool = generated and (ResourceLoader.exists("res://audio/guns/" + file_name + ".wav") or ResourceLoader.exists("res://audio/guns/" + file_name + ".ogg"))
	var snd: String = file_name if use_file else (("fire_" + weapon_id) if generated else GUN_SOUND_FILES.get(weapon_id, ""))
	var sub := "guns" if use_file else ("gen" if generated else "guns")
	if snd.is_empty():
		shoot(kind, pos, is_player, suppressed)
		return
	var pv := Utils.rand(0.94, 1.06)
	var vv := Utils.rand(0.9, 1.1)
	# 响度补偿:低峰值枪声按 GUN_GAIN 增益;程序化枪声已按类型校准,无需文件级补偿
	var gain: float = GUN_GAIN.get(snd, 1.0)
	if is_player:
		if suppressed:
			# 消音器枪声:复用现有采样大幅降音量 + 降音高(亚音速闷响感),无独立消音采样
			_play_2d(snd, 0.26 * vv, Utils.rand(0.78, 0.88), BUS_SFX, sub)
			_play_3d(snd, pos, 26, 150, 0.04, Utils.rand(0.8, 0.92), sub)
		else:
			_play_2d(snd, 0.9 * gain * vv, pv, BUS_SFX, sub)
			# 3D 环境尾音:玩家枪声也带空间反射,更有层次
			_play_3d(snd, pos, 26, 150, 0.2 * gain / 0.9, Utils.rand(0.9, 1.08), sub)
	else:
		_play_3d(snd, pos, 14, 160, vv * gain, pv, sub)


## 载具武器开火(坦克主炮/APC/AA 机炮/直升机机炮/战斗机导弹):audio/vehicles 专属采样
func veh_weapon(type: String, pos: Vector3) -> void:
	if not VEH_SOUND_FILES.has(type):
		return
	var e: Array = VEH_SOUND_FILES[type]
	_play_3d(e[0], pos, e[1], e[2], 1.0, Utils.rand(0.95, 1.05), "vehicles")


## 载具内部机械声:炮闩闭锁/供弹机构/液压随动。
## event 优先取 RELOAD_ACTION_FILES 中的机械采样;rumble 走低频冲击(爆炸同款)。
func veh_mech(event: String, vol := 0.5) -> void:
	var file: String = RELOAD_ACTION_FILES.get(event, "")
	if file != "":
		var gain: float = clampf(float(RELOAD_ACTION_GAIN.get(file, 1.0)) * 0.5 * vol, 0.05, 0.75)
		_play_2d(file, gain, Utils.rand(0.9, 1.06), BUS_SFX, "reload")
	elif event == "rumble":
		_play_2d("rumble", clampf(vol, 0.1, 0.7), Utils.rand(0.5, 0.62))
	elif event == "turret":
		_play_2d("bolt_cycle", clampf(vol * 0.3, 0.05, 0.25), Utils.rand(0.82, 1.05), BUS_SFX, "reload")


func rpg_fire(pos: Vector3) -> void:
	# 玩家开火时 2D 主体 + 3D 环境尾音;其他单位仍用 3D 定位
	if G.player != null and pos.distance_to(G.player.pos) < 2.0:
		_play_2d("rpg_fire", 0.95, Utils.rand(0.94, 1.06))
	_play_3d("rpg_fire", pos, 20, 200, Utils.rand(0.9, 1.1), Utils.rand(0.95, 1.05))


func dry_fire() -> void:
	_play_2d("dry_fire", 1.0, Utils.rand(0.95, 1.05))


func bolt() -> void:
	_play_2d("bolt", 1.0, Utils.rand(0.93, 1.07))


func reload(stage: int) -> void:
	_play_2d("reload_" + str(stage), Utils.rand(0.9, 1.1), Utils.rand(0.96, 1.04))


## 换弹动作音效统一入口:每个动作播放 audio/reload 下对应的 AI 合成采样。
## pitch_scale 由 ReloadProfiles 按枪型传入(重型机枪更低沉,高射速机枪更清脆)。
func reload_action(action: String, pitch_scale := 1.0) -> void:
	if GEN_ACTION_NAMES.has(action):
		var use_file: bool = ResourceLoader.exists("res://audio/reload/" + action + ".wav") or ResourceLoader.exists("res://audio/reload/" + action + ".ogg")
		var g1: float = 1.0
		if use_file:
			g1 = clampf(float(RELOAD_ACTION_GAIN.get(action, 1.0)), 0.4, 6.0)
			_play_2d(action, g1, clampf(pitch_scale, 0.75, 1.3), BUS_SFX, "reload")
		else:
			_play_2d(action, 0.9, clampf(pitch_scale, 0.75, 1.3), BUS_SFX, "gen")
		return
	var snd: String = RELOAD_ACTION_FILES.get(action, "")
	if snd.is_empty():
		return
	var gain: float = float(RELOAD_ACTION_GAIN.get(snd, 1.0))
	_play_2d(snd, clampf(gain, 0.5, 5.0), clampf(pitch_scale, 0.75, 1.3), BUS_SFX, "reload")


## [9/10] 武器专属机械音:AI 合成动作文件优先,缺失时回退程序化合成。
func weapon_mech(event: String, pitch_scale := 1.0, vol := 1.0) -> void:
	if GEN_ACTION_NAMES.has(event):
		var use_file: bool = ResourceLoader.exists("res://audio/reload/" + event + ".wav") or ResourceLoader.exists("res://audio/reload/" + event + ".ogg")
		var g2: float = clampf(vol, 0.2, 1.4)
		if use_file:
			g2 = clampf(float(RELOAD_ACTION_GAIN.get(event, 1.0)) * vol, 0.2, 3.5)
			_play_2d(event, g2, clampf(pitch_scale, 0.75, 1.3), BUS_SFX, "reload")
		else:
			_play_2d(event, g2, clampf(pitch_scale, 0.75, 1.3), BUS_SFX, "gen")
		return
	reload_action(event, pitch_scale)


## 弹鼓/弹链轻机枪机械音效事件:直接路由到对应的 AI 合成动作采样。
func mech(event: String, pitch_scale := 1.0) -> void:
	reload_action(event, pitch_scale)


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
			# 新 explosion.wav(4s)响度与持续能量高于旧素材,2D 近距层音量下调防过响(0.45-0.8 → 0.3-0.55)
			_play_2d("rumble", Utils.rand(0.5, 0.9), Utils.rand(0.5, 0.68))
			_play_2d("explosion", Utils.rand(0.3, 0.55), Utils.rand(0.55, 0.75))
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
## 按载具类型启动引擎循环音:加载该类型全部档位采样(文件名数字后缀 v0-v9 升序,
## 档位编号可不连续,如 ifv 只有 v1/v2、aa 只有 v0/v2),
## A/B 双 player 支持档位交叉淡化;类型未知/素材缺失回退 engine_loop(不崩溃)
func engine_start(v_type := "") -> void:
	if not _eng_players.is_empty():
		return
	# 响度补偿:aa_engine(-12dB)/jeep_engine(-12.6dB) 素材峰值偏低,tank 0.50/ifv 0.79-0.83 正常
	# → aa×1.8、jeep×1.5,tank/ifv/apc ×1.0(heli/jet 走 aircraft.gd 自管,不经此处)
	_eng_gain = 1.8 if v_type == "aa" else (1.5 if v_type == "jeep" else 1.0)
	var streams: Array[AudioStreamWAV] = []
	var base: String = ENGINE_GEAR_FILES.get(v_type, "")
	if base != "":
		for v in range(10):
			var path := "res://audio/engines/%s_engine_v%d.wav" % [base, v]
			if ResourceLoader.exists(path):
				streams.append(_snd("%s_engine_v%d" % [base, v], "engines"))
	if streams.is_empty():
		streams.append(_snd("engine_loop"))
	for s in streams:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_eng_players.append(p)
	_eng_streams = streams
	_eng_gear = 0
	_eng_active = 0
	_eng_fade_in_t = 0.0
	_eng_players[0].stream = _eng_streams[0]
	_eng_players[0].pitch_scale = 1.0
	_eng_players[0].volume_db = linear_to_db(0.18 * _eng_gain)
	_eng_players[0].play()


## 档位交叉淡化:旧档 player 0.15s 淡出至 -60dB 后停(避免换流咔哒声),
## 新档采样载入另一 player 淡入(0.25s,淡入音量由 engine_update 计时器爬升)
func _engine_set_gear(gear: int) -> void:
	if gear == _eng_gear or gear >= _eng_streams.size():
		return
	var old := _eng_players[_eng_active]
	_eng_active = 1 - _eng_active
	_eng_gear = gear
	if _eng_tween != null:
		_eng_tween.kill()
	_eng_tween = old.create_tween()
	# 起点夹取:旧 player 音量可能已是 -inf(linear_to_db(0)),直接由此插值会得 NaN
	_eng_tween.tween_property(old, "volume_db", -60.0, 0.15).from(maxf(old.volume_db, -60.0))
	_eng_tween.tween_callback(old.stop)
	var newp := _eng_players[_eng_active]
	newp.stop()
	newp.stream = _eng_streams[gear]
	newp.pitch_scale = 1.0
	newp.volume_db = linear_to_db(0.002)
	newp.play()
	_eng_fade_in_t = 0.25


## 档位按转速比切换:|speed|/max_speed 归一:2 档 → ≤0.45 档0 否则档1;
## 3 档 → ≤0.3/≤0.65/否则 档0/1/2;同时音高微调 0.9-1.15、音量 (0.18+speed*0.007)×_eng_gain
## (上限放宽到 0.5,容纳 aa×1.8 后 0.35 目标音量的放大空间)
func engine_update(speed: float, max_speed := 1.0) -> void:
	if _eng_players.is_empty():
		return
	var ratio := clampf(absf(speed) / maxf(max_speed, 0.01), 0.0, 1.0)
	var n := _eng_streams.size()
	var gear := 0
	if n == 2:
		gear = 1 if ratio > 0.45 else 0
	elif n >= 3:
		gear = 2 if ratio > 0.65 else (1 if ratio > 0.3 else 0)
	if gear != _eng_gear:
		_engine_set_gear(gear)
	var p := _eng_players[_eng_active]
	p.pitch_scale = lerpf(0.9, 1.15, ratio)
	var target_v := clampf((0.18 + absf(speed) * 0.007) * _eng_gain, 0.0, 0.5)
	# 新档淡入期:音量由计时器从 0.002 爬升到目标值,避免瞬时跳变爆音
	if _eng_fade_in_t > 0:
		_eng_fade_in_t -= get_process_delta_time()
		if _eng_fade_in_t > 0:
			p.volume_db = linear_to_db(maxf(lerpf(0.002, target_v, 1.0 - _eng_fade_in_t / 0.25), 0.0001))
			return
	p.volume_db = linear_to_db(maxf(target_v, 0.0001))


func engine_stop() -> void:
	if _eng_players.is_empty():
		return
	if _eng_tween != null:
		_eng_tween.kill()
		_eng_tween = null
	for p in _eng_players:
		p.stop()
		p.queue_free()
	_eng_players.clear()
	_eng_streams.clear()
	_eng_gear = -1
	_eng_active = 0
	_eng_fade_in_t = 0.0
	_eng_gain = 1.0


# ==================== 环境音 ====================
## 环境氛围 = 远处闷响 + 远距战场枪声(_process 定时随机触发)。
## 风噪循环已整体移除:wind_loop.wav 为 7.7s 单声道纯噪声采样,实测响度仅约
## -51dBFS(峰值 -43dB)近乎不可闻,且循环端点不干净曾被用户反馈为持续
## "嘶嘶/电流声"——与飞机引擎曾弃用该采样(wind_loop→engine_loop)为同源
## 质量问题,无修复价值,故连资源文件一并删除(见 aircraft.gd:71 历史注释)。

func start_ambient() -> void:
	_ambient_on = true


func stop_ambient() -> void:
	_ambient_on = false


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
