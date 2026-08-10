class_name GameMode_TDM extends GameMode_Portal
## 团队死斗(TDM)模式:蓝队(us,玩家方) VS 红队(ru)
## 规则:击杀+1 队伍分;10 秒内造成过伤害的队友记助攻;连杀(击杀间隔<5s)3+ 播报;
##      死亡 2 秒自动随机出生点复活;时间到(300s)或率先 50 击杀 → 结束;
##      结算含 MVP/TOP5/完整记分板/经验/武器XP/任务摘要。
## 依赖:G.player(玩家)/G.bot_manager / G.spawns / G.hud / G.game.spawn_actor / AudioSys / Utils / G.portal(PortalManager)
## 接线(架构 Agent):game.gd on_kill 处调 G.portal.active.on_player_killed(killer, victim, def, head);
##       bot.take_damage / player.damage 处调 G.portal.active.on_damage(attacker, victim, amount)(可选,用于助攻精确判定)
## 收尾:本模式组装 result 后调 G.portal.end_match(result)(PortalManager 负责结算屏/音频/状态清理)
## 契约说明:基类 game_mode_portal.gd 由架构/BR Agent 维护,本类按其最新契约适配:
##   on_player_killed(killer, victim, head) / on_damage(attacker, victim, amount) /
##   started 状态位 / score_changed(us, ru) / player_eliminated(受害名, 击杀者名, 爆头) /
##   mvp_changed(mvp 字典) / portal_hint(text)

const SCORE_LIMIT := 50           # 目标击杀数
const ASSIST_WINDOW := 10.0       # 助攻判定窗口(秒)
const STREAK_WINDOW := 5.0        # 连杀累计窗口(击杀间隔 < 5s)
const RESPAWN_DELAY := 2.0        # 死亡后自动复活延迟(秒)
const BOTS_PER_TEAM := 10         # bot_manager.reset(10):蓝 10 + 红 11(玩家补蓝队 → 实际 11v11)
const EXP_KILL := 10              # 经验:击杀
const EXP_ASSIST := 5             # 经验:助攻
const EXP_WIN := 200              # 经验:胜利
const EXP_MVP := 100              # 经验:全场最佳
const PROGRESS_PATH := "user://player_progress.cfg"

const PLAYER_KEY := "p"           # 玩家记分板键

var us_score := 0                 # 蓝队分(玩家方)
var ru_score := 0                 # 红队分
var ended := false                # 本局是否已结算
var reason := ""                  # 结束原因:score_limit | time_limit | ended
var _map_id := ""

# ---- 记分板:key -> { name, team, kills, deaths, assists, streak, streak_t, max_streak } ----
var _board := {}
# ---- 伤害表:victim_key -> { attacker_key -> { dmg, t } }(助攻判定,10s 窗口) ----
var _dmg := {}
# ---- 经验/武器XP(内存累计,结算落盘) ----
var _exp := { "kill": 0, "assist": 0, "win": 0, "mvp": 0 }
var _wxp := {}                    # weapon_id -> xp
var _player_max_streak := 0
var _player_assists := 0
# ---- 流程状态 ----
var _player_respawn_t := -1.0
var _dmg_cleanup_t := 0.0
var _mvp_t := 0.0
var _last_mvp_key := ""
var _first_blood := false
var _last_clock_s := -1


# ==================== 通用辅助 ====================

func _hud():
	if G.hud != null and is_instance_valid(G.hud):
		return G.hud
	return null


func _key_of(actor) -> String:
	if actor == null:
		return ""
	if actor is Object and is_same(actor, G.player):
		return PLAYER_KEY
	var id = actor.get("id") if actor.get("id") != null else null
	if id != null:
		return "b" + str(id)
	return "a" + str(actor.get_instance_id())


func _name_of(actor) -> String:
	if actor == null:
		return "战场"
	return Bot.display_name(actor, "士兵")


func _team_of(actor) -> String:
	if actor == null:
		return ""
	var t = actor.get("team")
	return str(t) if t != null else ""


func _is_player(actor) -> bool:
	return actor != null and actor is Object and is_same(actor, G.player)


## 取/建记分板条目(不存在则惰性创建,兼容对局中动态补充的 bot)
func _entry(key: String, actor) -> Dictionary:
	var e = _board.get(key)
	if e == null:
		e = {
			"key": key, "name": _name_of(actor), "team": _team_of(actor),
			"kills": 0, "deaths": 0, "assists": 0,
			"streak": 0, "streak_t": -99.0, "max_streak": 0,
		}
		_board[key] = e
	return e


