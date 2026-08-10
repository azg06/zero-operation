class_name BotManager extends Node
## AI 管理器(对应 ai.js 的 BotManager)
## 职责:生成/销毁、小队编制、每局兵种武器分配、按玩家表现动态平衡

var bots: Array = []

# ---- 动态平衡 ----
var base_per_team := 11
var target_per_team := 11
var balance_cd := 0.0
var enemy_skill_mod := 0.0       # 敌队技能系数修正(胶带平衡:票差越大敌方越强)
var enemy_respawn_mod := 1.0     # 敌方重生延迟倍率

const CLASS_POOL := ["assault", "assault", "assault", "assault", "engineer", "engineer", "support", "support", "recon", "recon", "recon"]
const WEAPONS := {
	"assault": { "us": ["m4", "ak", "scar", "aug", "g36c", "famas"], "ru": ["ak", "ak", "scar", "aug", "ak74", "g3"] },
	"engineer": { "us": ["m249", "pkm", "rpd", "m60"], "ru": ["pkm", "rpd", "rpd", "mg42"] },
	"support": { "us": ["mp5", "ump", "p90", "vector"], "ru": ["mp5", "ump", "p90", "pp19"] },
	"recon": { "us": ["awm", "m24", "m24", "m110"], "ru": ["svd", "svd", "m24", "m40"] },
}


func reset(per_team := 11, ru_bonus := 1) -> void:
	# [BALANCE 8/10] ru_bonus:防守方(ru)相对进攻方(us)的兵力差。
	# 突破模式传负值削弱防守方(ru=us+ru_bonus),默认 +1 保持其他模式原样
	if OS.has_feature("web"):
		per_team = 6  # Web 端 AI 减半,大幅降低 CPU 开销
	base_per_team = per_team
	target_per_team = per_team
	enemy_skill_mod = 0.0
	enemy_respawn_mod = 1.0
	Bot._noise_log = []  # 换图:清空战场噪音日志,防止 AI 听到上一张图的枪声
	for b in bots:
		b.queue_free()
	bots = []
	G.bots = bots
	for i in per_team:
		var b := Bot.new("us")
		bots.append(b)
		G.main.add_child(b)
	for i in maxi(0, per_team + ru_bonus):
		var b := Bot.new("ru")
		bots.append(b)
		G.main.add_child(b)
	# 每局兵种/武器分布:按 CLASS_POOL 打乱后分配,保证突击/工程/支援/侦察齐全
	_assign_loadouts()
	_assign_skills()
	# 小队编制:每 4 人一队,玩家加入第一友军小队
	G.squads = []
	var sq_id := 0
	for team in ["us", "ru"]:
		var mates := bots.filter(func(b): return b.team == team)
		var i := 0
		while i < mates.size():
			var sq := { "id": sq_id, "team": team, "members": mates.slice(i, i + 4) }
			sq_id += 1
			for m in sq["members"]:
				m.squad_id = sq["id"]
			G.squads.append(sq)
			i += 4
	for s in G.squads:
		if s["team"] == G.player.team:
			G.player_squad = s
			break
	# 指派载具驾驶员(突破模式进攻方更多;BR 大地图远距进圈,每队 12 名驾驶员)
	var us_d := 0
	var ru_d := 0
	var need_us := 12 if G.mode == "br" else (4 if G.mode == "breakthrough" else 3)
	var need_ru := 12 if G.mode == "br" else 3
	for b in bots:
		if b.team == "us" and us_d < need_us:
			b.can_drive = true
			us_d += 1
		elif b.team == "ru" and ru_d < need_ru:
			b.can_drive = true
			ru_d += 1
	for b in bots:
		b.respawn_t = Utils.rand(0, 2)
		b.alive = false
		b.mesh.visible = false


