class_name CampaignData
## 战役模式章节数据(零度行动):6 章剧情、目标、敌军强度与出生点定义
## 剧情原创:边境联军遭"白狼佣兵团"突袭,雪豹小队队长曹锐率队夺回六处要地
## 字段:title=第X章,cn=章名,tagline=中文副题,sub=英文副题
## cutscene:title_card=标题卡,intro/outro=过场台词(与 flyover 飞越同步),objective_names=目标点名卡
## briefing/epilogue 与 cutscene.intro/outro 同内容,供旧状态机兼容播放;新增字段另加

## 全战役统一角色表(含敌对角色,供 HUD 台词着色/点名)
static func chars() -> Array:
	return [
		{ "id": "caorui", "name": "曹锐", "role": "雪豹小队队长 · 突击兵(主角)", "color": Color(1.0, 0.85, 0.45) },
		{ "id": "linxue", "name": "林雪", "role": "医疗兵", "color": Color(0.55, 0.9, 0.6) },
		{ "id": "laozhou", "name": "老周", "role": "狙击手 · 老兵", "color": Color(0.7, 0.8, 0.95) },
		{ "id": "tiezhu", "name": "铁柱", "role": "工程兵", "color": Color(0.95, 0.7, 0.4) },
		{ "id": "suya", "name": "苏雅", "role": "通信员 · 指挥部联络", "color": Color(0.5, 0.85, 1.0) },
		{ "id": "chen", "name": "陈振国上校", "role": "战区指挥官 · 无线电", "color": Color(0.95, 0.93, 0.8) },
		{ "id": "white_wolf", "name": "白狼", "role": "佣兵团首领 · 敌对目标", "color": Color(0.95, 0.4, 0.35) },
	]