func _weapon_id_of_player() -> String:
	var p = G.player
	if p == null:
		return ""
	var gun = p.get("gun") if p.get("gun") != null else null
	if gun != null and is_instance_valid(gun) and gun.get("id") != null:
		var wid = gun.get("id")
		if wid != null and str(wid) != "":
			return str(wid)
	var lo = p.get("loadout")
	if lo != null and lo is Dictionary:
		var w = lo.get("primary")
		if w != null:
			return str(w)
	return ""


## PortalManager 存在时走其提示通道(portal_hint → G.hud.hint)
func _portal_hint(text: String) -> void:
	portal_hint.emit(text)


## 当前全场最佳(KD 优先 → 击杀 → 助攻)
func _compute_mvp() -> Dictionary:
	var best: Dictionary = {}
	var best_kd := -1.0
	var best_kills := -1
	var best_assists := -1
	for key in _board:
		var e: Dictionary = _board[key]
		var kd: float = float(e["kills"]) / maxf(1.0, float(e["deaths"]))
		if kd > best_kd or (is_equal_approx(kd, best_kd) and int(e["kills"]) > best_kills) \
				or (is_equal_approx(kd, best_kd) and int(e["kills"]) == best_kills and int(e["assists"]) > best_assists):
			best = e
			best_kd = kd
			best_kills = int(e["kills"])
			best_assists = int(e["assists"])
	if best.is_empty():
		return { "name": "-", "team": "us", "kills": 0, "deaths": 0, "assists": 0, "kd": 0.0 }
	return {
		"key": best["key"], "name": best["name"], "team": best["team"],
		"kills": int(best["kills"]), "deaths": int(best["deaths"]),
		"assists": int(best["assists"]),
		"kd": float(best["kills"]) / maxf(1.0, float(best["deaths"])),
	}


# ==================== 生命周期(契约) ====================

func start(map_id: String = "") -> void:
	G.mode = "tdm"
	mode_name = "tdm"
	time_limit = 300.0
	round_time = 0.0
	started = true
	ended = false
	reason = ""
	_map_id = map_id
	us_score = 0
	ru_score = 0
	_board.clear()
	_dmg.clear()
	_exp = { "kill": 0, "assist": 0, "win": 0, "mvp": 0 }
	_wxp.clear()
	_player_max_streak = 0
	_player_assists = 0
	_player_respawn_t = -1.0
	_dmg_cleanup_t = 0.0
	_mvp_t = 0.0
	_last_mvp_key = ""
	_first_blood = false
	_last_clock_s = -1
	# 队伍:玩家加入蓝队;bot 由 bot_manager 按队分配(10v10 + 玩家补蓝 = 11v11)
	if G.player != null:
		G.player.team = "us"
		# TDM 装备:装备屏所选主副武器(任意武器/不限兵种)→ spawn 时 give_class 装配
		_apply_tdm_loadout()
	var bm = G.bot_manager
	if bm != null and is_instance_valid(bm):
		bm.reset(BOTS_PER_TEAM)
	# 顶部票数条直接显示队伍分(征服用兵力条,复用无需改 HUD)
	G.tickets = { "us": 0, "ru": 0 }
	# HUD 目标击杀/倒计时镜像(PortalManager 只读字段;hud.gd 缺省 50/300 双保险)
	var pm0: Variant = G.get("portal")
	if pm0 != null:
		pm0.set("tdm_target", SCORE_LIMIT)
		pm0.set("tdm_time_left", time_limit)
	# 玩家出生(菜单流首进无 deploy 屏;与 BR 同款写法:未存活则走 game.spawn_actor,
	# 出生点由 spawn_actor 按己方阵营取 G.spawns["us"] 随机)
	if G.player != null and not G.player.alive:
		G.game.spawn_actor(G.player)
	print("[TDM] start map=%s 10v10(bot) 蓝=us/红=ru 目标=%d 时限=%.0fs" % [map_id, SCORE_LIMIT, time_limit])