## 每局兵种分布:池子洗牌保证各兵种齐全,武器随兵种+阵营随机
func _assign_loadouts() -> void:
	for team in ["us", "ru"]:
		var mates := bots.filter(func(b): return b.team == team)
		mates.shuffle()
		for i in mates.size():
			var cid: String = CLASS_POOL[i % CLASS_POOL.size()]
			var pool: Array = WEAPONS[cid][team]
			var wid: String = Utils.choice(pool)
			(mates[i] as Bot).apply_loadout(cid, wid)


## 技能系数:开局基线 ± 随机;胶带平衡由敌方修正项叠加
func _assign_skills() -> void:
	for b in bots:
		var base := 0.8 if b.team == "us" else 0.82
		b.skill = clampf(base + Utils.rand(-0.14, 0.14), 0.45, 1.1)


var _bot_sh_t := 0.0   # [8/10] bot 阴影分级节流计时
var _ai_dbg := false   # --ai-debug:头顶 AI 状态浮字(状态/任务/卡死阶段)
var _ai_dbg_t := 0.0


func _ready() -> void:
	_ai_dbg = OS.get_cmdline_user_args().has("--ai-debug")
	# AI 战场指挥层(4s 一拍:回防/支援/夺旗/推进/驻守任务分配)
	add_child(AIDirector.new())


## --ai-debug:每个存活 bot 头顶显示 AI 状态浮字(节流 0.3s)
func _update_ai_debug(dt: float) -> void:
	_ai_dbg_t -= dt
	if _ai_dbg_t > 0:
		return
	_ai_dbg_t = 0.3
	for b in bots:
		if b.mesh == null:
			continue
		var lbl: Label3D = b.mesh.get_node_or_null("AiDbg")
		if lbl == null:
			lbl = Label3D.new()
			lbl.name = "AiDbg"
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			lbl.pixel_size = 0.011
			lbl.font_size = 16
			lbl.position = Vector3(0, 2.45, 0)
			lbl.modulate = Color(0.35, 1.0, 0.65)
			b.mesh.add_child(lbl)
		if not b.alive:
			lbl.text = "DEAD"
			continue
		var t: Dictionary = G.ai_tasks.get(b.squad_id, {})
		var obj_s: String = ""
		if b.objective != null and is_instance_valid(b.objective):
			obj_s = str(b.objective.get("id", "?"))
		lbl.text = "S%d %s\nOBJ:%s %s\nSTK:%d" % [
			b.squad_id, b.state.to_upper(), t.get("kind", "-"), obj_s, b._stuck_phase]


func update_bots(dt: float) -> void:
	_update_balance(dt)
	if _ai_dbg:
		_update_ai_debug(dt)
	# [PERF-AUDIT] --noai 临时禁用 AI 更新(仅性能审计用,测量 AI 占 CPU 比例)
	if OS.get_cmdline_user_args().has("--noai"):
		return
	# [8/10] bot 阴影分级投射:>40m 关阴影(阴影 pass 提交大降,1%Low 波动消除;近处保留视觉)
	_bot_sh_t += dt
	if _bot_sh_t >= 0.5:
		_bot_sh_t = 0.0
		var p_pos: Vector3 = G.player.pos if (G.player != null) else Vector3.ZERO
		var has_p: bool = G.player != null
		for b in bots:
			if b.mesh == null:
				continue
			var near: bool = has_p and b.alive and b.pos.distance_to(p_pos) < 40.0
			var cur: bool = b.mesh.get_meta("sh_on", true)
			if cur != near:
				b.mesh.set_meta("sh_on", near)
				_set_shadow_recursive(b.mesh, near)
	for b in bots:
		if not b.alive:
			if b.mesh.visible:
				b.update_bot(dt)  # 死亡动画
			b.respawn_t -= dt
			# 实时 3D 战场部署(征服/突破):玩家死亡观察期间战场持续运转,AI 正常补充
			var battlefield_live: bool = G.deployment != null and G.deployment.active
			if b.respawn_t <= 0 and (G.state == "playing" or battlefield_live):
				if G.mode == "tdm":
					# TDM 契约:bot 死亡 2s 后从本队出生点复活(立即复活节奏)
					b.respawn_t = 2.0 + Utils.rand(0, 0.6)
				else:
					b.respawn_t = Utils.rand(4, 7) * (enemy_respawn_mod if b.team != (G.player.team if G.player != null else "us") else 1.0)
				G.game.spawn_actor(b)
			continue
		b.update_bot(dt)