## 简报台词 = 过场 intro 同内容(去 dur),供旧 briefing/epilogue 状态机兼容播放
static func _strip_dur(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		out.append({ "name": l["name"], "text": l["text"] })
	return out


## 四人小队默认编制(每章可覆盖;队友与玩家共同构成"雪豹小队"):
## 林雪-医疗(support/mp5) 老周-狙击(recon/m24) 铁柱-工程(engineer/pkm)
static func squad() -> Array:
	return [
		{ "id": "linxue", "name": "林雪", "role": "support", "weapon": "mp5", "skill": 0.88 },
		{ "id": "laozhou", "name": "老周", "role": "recon", "weapon": "m24", "skill": 0.95 },
		{ "id": "tiezhu", "name": "铁柱", "role": "engineer", "weapon": "pkm", "skill": 0.85 },
	]


static func chapters() -> Array[Dictionary]:
	var C := chars()
	var out: Array[Dictionary] = []
	out.append({
		"id": "c1",
		"title": "第一章",
		"cn": "夺路",
		"tagline": "突入沦陷城市街区",
		"sub": "Streets of Ashes",
		"map": "city",
		"map_cn": "边境城区",
		"chars": C,
		"squad": squad(),
		"cutscene": {
			"title_card": "第一章 · 夺路",
			"flyover": [
				{ "pos": Vector3(0, 45, -138), "look": Vector3(0, 0, -80), "dur": 3.4 },
				{ "pos": Vector3(-60, 70, -120), "look": Vector3(-80, 0, -80), "dur": 3.2 },
				{ "pos": Vector3(-90, 85, -70), "look": Vector3(-60, 0, -20), "dur": 3.4 },
				{ "pos": Vector3(-20, 100, -20), "look": Vector3(0, 0, 0), "dur": 3.6 },
				{ "pos": Vector3(30, 70, 40), "look": Vector3(0, 0, 10), "dur": 3.4 },
			],
			"intro": [
				{ "name": "陈振国上校", "text": "零度行动开始。白狼一夜扫平边境六处要地——你们脚下的街区,是最后一块。夺回来,城就回来了。", "dur": 3.6 },
				{ "name": "苏雅", "text": "链路恢复。路口有火力点,主街沿线都有伏击位,别走直线,听我实时播报。", "dur": 3.2 },
				{ "name": "白狼", "text": "齐万里在首哨把命留给了我们。雪豹小队,想听他的遗言,就到主街来。", "dur": 3.4 },
				{ "name": "曹锐", "text": "……齐排长的遗言,我自己去听。铁柱、林雪,主街跟我;老周,高点,把路口清出来。", "dur": 3.4 },
				{ "name": "老周", "text": "风不大,视野正好。队长,别让他牵着走——我们打我们的。", "dur": 3.0 },
			],
			"outro": [
				{ "name": "林雪", "text": "街区肃清,无平民滞留。白狼撤得很干净,把能搬的都搬空了。", "dur": 3.6 },
				{ "name": "苏雅", "text": "他留了段电文:『这是开场,不是尾声。』信号是跳频的,追不到。", "dur": 3.4 },
				{ "name": "陈振国上校", "text": "夺路完成。城空的账先记下——雪豹小队,向沙漠油站机动,补给队随后到。", "dur": 3.6 },
				{ "name": "曹锐", "text": "他炸得掉城,炸不掉家。走,一处处夺回来。", "dur": 3.0 },
			],
			"objective_names": ["爆破破门", "肃清西区路口", "坚守中心广场"],
		},
		"briefing": [],
		"epilogue": [],
		"objectives": [
			# 可达性:封锁带东翼 x∈[27,41] / 西翼 x∈[-41,-27] / 北端 z∈[108,112];主街走廊 x∈[-27,27] 全程可达
			# interact 破门点 (-80,-80) 在西区路口缺口 z∈(-89,-41) 内,距最近封锁带(西翼南段 z=-89 缘)9m ≥8m 余量
			{ "type": "interact", "pos": Vector3(-80, 0, -80), "radius": 5.0, "time": 2.5, "kind": "breach",
				"label": "爆破破门", "desc": "爆破西区路口的路障,打开中央大道通道" },
			# 可达性:西区路口检查站 + 主街走廊 x∈[-27,27] 均可交战
			{ "type": "kill", "count": 12, "desc": "肃清西区路口的敌军" },
			# 可达性:hold 区 x∈[-16,16],z∈[-16,16] 全部在主街走廊内,与封锁带零重叠
			{ "type": "hold", "pos": Vector3(0, 0, 0), "radius": 16.0, "time": 20.0, "desc": "坚守中心广场 20 秒" },
		],
		"enemy_total": 22,
		"enemy_cap": 8,
		"enemy_skill": 0.55,
		"player_deaths_limit": 6,
		"start_pos": Vector3(0, 0, -130),
		"start_yaw": 0.0,
		"spawn_anchors": [Vector3(0, 0, -90), Vector3(-50, 0, -80), Vector3(16, 0, -60)],
		# 线性关卡化·封锁带 {x,z,w,d,h,kind}:把城区收窄为"南街→西区路口→中心广场"线形走廊
		#   东翼封锁:封死中央大道东侧整片街区,只能沿 x∈[-27,27] 大道北进
		#   西翼南/北段:只留 z=-80 主街(西区路口)通道,其余西翼街区封死
		#   北端封口:中心广场(hold)后方大道截断,防绕行广场北侧空区
		"blockers": [
			{ "x": 34.0, "z": 0.0, "w": 14.0, "d": 298.0, "kind": "rubble" },   # 东翼封锁带:中央大道东侧全线(与楼群/坠机重叠成封口)
			{ "x": -34.0, "z": -119.0, "w": 14.0, "d": 60.0, "kind": "rubble" }, # 西翼南段:西区路口(z=-80 主街)以南封死
			{ "x": -34.0, "z": 39.0, "w": 14.0, "d": 220.0, "kind": "rubble" },  # 西翼北段:西区路口以北(留 9m 通道余量)
			{ "x": 0.0, "z": 110.0, "w": 50.0, "d": 4.0, "kind": "wall" },       # 北端封口:中心广场后方大道截断
		],
		# 线性关卡化·路线引导:出生点→中央大道→西区路口(全部落在封锁后走廊内)
		"path": [
			Vector3(0, 0, -95), Vector3(0, 0, -55), Vector3(-70, 0, -80),
		],
		"mid_lines": [
			{ "name": "老周", "text": "路口清了一半,火力点都在后撤,别追太深,留人盯主街。", "dur": 3.2 },
			{ "name": "林雪", "text": "负伤的往我这边靠,医疗包管够。", "dur": 2.6 },
			{ "name": "苏雅", "text": "西区路口守敌折损过半,广场方向有增援,小心身后。", "dur": 3.2 },
		],
		"finish_lines": [
			{ "name": "曹锐", "text": "路通了,老周,高点把路口清出来!", "dur": 2.8 },
			{ "name": "铁柱", "text": "检查站到手,广场方向没有重火力,走!", "dur": 2.8 },
		],
	})
	out[0]["briefing"] = _strip_dur(out[0]["cutscene"]["intro"])
	out[0]["epilogue"] = _strip_dur(out[0]["cutscene"]["outro"])
	out.append({
		"id": "c2",
		"title": "第二章",
		"cn": "燃点",
		"tagline": "夺回油料补给站",
		"sub": "Ignition",
		"map": "desert",
		"map_cn": "沙漠油站",
		"chars": C,
		"squad": squad(),
		"cutscene": {
			"title_card": "第二章 · 燃点",
			"flyover": [
				{ "pos": Vector3(0, 40, -138), "look": Vector3(0, 0, -40), "dur": 3.2 },
				{ "pos": Vector3(-40, 60, -80), "look": Vector3(0, 0, -20), "dur": 3.4 },
				{ "pos": Vector3(-20, 75, -30), "look": Vector3(0, 0, 0), "dur": 3.6 },
				{ "pos": Vector3(10, 90, 30), "look": Vector3(0, 0, 60), "dur": 3.2 },
				{ "pos": Vector3(-30, 70, 95), "look": Vector3(0, 0, 80), "dur": 3.4 },
			],
			"intro": [
				{ "name": "陈振国上校", "text": "白狼在油站布了爆破网,要炸掉整座油库。补给线断三个月,前线的仗就不用打了。", "dur": 3.6 },
				{ "name": "苏雅", "text": "无人机侦察:外围四座机枪台,雷区在输油管线两侧,站内有布防小组,人数不明。", "dur": 3.4 },
				{ "name": "曹锐", "text": "铁柱,爆破网怎么拆,你最有数。", "dur": 2.8 },
				{ "name": "铁柱", "text": "他们埋得快,接线图八成在站长室。先进站抢图纸,再拆雷,一锅端。", "dur": 3.2 },
				{ "name": "曹锐", "text": "老周,机枪台点掉;林雪跟我进站。苏雅,全程报数,听我口令断站区电。", "dur": 3.2 },
			],
			"outro": [
				{ "name": "铁柱", "text": "爆破网全拆,一根引线没剩。图纸还顺出两张——他们布的不止这一座站。", "dur": 3.6 },
				{ "name": "苏雅", "text": "图纸解析完成:六处要地都有兵力表,还多了一支预备队,代号『北翼』,正往雪山方向集结。", "dur": 3.8 },
				{ "name": "陈振国上校", "text": "补给线通了。『北翼』……雪山哨站的侦察班正在追它,信号三小时前断了。", "dur": 3.6 },
				{ "name": "曹锐", "text": "侦察班,是老周送过去的那支?", "dur": 2.6 },
				{ "name": "老周", "text": "……是我送他们去的。队我来带,人我去接。", "dur": 3.0 },
			],
			"objective_names": ["爆破主站大门", "摧毁引爆油桶", "呼叫指挥部", "控制北区油库"],
		},
		"briefing": [],
		"epilogue": [],
		"objectives": [
			# 可达性:封锁带东西翼 x∈±[27,35] / 北端 z∈[103,107];中轴走廊 x∈[-27,27] 全程可达
			# interact 点距两侧封锁带 ≥27m、距北端封口 ≥103m,余量充足
			{ "type": "interact", "pos": Vector3(0, 0, 0), "radius": 5.0, "time": 3.0, "kind": "breach",
				"label": "爆破突入", "desc": "爆破主站大门,突入沙漠油站" },
			# 可达性:破坏物撒点 x∈[-9,9],z∈[-9,9] 在中轴走廊内;hold 区 (0,80)±16 → z∈[64,96] < 北端封口 z=103
			{ "type": "destroy", "count": 4, "pos": Vector3(0, 0, 0), "spread": 9.0, "desc": "摧毁站区布设的引爆油桶" },
			# 可达性:呼叫点 (0,12) 在中轴走廊内(主站北侧)
			{ "type": "interact", "pos": Vector3(0, 0, 12), "radius": 5.0, "time": 3.0, "kind": "radio",
				"label": "接通指挥部电台", "desc": "呼叫指挥部,部署工兵接管油站" },
			{ "type": "hold", "pos": Vector3(0, 0, 80), "radius": 16.0, "time": 18.0, "desc": "占领北区储油库 18 秒,守住补给线" },
		],
		"enemy_total": 26,
		"enemy_cap": 9,
		"enemy_skill": 0.6,
		"player_deaths_limit": 5,
		"start_pos": Vector3(0, 0, -130),
		"start_yaw": 0.0,
		"spawn_anchors": [Vector3(0, 0, -70), Vector3(-18, 0, -30), Vector3(18, 0, 40)],
		# 线性关卡化·封锁带:沙漠油站收窄为"中轴→主站→北库"线形走廊
		#   东西翼全线封锁(与停机坪飞机/机库区重叠成封口,杜绝绕行)
		#   北端封口:北区储油库(hold)后方截断
		"blockers": [
			{ "x": 31.0, "z": 0.0, "w": 8.0, "d": 298.0, "kind": "rubble" },  # 东翼封锁带:中轴以东(含跑道/机库/东停机坪)
			{ "x": -31.0, "z": 0.0, "w": 8.0, "d": 298.0, "kind": "rubble" }, # 西翼封锁带:中轴以西(含机场西停机坪)
			{ "x": 0.0, "z": 105.0, "w": 54.0, "d": 4.0, "kind": "wall" },    # 北端封口:北区油库后方截断
		],
		# 线性关卡化·路线引导:出生点→主站区(中轴直通)
		"path": [
			Vector3(0, 0, -100), Vector3(0, 0, -50), Vector3(0, 0, -15),
		],
		"mid_lines": [
			{ "name": "铁柱", "text": "机枪台哑了两座,站区布防组在收缩,稳着打。", "dur": 3.0 },
			{ "name": "苏雅", "text": "油站守敌折损过半,注意输油管两侧的雷区。", "dur": 3.0 },
			{ "name": "老周", "text": "主站方向有狙击手,进站前先把制高点压住。", "dur": 3.0 },
		],
		"finish_lines": [
			{ "name": "铁柱", "text": "接线图到手,爆破网有解了!", "dur": 2.6 },
			{ "name": "苏雅", "text": "油库控制权到手,补给线稳了。", "dur": 2.8 },
		],
	})
	out[1]["briefing"] = _strip_dur(out[1]["cutscene"]["intro"])
	out[1]["epilogue"] = _strip_dur(out[1]["cutscene"]["outro"])
	out.append({
		"id": "c3",
		"title": "第三章",
		"cn": "冰刃",
		"tagline": "营救雪山哨站侦察班",
		"sub": "Cold Edge",
		"map": "snow",
		"map_cn": "雪山哨站",
		"chars": C,
		"squad": squad(),
		"cutscene": {
			"title_card": "第三章 · 冰刃",
			"flyover": [
				{ "pos": Vector3(0, 45, -136), "look": Vector3(-40, 0, 40), "dur": 3.4 },
				{ "pos": Vector3(-40, 70, -60), "look": Vector3(-80, 0, 40), "dur": 3.2 },
				{ "pos": Vector3(-90, 90, 0), "look": Vector3(-80, 0, 60), "dur": 3.6 },
				{ "pos": Vector3(-95, 80, 45), "look": Vector3(-80, 0, 80), "dur": 3.4 },
				{ "pos": Vector3(-40, 60, 95), "look": Vector3(-70, 0, 80), "dur": 3.4 },
			],
			"intro": [
				{ "name": "苏雅", "text": "『北翼』把侦察班围在雪山哨站。暴风雪三小时后封山,信号已断,他们撑不了太久。", "dur": 3.6 },
				{ "name": "陈振国上校", "text": "侦察班带着『北翼』的完整部署,人也都是好兵。曹锐,带他们回来,一个不少。", "dur": 3.6 },
				{ "name": "老周", "text": "东南山脊能架枪,风大,我贴地进,快不了。", "dur": 3.0 },
				{ "name": "曹锐", "text": "老周,你不是一个人去。铁柱,谷口留撤出通道;林雪,血包带足,雪地里时间就是命。", "dur": 3.4 },
				{ "name": "老周", "text": "……孟海是我送进侦察班的。他要是少一根头发,我这辈子过不去。", "dur": 3.2 },
			],
			"outro": [
				{ "name": "林雪", "text": "两名幸存者,伤情稳定。孟海左臂骨折,命保住了。", "dur": 3.2 },
				{ "name": "老周", "text": "……活着就好。方志走前托我带话给他弟弟:『别学我,该活着的时候,得活着。』", "dur": 3.8 },
				{ "name": "苏雅", "text": "孟海交出了完整部署图:白狼指挥部——暗夜雷达站,防空指挥雷达,他本人坐镇。", "dur": 3.8 },
				{ "name": "陈振国上校", "text": "人和情报都到手,『北翼』失了先手。接下来,轮到我们进攻了。", "dur": 3.4 },
				{ "name": "曹锐", "text": "雪会化,冰会碎,兄弟不会。老周,把方志的话捎到了,你也该下山了。", "dur": 3.4 },
			],
			"objective_names": ["抵达哨站", "救助幸存者", "掩护撤离", "断后清剿"],
		},
		"briefing": [],
		"epilogue": [],
		"objectives": [
			# 可达性:东西翼封锁带 x∈±[27,35];西翼缺口 z∈[-8,8] 通 x∈[-101,-35] 走廊;远西墙 x∈[-107,-101]
			# reach/hold 区 x∈[-96,-64],z∈[64,96]:哨站大道走廊 x∈[-101,-35],z∈[8,101] 全覆盖
			{ "type": "reach", "pos": Vector3(-80, 0, 80), "radius": 14.0, "loc": "雪山哨站",
				"desc": "抵达雪山哨站,接应侦察班" },
			# 可达性:幸存者 (-76,82) 在哨站大道走廊内,距远西墙 25m、北端封口 19m(≥8m 余量)
			{ "type": "interact", "pos": Vector3(-76, 0, 82), "radius": 5.0, "time": 3.5, "kind": "revive_survivor",
				"label": "按住 E 救助幸存者", "desc": "救助哨站内的负伤侦察兵孟海" },
			# 可达性:hold 区 x∈[-96,-64],z∈[64,96] 全覆盖;远西墙与圆区 ≥18m;北端封口 z∈[101,105] 在区外
			{ "type": "hold", "pos": Vector3(-80, 0, 80), "radius": 16.0, "time": 18.0, "desc": "掩护侦察班撤离哨站 18 秒" },
			{ "type": "kill", "count": 14, "desc": "断后清剿,肃清哨站沿线敌军" },
		],
		"enemy_total": 30,
		"enemy_cap": 10,
		"enemy_skill": 0.68,
		"player_deaths_limit": 5,
		"start_pos": Vector3(0, 0, -130),
		"start_yaw": 0.0,
		"spawn_anchors": [Vector3(-60, 0, 20), Vector3(-92, 0, 60), Vector3(-48, 0, 90)],
		# 线性关卡化·封锁带:雪山收窄为"南大道→z=0 西大道→x=-80 哨站大道"L 形走廊
		#   东西翼封锁:东翼全线封死;西翼只留 z=0 主街通道
		#   远西封锁:x=-80 哨站大道以西封死(x=-104,与 hold 圆区保持 ≥18m 余量);北端两处封口:哨站与南大道北端截断
		"blockers": [
			{ "x": 31.0, "z": 0.0, "w": 8.0, "d": 298.0, "kind": "rubble" },   # 东翼封锁带:南大道东侧全线
			{ "x": -31.0, "z": -79.0, "w": 8.0, "d": 142.0, "kind": "rubble" }, # 西翼南段:z=0 主街以南封死
			{ "x": -31.0, "z": 79.0, "w": 8.0, "d": 142.0, "kind": "rubble" },  # 西翼北段:z=0 主街以北(留 16m 通道)
			{ "x": -104.0, "z": 0.0, "w": 6.0, "d": 298.0, "kind": "rubble" }, # 远西封锁带:x=-80 哨站大道以西全线(hold 圆区余量 ≥18m)
			{ "x": -80.0, "z": 103.0, "w": 40.0, "d": 4.0, "kind": "wall" },    # 哨站北端封口(hold 区后方)
			{ "x": 0.0, "z": 103.0, "w": 50.0, "d": 4.0, "kind": "wall" },      # 南大道北端封口(防绕行北区)
		],
		# 线性关卡化·路线引导:出生点→中轴→z=0 西大道→哨站大道(全部在走廊内)
		"path": [
			Vector3(0, 0, -100), Vector3(0, 0, -45), Vector3(-60, 0, 0), Vector3(-80, 0, 55),
		],
		"mid_lines": [
			{ "name": "老周", "text": "山脊压住一片,哨站方向还有两处火力点,贴着雪走。", "dur": 3.2 },
			{ "name": "林雪", "text": "雪地里别恋战,孟海还等着我们,保命优先。", "dur": 3.0 },
			{ "name": "苏雅", "text": "哨站守敌折损过半,侦察班的撤离窗口在打开。", "dur": 3.0 },
		],
		"finish_lines": [
			{ "name": "老周", "text": "……孟海,还活着。谢天谢地。", "dur": 2.8 },
			{ "name": "林雪", "text": "幸存者都在,撤出路线干净,快走!", "dur": 2.8 },
			{ "name": "曹锐", "text": "哨站拿回来了,一个不少,撤!", "dur": 2.6 },
		],
	})
	out[2]["briefing"] = _strip_dur(out[2]["cutscene"]["intro"])
	out[2]["epilogue"] = _strip_dur(out[2]["cutscene"]["outro"])
	out.append({
		"id": "c4",
		"title": "第四章",
		"cn": "渡河",
		"tagline": "突破河谷防线",
		"sub": "The Crossing",
		"map": "bt_jungle",
		"map_cn": "丛林河谷",
		"chars": C,
		"squad": squad(),
		"cutscene": {
			"title_card": "第四章 · 渡河",
			"flyover": [
				{ "pos": Vector3(0, 40, -155), "look": Vector3(0, 0, -60), "dur": 3.4 },
				{ "pos": Vector3(-40, 65, -100), "look": Vector3(0, 0, -42), "dur": 3.2 },
				{ "pos": Vector3(0, 80, -55), "look": Vector3(0, 0, -10), "dur": 3.6 },
				{ "pos": Vector3(30, 90, 10), "look": Vector3(0, 0, 50), "dur": 3.2 },
				{ "pos": Vector3(0, 60, 80), "look": Vector3(-10, 0, 78), "dur": 3.4 },
			],
			"intro": [
				{ "name": "陈振国上校", "text": "河谷是白狼的纵深防线,对岸囤着西线全部弹药。重装部队过不了河,反攻就是空话。", "dur": 3.6 },
				{ "name": "苏雅", "text": "水位两天涨了半米,两座便桥都在他火力走廊里。强攻,会死人。", "dur": 3.2 },
				{ "name": "曹锐", "text": "先拔弹药库,再抢桥头。铁柱,爆破组跟我走水线;老周,对岸机枪阵地,一个不留。", "dur": 3.4 },
				{ "name": "铁柱", "text": "水线……行,我带足防水炸药。先说好,炸过头了,别怪我发明了新河道。", "dur": 3.4 },
				{ "name": "老周", "text": "水声吞枪声。过河的时候,谁也别回头。", "dur": 2.8 },
			],
			"outro": [
				{ "name": "铁柱", "text": "弹药库炸了,殉爆掀翻对岸半条防线。……小马,没回来。", "dur": 3.2 },
				{ "name": "曹锐", "text": "过河的命令是我下的,水位也是我判的。这笔账,我认。", "dur": 3.0 },
				{ "name": "老周", "text": "认账的不叫指挥官,少欠一条命的才叫。账记着,去下一个渡口还。", "dur": 3.2 },
				{ "name": "苏雅", "text": "重装部队过河了。侦察机报告:暮港码头灯火通明,白狼的船队在连夜装货。", "dur": 3.4 },
				{ "name": "曹锐", "text": "那我们就连夜去拆他的货。还账的最好方式,是让敌人先欠。", "dur": 3.0 },
			],
			"objective_names": ["清剿南岸", "摧毁弹药库", "抢占桥头", "呼叫工兵"],
		},
		"briefing": [],
		"epilogue": [],
		"objectives": [
			# 可达性:两侧封锁带 x∈±[22,30] / 南北封口 z∈[-162,-158]∪[103,107];中轴走廊 x∈[-22,22] 全程可达
			{ "type": "kill", "count": 12, "desc": "肃清河谷南岸的敌军" },
			# 可达性:破坏物撒点 x∈[-8,8],z∈[-30,-14] 在南岸走廊内(渡口前)
			{ "type": "destroy", "count": 4, "pos": Vector3(0, 0, -22), "spread": 8.0, "desc": "摧毁渡口的弹药库" },
			{ "type": "reach", "pos": Vector3(0, 0, 20), "radius": 14.0, "loc": "北岸桥头",
				"desc": "渡河抵达北岸桥头" },
			# 可达性:呼叫点 (0,34) 在北岸走廊 x∈[-22,22] 内,距两侧封锁带 22m、北端封口 69m(≥8m 余量)
			{ "type": "interact", "pos": Vector3(0, 0, 34), "radius": 5.0, "time": 3.0, "kind": "radio",
				"label": "接通指挥部电台", "desc": "呼叫指挥部,工兵架设重装备渡桥" },
		],
		"enemy_total": 34,
		"enemy_cap": 11,
		"enemy_skill": 0.76,
		"player_deaths_limit": 4,
		"start_pos": Vector3(0, 0, -145),
		"start_yaw": 0.0,
		"spawn_anchors": [Vector3(0, 0, -100), Vector3(-12, 0, -40), Vector3(12, 0, 60)],
		# 线性关卡化·封锁带:河谷收窄为"南岸中轴→渡口→北岸中轴"走廊
		#   东西两侧全线封锁(含河道南北两岸非渡口段):渡河只能走中央渡口
		#   南北两端封口:出生区后方与北岸桥头堡(hold)后方截断
		"blockers": [
			{ "x": -26.0, "z": 0.0, "w": 8.0, "d": 340.0, "kind": "rubble" }, # 西侧封锁带:河道西岸+西侧丛林全线
			{ "x": 26.0, "z": 0.0, "w": 8.0, "d": 340.0, "kind": "rubble" },  # 东侧封锁带:河道东岸+东侧丛林全线
			{ "x": 0.0, "z": 105.0, "w": 44.0, "d": 4.0, "kind": "wall" },    # 北端封口:北岸桥头堡后方
			{ "x": 0.0, "z": -160.0, "w": 44.0, "d": 4.0, "kind": "wall" },   # 南端封口:出生区后方
		],
		# 线性关卡化·路线引导:出生点→渡口→北岸弹药库区(中轴直通,跨河点=渡口)
		"path": [
			Vector3(0, 0, -120), Vector3(0, 0, -70), Vector3(0, 0, -32),
		],
		"mid_lines": [
			{ "name": "铁柱", "text": "对岸机枪阵地在换弹间歇,趁这个窗口推进。", "dur": 3.0 },
			{ "name": "苏雅", "text": "河谷守军折损过半,渡口火力在减弱。", "dur": 2.8 },
			{ "name": "老周", "text": "水声吞枪声,过河的时候,谁也别回头。", "dur": 2.8 },
		],
		"finish_lines": [
			{ "name": "铁柱", "text": "弹药库殉爆,渡口方向干净了!", "dur": 2.8 },
			{ "name": "苏雅", "text": "桥头堡到手,工兵可以进场架桥了。", "dur": 2.8 },
		],
	})
	out[3]["briefing"] = _strip_dur(out[3]["cutscene"]["intro"])
	out[3]["epilogue"] = _strip_dur(out[3]["cutscene"]["outro"])
	out.append({
		"id": "c5",
		"title": "第五章",
		"cn": "夜港",
		"tagline": "夜袭港口破坏补给船",
		"sub": "Night Harbor",
		"map": "bt_harbor",
		"map_cn": "暮港码头",
		"chars": C,
		"squad": squad(),
		"cutscene": {
			"title_card": "第五章 · 夜港",
			"flyover": [
				{ "pos": Vector3(0, 40, -152), "look": Vector3(0, 0, -60), "dur": 3.2 },
				{ "pos": Vector3(40, 60, -90), "look": Vector3(80, 0, -20), "dur": 3.4 },
				{ "pos": Vector3(75, 75, 0), "look": Vector3(101, 0, 12), "dur": 3.6 },
				{ "pos": Vector3(0, 85, 40), "look": Vector3(-44, 0, 78), "dur": 3.4 },
				{ "pos": Vector3(-55, 60, 90), "look": Vector3(-44, 0, 78), "dur": 3.2 },
			],
			"intro": [
				{ "name": "苏雅", "text": "暮港码头,白狼最后的补给线。船在装货,货在仓库,天亮前全走,就再没机会。", "dur": 3.6 },
				{ "name": "陈振国上校", "text": "断他海上补给,困他在陆上。补给船、起重设备、仓库,一个不留。", "dur": 3.2 },
				{ "name": "曹锐", "text": "铁柱,爆破组跟我走栈桥;老周,塔吊上压全港火力;林雪,货场入口留道缝接应。", "dur": 3.4 },
				{ "name": "铁柱", "text": "老周,你那是居高临下,我这叫高空作业——别把塔吊打塌,我还指着它吊炸药。", "dur": 3.4 },
				{ "name": "老周", "text": "我不炸塔吊。塔吊顶上那盏灯,今晚正好当瞄准镜。", "dur": 3.0 },
			],
			"outro": [
				{ "name": "铁柱", "text": "船沉了,仓烧了……嘶,埋在桶里的炸药,专门等着我,真他娘讲究。", "dur": 3.4 },
				{ "name": "林雪", "text": "弹片在右肩,位置不好,别动。队长,白狼刚就在塔吊影子里——他是故意放我们进来的。", "dur": 3.6 },
				{ "name": "曹锐", "text": "林雪,带铁柱撤出去,码头的事完了。白狼往北跑了——今天的账先记着,兄弟不能折在今晚。", "dur": 3.8 },
				{ "name": "苏雅", "text": "指挥部复述白狼电文:『雪豹小队,我在雷达站等你们,来把故事讲完。』", "dur": 3.4 },
				{ "name": "曹锐", "text": "讲完就讲完。铁柱的伤,我记在雷达站的账上——最后一枪,我要亲眼看着打出去。", "dur": 3.4 },
			],
			"objective_names": ["肃清码头", "炸沉驳船", "点燃仓库", "撤离码头"],
		},
		"briefing": [],
		"epilogue": [],
		"objectives": [
			# 可达性:主走廊 x∈[-23,35];西翼 x∈[-74,-31] 经 z∈(60,94) 缺口进入;东翼 x∈[41,170] 经 z∈(6,24) 缺口进入
			{ "type": "kill", "count": 12, "desc": "肃清南码头与栈桥的敌军" },
			# 可达性:装药点 (101,15) 在驳船带走廊 x∈[41,170],z∈(-7,29) 内,距两侧封锁带/封口墙 ≥9m(≥8m 余量)
			{ "type": "interact", "pos": Vector3(101, 0, 15), "radius": 5.0, "time": 3.5, "kind": "arm",
				"label": "按住 E 安装炸药", "desc": "在补给驳船上安装爆破装置" },
			# 可达性:点火点 (-44,78) 在仓库带走廊 x∈[-74,-31],z∈(60,94) 内,距各封锁带 ≥16m(≥8m 余量)
			{ "type": "interact", "pos": Vector3(-44, 0, 78), "radius": 5.0, "time": 3.0, "kind": "arm",
				"label": "按住 E 点火引燃", "desc": "点燃港区仓库的储运物资" },
			# 可达性:撤离点 (0,-120) 在南码头走廊 x∈[-23,35] 内,距西/东封锁带 ≥23m
			{ "type": "reach", "pos": Vector3(0, 0, -120), "radius": 14.0, "loc": "南码头撤离点",
				"desc": "前往南码头撤离点登机" },
		],
		"enemy_total": 38,
		"enemy_cap": 12,
		"enemy_skill": 0.85,
		"player_deaths_limit": 4,
		"start_pos": Vector3(0, 0, -145),
		"start_yaw": 0.0,
		"spawn_anchors": [Vector3(24, 0, -80), Vector3(24, 0, 0), Vector3(-60, 0, 72)],
		# 线性关卡化·封锁带:港区收窄为"南码头→中栈桥→东驳船→西北仓库"走廊
		#   西翼:只留 z∈[60,94] 仓库带通道,其余(南/北/最西端)封死
		#   东翼:只留 z∈[6,24] 栈桥带通向东驳船区,其北/南/远端全部封死
		"blockers": [
			{ "x": -27.0, "z": -55.0, "w": 8.0, "d": 230.0, "kind": "rubble" },  # 西翼封锁带南段(仓库带以南)
			{ "x": -27.0, "z": 132.0, "w": 8.0, "d": 76.0, "kind": "rubble" },   # 西翼封锁带北段(仓库带以北)
			{ "x": 38.0, "z": -82.0, "w": 6.0, "d": 176.0, "kind": "rubble" },   # 东翼封锁带南段(栈桥带以南)
			{ "x": 38.0, "z": 97.0, "w": 6.0, "d": 146.0, "kind": "rubble" },    # 东翼封锁带北段(栈桥带以北)
			{ "x": -77.0, "z": 0.0, "w": 6.0, "d": 340.0, "kind": "rubble" },    # 最西封口:仓库带以西纵深封死
			{ "x": 102.5, "z": 32.0, "w": 135.0, "d": 6.0, "kind": "wall" },     # 东区北封口:驳船带以北
			{ "x": 102.5, "z": -10.0, "w": 135.0, "d": 6.0, "kind": "wall" },    # 东区南封口:驳船带以南
			{ "x": -92.5, "z": 105.0, "w": 115.0, "d": 6.0, "kind": "wall" },    # 西区北封口:仓库带以北
			{ "x": -92.5, "z": 30.0, "w": 115.0, "d": 6.0, "kind": "wall" },     # 西区南封口:仓库带以南
		],
		# 线性关卡化·路线引导:出生点→中栈桥(南码头直通)
		"path": [
			Vector3(0, 0, -120), Vector3(0, 0, -60), Vector3(0, 0, -20),
		],
		"mid_lines": [
			{ "name": "老周", "text": "塔吊上看得清楚,码头守军往仓库带撤了。", "dur": 3.0 },
			{ "name": "林雪", "text": "栈桥火力点拔掉大半,货场入口还留着缝。", "dur": 3.0 },
			{ "name": "苏雅", "text": "码头守军折损过半,白狼的船还在装货,动作快。", "dur": 3.0 },
		],
		"finish_lines": [
			{ "name": "铁柱", "text": "炸药埋好了,船在劫难逃。", "dur": 2.6 },
			{ "name": "林雪", "text": "撤离点清出来了,兄弟们撤!", "dur": 2.8 },
		],
	})
	out[4]["briefing"] = _strip_dur(out[4]["cutscene"]["intro"])
	out[4]["epilogue"] = _strip_dur(out[4]["cutscene"]["outro"])
	out.append({
		"id": "c6",
		"title": "第六章",
		"cn": "零度",
		"tagline": "攻占防空指挥雷达站",
		"sub": "Zero Hour",
		"map": "bt_peak",
		"map_cn": "暗夜雷达站",
		"chars": C,
		"squad": squad(),
		"cutscene": {
			"title_card": "第六章 · 零度",
			"flyover": [
				{ "pos": Vector3(0, 50, -155), "look": Vector3(0, 0, -60), "dur": 3.4 },
				{ "pos": Vector3(-30, 85, -70), "look": Vector3(0, 0, -20), "dur": 3.4 },
				{ "pos": Vector3(20, 105, -10), "look": Vector3(0, 18, 0), "dur": 3.8 },
				{ "pos": Vector3(-15, 120, 40), "look": Vector3(0, 18, 10), "dur": 3.4 },
				{ "pos": Vector3(0, 95, 85), "look": Vector3(0, 0, 80), "dur": 3.4 },
			],
			"intro": [
				{ "name": "苏雅", "text": "暗夜雷达站,防空指挥雷达,白狼最后的堡垒。雷达在,他们的炮火就长着眼睛。", "dur": 3.6 },
				{ "name": "陈振国上校", "text": "零度行动,终章。六处要地,五处已经回来,这是最后一处。雪豹小队,你们是整个战役的矛尖。", "dur": 3.8 },
				{ "name": "曹锐", "text": "从街区到油站,从雪山到河谷,再到今晚的港口——我们一路打过来,不是因为枪好,是因为身边有人。", "dur": 3.8 },
				{ "name": "老周", "text": "山顶风大信号差。狙击位我自己找,你们放心往上打。", "dur": 3.0 },
				{ "name": "林雪", "text": "打完这一仗,我请全队喝热汤。规矩不变——先活着,再喝汤。", "dur": 3.0 },
			],
			"outro": [
				{ "name": "白狼", "text": "……齐万里临死前说,会有人替他打完这一仗。看来,他赌对了。", "dur": 3.6 },
				{ "name": "曹锐", "text": "雷达站收复,白狼确认死亡。零度行动,任务完成。", "dur": 3.2 },
				{ "name": "苏雅", "text": "指挥部全体频道:边境六处要地全部收复,防线回到联军手中。", "dur": 3.4 },
				{ "name": "陈振国上校", "text": "雪豹小队,干得漂亮。从今天起,你们的名字,就是联军的旗帜。", "dur": 3.2 },
				{ "name": "曹锐", "text": "齐排长,首哨的灯,我替你点回来了。……全体,回家。", "dur": 3.4 },
			],
			"objective_names": ["突破外线", "爆破山门", "摧毁雷达", "击毙白狼"],
		},
		"briefing": [],
		"epilogue": [],
		"objectives": [
			# 可达性:东西翼封锁带 x∈±[27,35] / 北端封口 z∈[103,107];中轴走廊 x∈[-27,27] 全程可达
			{ "type": "kill", "count": 12, "desc": "突破雷达站外围防线" },
			# 可达性:山门 (0,-80) 在中轴走廊内,距两侧封锁带 ≥27m、北端封口 ≥183m(≥8m 余量)
			{ "type": "interact", "pos": Vector3(0, 0, -80), "radius": 5.0, "time": 2.5, "kind": "breach",
				"label": "爆破山门", "desc": "爆破山门,突入雷达站腹地" },
			# 可达性:破坏物撒点 x∈[-9,9],z∈[9,27] 在中轴走廊内
			{ "type": "destroy", "count": 4, "pos": Vector3(0, 0, 18), "spread": 9.0, "desc": "摧毁防空指挥雷达阵列" },
			# 可达性:白狼出生点 (0,80) 在中轴走廊内,玩家可直达交战
			{ "type": "boss", "pos": Vector3(0, 0, 80), "desc": "击毙佣兵团首领「白狼」" },
		],
		"enemy_total": 42,
		"enemy_cap": 13,
		"enemy_skill": 0.94,
		"player_deaths_limit": 4,
		"start_pos": Vector3(0, 0, -145),
		"start_yaw": 0.0,
		"spawn_anchors": [Vector3(0, 0, -100), Vector3(-16, 0, -40), Vector3(18, 0, 30)],
		# 线性关卡化·封锁带:雷达站收窄为"山门→雷达阵列→指挥中心"中轴走廊
		#   东西翼全线封锁(与散落碉堡/营房重叠处形成封口);北端封口:指挥中心(白狼)后方
		"blockers": [
			{ "x": 31.0, "z": 0.0, "w": 8.0, "d": 298.0, "kind": "rubble" },  # 东翼封锁带:中轴以东全线
			{ "x": -31.0, "z": 0.0, "w": 8.0, "d": 298.0, "kind": "rubble" }, # 西翼封锁带:中轴以西全线
			{ "x": 0.0, "z": 105.0, "w": 50.0, "d": 4.0, "kind": "wall" },    # 北端封口:指挥中心后方截断
		],
		# 线性关卡化·路线引导:出生点→山门→雷达阵列区(中轴直通)
		"path": [
			Vector3(0, 0, -125), Vector3(0, 0, -95), Vector3(0, 0, -60),
		],
		"mid_lines": [
			{ "name": "苏雅", "text": "雷达站守军折损过半,白狼的贴身卫队还没动。", "dur": 3.0 },
			{ "name": "老周", "text": "山顶风大,弹道飘,都给我贴近了再打。", "dur": 2.8 },
			{ "name": "曹锐", "text": "外围清得差不多了,往山门压!", "dur": 2.6 },
		],
		"finish_lines": [
			{ "name": "曹锐", "text": "山门破了,雷达阵列就在前面!", "dur": 2.8 },
			{ "name": "铁柱", "text": "雷达阵列报销,白狼的防空网瞎了。", "dur": 2.8 },
			{ "name": "老周", "text": "指挥中心到了,白狼,该算总账了。", "dur": 2.8 },
		],
	})
	out[5]["briefing"] = _strip_dur(out[5]["cutscene"]["intro"])
	out[5]["epilogue"] = _strip_dur(out[5]["cutscene"]["outro"])
	return out