## TDM 装备应用:读 menus.tdm_loadout(主/副任意武器;rpg 火箭筒为技能武器不入池)。
## 兵种固定为 assault(无兵种技能:use_gadget 已门控;RPG/随身霰弹槽位不追加,只带所选两把)。
## 复活路径(player.spawn → give_class(class_id, loadout))沿用 player.loadout,无需重复应用。
func _apply_tdm_loadout() -> void:
	var p = G.player
	if p == null or not is_instance_valid(p):
		return
	var lo := { "primary": "m4", "secondary": "m1911", "shotgun": null }
	if G.menus != null and is_instance_valid(G.menus):
		var sel: Variant = G.menus.get("tdm_loadout")
		if sel is Dictionary:
			for slot in ["primary", "secondary"]:
				var wid: Variant = sel.get(slot)
				if wid is String and WeaponsData.W().has(wid):
					lo[slot] = wid
	p.class_id = "assault"
	p.loadout = lo
	print("[TDM-W] loadout applied primary=%s secondary=%s" % [lo["primary"], lo["secondary"]])


func tick(dt: float) -> void:
	if not started or ended:
		return
	round_time += dt
	# 玩家 2 秒自动复活(蓝队出生点随机)
	if _player_respawn_t >= 0.0:
		_player_respawn_t -= dt
		if _player_respawn_t <= 0.0:
			_player_respawn_t = -1.0
			_auto_respawn_player()
	# 助攻窗口清理(1s 一拍,O(n))
	_dmg_cleanup_t += dt
	if _dmg_cleanup_t >= 1.0:
		_dmg_cleanup_t = 0.0
		_prune_damage()
	# MVP 刷新(1s 一拍,MVP 变化时发信号)
	_mvp_t += dt
	if _mvp_t >= 1.0:
		_mvp_t = 0.0
		_refresh_mvp_signal()
	# 时间到 → 按当前比分判定
	if round_time >= time_limit:
		_end_match(us_score > ru_score, "time_limit")
		return
	# HUD 剩余时间(比分未变时按秒转发,供 HUD 显示倒计时;击杀时已即时转发)
	var clock_s := int(round_time)
	if clock_s != _last_clock_s:
		_last_clock_s = clock_s
		score_changed.emit(us_score, ru_score)
		var pm1: Variant = G.get("portal")
		if pm1 != null:
			pm1.set("tdm_time_left", maxf(0.0, time_limit - round_time))


## 击杀注册(game.gd on_kill → PortalManager 转发;head 是否爆头)
func on_player_killed(killer, victim, head := false) -> void:
	if not started or ended:
		return
	if victim == null:
		return
	var v_key: String = _key_of(victim)
	if v_key == "":
		return
	var v_entry: Dictionary = _entry(v_key, victim)
	v_entry["deaths"] = int(v_entry["deaths"]) + 1
	v_entry["streak"] = 0  # 死亡清零连杀
	# 玩家死亡 → 排定 2 秒自动复活
	if _is_player(victim):
		_player_respawn_t = RESPAWN_DELAY
	var k_key: String = _key_of(killer)
	var k_team: String = _team_of(killer)
	var v_team: String = _team_of(victim)
	var scored := false
	# 击杀者记分(自伤/同队不计分;环境击杀无阵营不计分)
	if k_key != "" and killer != null and not is_same(killer, victim) \
			and k_team != "" and k_team != v_team:
		var k_entry: Dictionary = _entry(k_key, killer)
		k_entry["kills"] = int(k_entry["kills"]) + 1
		_update_streak(k_entry)
		# 击杀视为一次伤害(兜底:即使 on_damage 未接线,击杀者的助攻表也有记录)
		_register_damage(killer, victim, 1.0)
		scored = true
		if k_team == "us":
			us_score += 1
			G.tickets["us"] = us_score
		else:
			ru_score += 1
			G.tickets["ru"] = ru_score
		# 玩家击杀:经验 + 武器 XP + 连杀播报
		if _is_player(killer):
			_exp["kill"] += EXP_KILL
			var wid := _weapon_id_of_player()
			if wid != "":
				_wxp[wid] = int(_wxp.get(wid, 0)) + 10
			_hud_announce_streak(k_entry)
		# 连杀 3+:播报 + MVP 信号(不限玩家,含 bot)
		if int(k_entry["streak"]) >= 3 and int(k_entry["streak"]) % 2 == 1:
			_announce("连杀 ×" + str(k_entry["streak"]) + " — " + str(k_entry["name"]), true)
			_refresh_mvp_signal(true)
	# 首杀播报
	if not _first_blood and k_team != "" and scored:
		_first_blood = true
		_announce("首杀 — " + _name_of(killer) + "!", false)
	# 助攻:击杀者 10 秒内造成过伤害的队友
	var assists: Array = _assist_keys(killer, victim)
	for a_key in assists:
		var a_rec: Dictionary = _dmg.get(v_key, {}).get(a_key, {})
		var a_entry: Dictionary = _entry(a_key, null)
		a_entry["name"] = str(a_rec.get("name", a_entry["name"]))
		a_entry["team"] = str(a_rec.get("team", a_entry["team"]))
		a_entry["assists"] = int(a_entry["assists"]) + 1
		var hud = _hud()
		if hud != null:
			hud.add_killfeed(str(a_entry["name"]), str(a_entry["team"]),
				str(v_entry["name"]), v_team, "助攻", false, a_key == PLAYER_KEY)
		if a_key == PLAYER_KEY:
			_exp["assist"] += EXP_ASSIST
			_player_assists += 1
	# 信号:比分 / 淘汰(名字契约:受害名/击杀者名/爆头;PortalManager 以 3 参转发统计)
	score_changed.emit(us_score, ru_score)
	player_eliminated.emit(str(_name_of(victim)), str(_name_of(killer)), head)
	# 目标击杀数判定
	if us_score >= SCORE_LIMIT or ru_score >= SCORE_LIMIT:
		_end_match(us_score >= SCORE_LIMIT, "score_limit")