## [PERF-AUDIT] 递归设置阴影投射(审计/分级用)
func _set_shadow_recursive(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in n.get_children():
		_set_shadow_recursive(ch, on)


## ==================== 动态平衡(12 秒一拍) ====================
func _update_balance(dt: float) -> void:
	balance_cd -= dt
	if balance_cd > 0:
		return
	balance_cd = 12.0
	if G.state != "playing" or G.player == null:
		return
	# 战役模式:敌人由战役控制器生成/补兵,票差胶带与 K/D 动态平衡均不适用
	if G.mode == "campaign":
		return
	# BR:固定 47×2 混战名单(无阵营/无重生),不适用票差胶带与动态增减
	if G.mode == "br":
		return
	# 突破模式票数天生不对称(攻 250/def ∞),票差胶带不适用,跳过
	if G.mode == "breakthrough":
		return
	# 票差胶带:我方大优 → 敌方变强/复活变快;我方大劣 → 敌方变弱
	var tdiff: float = G.tickets[G.player.team] - (G.tickets["ru"] if G.player.team == "us" else G.tickets["us"])
	if tdiff > 80:
		enemy_skill_mod = 0.15
		enemy_respawn_mod = 0.8
	elif tdiff > 30:
		enemy_skill_mod = 0.06
		enemy_respawn_mod = 0.92
	elif tdiff < -80:
		enemy_skill_mod = -0.12
		enemy_respawn_mod = 1.4
	elif tdiff < -30:
		enemy_skill_mod = -0.05
		enemy_respawn_mod = 1.2
	else:
		enemy_skill_mod = 0.0
		enemy_respawn_mod = 1.0
	# 玩家 K/D 窗口:表现越好敌方越多(上限 13/队),越差越少(下限 8/队)
	var kd := (float(G.stats.kills) + 1.0) / (float(G.stats.deaths) + 1.0)
	if kd > 2.2:
		target_per_team = base_per_team + 2
	elif kd > 1.4:
		target_per_team = base_per_team + 1
	elif kd < 0.25:
		target_per_team = base_per_team - 2
	elif kd < 0.45:
		target_per_team = base_per_team - 1
	else:
		target_per_team = base_per_team
	target_per_team = clampi(target_per_team, 8, 24)
	# 应用:每队数量对齐目标
	var p_team: String = G.player.team
	for team in ["us", "ru"]:
		var c := 0
		for b in bots:
			if b.team == team:
				c += 1
		if c < target_per_team:
			# 补员:生成新 bot 快速入场
			var cid: String = Utils.choice(CLASS_POOL)
			var nb := Bot.new(team)
			nb.apply_loadout(cid, Utils.choice(WEAPONS[cid][team]))
			nb.skill = clampf(0.8 + Utils.rand(-0.14, 0.14), 0.45, 1.1)
			bots.append(nb)
			G.bots = bots
			G.main.add_child(nb)
			nb.respawn_t = Utils.rand(1, 3)
			nb.alive = false
			nb.mesh.visible = false
		elif c > target_per_team:
			# 缩员:拉长已死 bot 的重生,自然减员
			var extra := c - target_per_team
			var cut := 0
			for b in bots:
				if cut >= extra:
					break
				if b.team == team and not b.alive:
					b.respawn_t = maxf(b.respawn_t, 9.0)
					cut += 1
	# 敌队技能基线随胶带调整(玩家队保持 0.8 基线,公平性)
	for b in bots:
		if b.team != p_team:
			b.skill = clampf(0.82 + enemy_skill_mod + Utils.rand(-0.1, 0.1), 0.45, 1.1)