## 伤害登记(bot.take_damage / player.damage 由架构 Agent 接线调用;未接线时击杀兜底 1 点伤害)
func on_damage(attacker, victim, amount: float) -> void:
	if not started or ended or victim == null or attacker == null:
		return
	if amount <= 0.0:
		return
	_register_damage(attacker, victim, amount)


func end() -> void:
	if not started or ended:
		return
	var win := us_score > ru_score
	if us_score == ru_score:
		# 平分时以 MVP 阵营判胜;空记分板(0-0 强停)不得判定胜方,防伪胜场/伪经验
		var m: Dictionary = _compute_mvp()
		win = m.get("team", "") == "us" and m.get("key", "") != ""
	_end_match(win, "ended")


# ==================== 助攻 ====================

func _register_damage(attacker, victim, amount: float) -> void:
	var v_key: String = _key_of(victim)
	var a_key: String = _key_of(attacker)
	if v_key == "" or a_key == "":
		return
	var row = _dmg.get(v_key)
	if row == null:
		row = {}
		_dmg[v_key] = row
	var rec = row.get(a_key)
	if rec == null:
		rec = { "dmg": 0.0, "t": round_time, "team": _team_of(attacker), "name": _name_of(attacker) }
		row[a_key] = rec
	rec["dmg"] = float(rec["dmg"]) + amount
	rec["t"] = round_time
	rec["team"] = _team_of(attacker)


## 击杀者的队友(同队、非击杀者、窗口内造成过伤害)
func _assist_keys(killer, victim) -> Array:
	var v_key: String = _key_of(victim)
	if v_key == "":
		return []
	var k_team: String = _team_of(killer)
	if k_team == "":
		return []
	var k_key: String = _key_of(killer)
	var row: Dictionary = _dmg.get(v_key, {})
	var out: Array = []
	for a_key in row:
		if a_key == k_key or a_key == "":
			continue
		var rec: Dictionary = row[a_key]
		if str(rec.get("team", "")) != k_team:
			continue
		if round_time - float(rec["t"]) <= ASSIST_WINDOW:
			out.append(a_key)
	return out


func _prune_damage() -> void:
	var cutoff := round_time - ASSIST_WINDOW
	for v_key in _dmg.keys():
		var row: Dictionary = _dmg[v_key]
		var alive_keys: Array = []
		for a_key in row:
			if float(row[a_key]["t"]) >= cutoff:
				alive_keys.append(a_key)
		if alive_keys.is_empty():
			_dmg.erase(v_key)
		else:
			var new_row := {}
			for a_key in alive_keys:
				new_row[a_key] = row[a_key]
			_dmg[v_key] = new_row


# ==================== 连杀 / 播报 ====================

func _update_streak(e: Dictionary) -> void:
	if round_time - float(e["streak_t"]) <= STREAK_WINDOW:
		e["streak"] = int(e["streak"]) + 1
	else:
		e["streak"] = 1
	e["streak_t"] = round_time
	e["max_streak"] = maxi(int(e["max_streak"]), int(e["streak"]))
	if e["key"] == PLAYER_KEY:
		_player_max_streak = maxi(_player_max_streak, int(e["streak"]))


func _hud_announce_streak(e: Dictionary) -> void:
	if int(e["streak"]) < 2:
		return
	var hud = _hud()
	if hud != null:
		hud.banner("连杀 ×" + str(e["streak"]) + " — " + str(e["name"]))
	_portal_hint("连杀 ×" + str(e["streak"]) + " — " + str(e["name"]))
	if AudioSys != null:
		AudioSys.kill_confirm(int(e["streak"]) % 3 == 0)


## 播报:战斗广播音效组合(kill/capture 系)+ HUD 文字(audio/voice 仅有战役台词,无 TDM 语音,见报告)
func _announce(text: String, good: bool) -> void:
	var hud = _hud()
	if hud != null:
		hud.banner(text, not good)
	_portal_hint(text)
	if AudioSys != null:
		AudioSys.capture(good)
		AudioSys.kill_confirm(good)


func _refresh_mvp_signal(force := false) -> void:
	var mvp: Dictionary = _compute_mvp()
	var m_key: String = str(mvp.get("key", ""))
	if force or m_key != _last_mvp_key:
		_last_mvp_key = m_key
		mvp_changed.emit(mvp)


# ==================== 复活 ====================

func _auto_respawn_player() -> void:
	if G.state != "dead":
		return
	var p = G.player
	if p == null or not is_instance_valid(p):
		return
	# 蓝队随机出生点(地图 Agent 提供 G.spawns["us"];缺省交给 game.spawn_actor 兜底)
	var spots: Array = G.spawns.get("us", []) if G.spawns != null else []
	var pos = Utils.choice(spots) if not spots.is_empty() else null
	if pos != null:
		p.spawn(pos)
	elif G.game != null and is_instance_valid(G.game):
		G.game.spawn_actor(p)
	print("[TDM] 玩家自动复活 @%.1fs" % round_time)
	G.state = "playing"
	var hud = _hud()
	if hud != null:
		hud.hide_screen("death")
		hud.show_screen("hud")
	if G.input_sys != null:
		G.input_sys.lock()
	if AudioSys != null:
		AudioSys.deploy_sting()


# ==================== 结算 ====================

func _end_match(win: bool, why: String) -> void:
	if ended:
		return
	ended = true
	started = false
	reason = why
	_prune_damage()
	# ---- 结算数据 ----
	var mvp: Dictionary = _compute_mvp()
	if win:
		_exp["win"] += EXP_WIN
	if mvp.get("key", "") == PLAYER_KEY:
		_exp["mvp"] += EXP_MVP
	var top: Array = _board.values()
	top.sort_custom(func(a, b):
		var ka: int = int(a["kills"]); var kb: int = int(b["kills"])
		if ka != kb:
			return ka > kb
		var da: float = float(a["deaths"]); var db: float = float(b["deaths"])
		if da != db:
			return da < db
		return int(a["assists"]) > int(b["assists"]))
	var top_players: Array = []
	for i in mini(5, top.size()):
		var e: Dictionary = top[i]
		top_players.append({
			"name": e["name"], "team": e["team"], "kills": int(e["kills"]),
			"deaths": int(e["deaths"]), "assists": int(e["assists"]),
			"kd": float(e["kills"]) / maxf(1.0, float(e["deaths"])),
		})
	var scoreboard: Array = []
	for e in _board.values():
		scoreboard.append({
			"name": e["name"], "team": e["team"], "kills": int(e["kills"]),
			"deaths": int(e["deaths"]), "assists": int(e["assists"]),
			"max_streak": int(e["max_streak"]), "me": e["key"] == PLAYER_KEY,
		})
	var p_kills := 0
	var p_deaths := 0
	if _board.has(PLAYER_KEY):
		p_kills = int(_board[PLAYER_KEY]["kills"])
		p_deaths = int(_board[PLAYER_KEY]["deaths"])
	# ---- 经验落盘(user://player_progress.cfg) ----
	var exp_earned: int = _exp["kill"] + _exp["assist"] + _exp["win"] + _exp["mvp"]
	var saved := _save_progress(exp_earned, _wxp, win)
	# ---- 任务摘要 ----
	var tasks: Array = [
		{ "id": "win", "name": "赢得比赛", "done": win, "goal": 1, "value": 1 if win else 0 },
		{ "id": "kills_15", "name": "单局击杀 15", "done": p_kills >= 15, "goal": 15, "value": p_kills },
		{ "id": "streak_3", "name": "达成连杀 3", "done": _player_max_streak >= 3, "goal": 3, "value": _player_max_streak },
		{ "id": "mvp", "name": "全场最佳", "done": mvp.get("key", "") == PLAYER_KEY, "goal": 1, "value": 1 if mvp.get("key", "") == PLAYER_KEY else 0 },
	]
	var result := {
		"mode": "tdm", "map_id": _map_id, "win": win, "reason": reason,
		"winner_team": "us" if win else ("ru" if not win else "draw"),
		"scores": { "us": us_score, "ru": ru_score },
		"us_score": us_score, "ru_score": ru_score, "time": round_time,
		"my_stats": { "kills": p_kills, "deaths": p_deaths, "assists": _player_assists,
			"max_streak": _player_max_streak, "kd": float(p_kills) / maxf(1.0, float(p_deaths)) },
		"mvp": mvp, "top_players": top_players, "scoreboard": scoreboard,
		"player_stats": _player_stats_dict(scoreboard),
		"tasks": tasks,
		"exp": { "earned": exp_earned, "total": int(saved["exp"]), "level": int(saved["level"]),
			"level_xp": int(saved["level_xp"]),
			"breakdown": { "kill": _exp["kill"], "assist": _exp["assist"], "win": _exp["win"], "mvp": _exp["mvp"] } },
		"weapon_xp": _wxp.duplicate(),
	}
	# ---- 收尾:PortalManager 存在时交给它(结算屏/音频/状态由它统一处理);缺省自收尾(测试/独立运行) ----
	var pm = G.get("portal")
	if pm != null and is_instance_valid(pm):
		pm.end_match(result)
	else:
		G.tickets = { "us": us_score, "ru": ru_score }
		G.state = "over"
		if G.input_sys != null:
			G.input_sys.unlock()
		var hud = _hud()
		if hud != null:
			hud.hide_screen("hud")
			hud.hide_screen("death")
			hud.hide_screen("deploy")
			hud.show_end(win)
		if AudioSys != null:
			if win:
				AudioSys.win()
			else:
				AudioSys.lose()
	print("[TDM] round_ended win=%s reason=%s us=%d ru=%d mvp=%s exp=%d" % [win, reason, us_score, ru_score, str(mvp.get("name", "-")), exp_earned])
	round_ended.emit(result)


## 按 PortalManager 约定生成 player_stats:{ 名字: { kills, deaths, assists } }
func _player_stats_dict(scoreboard: Array) -> Dictionary:
	var out := {}
	for e in scoreboard:
		out[str(e["name"])] = {
			"kills": int(e["kills"]), "deaths": int(e["deaths"]), "assists": int(e["assists"]),
		}
	return out


# ==================== 经验 / 武器 XP 存档(user://player_progress.cfg) ====================

## 读档:返回 { "exp": int, "level": int, "level_xp": int, "matches": int, "wins": int, "weapon_xp": {} }
func load_progress() -> Dictionary:
	var cf := ConfigFile.new()
	var out := { "exp": 0, "level": 1, "level_xp": 0, "matches": 0, "wins": 0, "weapon_xp": {} }
	if cf.load(PROGRESS_PATH) == OK:
		out["exp"] = int(cf.get_value("progress", "exp", 0))
		out["matches"] = int(cf.get_value("stats", "matches", 0))
		out["wins"] = int(cf.get_value("stats", "wins", 0))
		for wid in cf.get_section_keys("weapons"):
			out["weapon_xp"][wid] = int(cf.get_value("weapons", wid, 0))
	out["level"] = 1 + int(out["exp"] / 100)
	out["level_xp"] = int(out["exp"]) % 100
	return out


## 写档:累计经验/胜场/对局数与武器 XP,返回写后总览(同上结构)
func _save_progress(exp_gain: int, weapon_xp: Dictionary, win: bool) -> Dictionary:
	var cur := load_progress()
	var cf := ConfigFile.new()
	cf.load(PROGRESS_PATH)
	var total: int = int(cur["exp"]) + exp_gain
	cf.set_value("progress", "exp", total)
	cf.set_value("stats", "matches", int(cur["matches"]) + 1)
	cf.set_value("stats", "wins", int(cur["wins"]) + (1 if win else 0))
	var merged := {}
	for wid in cur["weapon_xp"]:
		merged[str(wid)] = int(cur["weapon_xp"][wid])
	for wid in weapon_xp:
		merged[str(wid)] = int(merged.get(str(wid), 0)) + int(weapon_xp[wid])
	for wid in merged:
		cf.set_value("weapons", str(wid), int(merged[wid]))
	cf.save(PROGRESS_PATH)
	cur["exp"] = total
	cur["level"] = 1 + int(total / 100)
	cur["level_xp"] = total % 100
	cur["matches"] = int(cur["matches"]) + 1
	cur["wins"] = int(cur["wins"]) + (1 if win else 0)
	return cur
