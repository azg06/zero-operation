# 第一人称玩家身体视角规范 v2.0

> 适用范围：《零度行动》玩家第一人称视角（相机 / 身体 / 头部对齐 / 姿态）。
> v2.0 变更：**头部前倾取代躯干溶解**、蹲姿身体补偿、腾空姿态、第一人称手臂比例。
> 所有数字均来自实机 QA 实测（`--test-fpdiag`），不是估算。v1 存档见 `fp_body_spec.v1.md`。

---

## 1. 设计目标

参考主流大型军事 FPS（Battlefield / Call of Duty / Escape from Tarkov）的第一人称表现：

- 相机**严格位于玩家角色双眼之间**，高度等于真实站姿眼高。
- **低头时相机随头部前倾**，像真人一样绕颈椎转动 —— 而不是原地转镜头。
- 身体从镜头位置**自然向下连续延伸**，低头能看到真实的胸、腹、腰、腿、靴。
- 身体与相机**共享同一套人体骨骼与空间坐标系**。
- 各姿态（站/走/跑/冲刺/蹲/趴/跳/换弹）保持合理空间关系。
- 镜头有轻微真实的人体运动感，但不过度晃动。

**核心原则：能看见身体 ≠ 把身体藏起来。** 相机必须物理地位于身体外部，
靠"前倾 + 抬高眼位 + 拉开净空"实现，而不是把躯干删掉。

---

## 2. 铁律（Hard Rules）

| # | 规则 | 违反后果 |
|---|---|---|
| R1 | 站立眼高 **1.70 m**，与 GLB 模型真实眼位一致 | 相机贴进胸腔，`near` 把胸口整片裁掉 |
| R2 | 站立/走/跑/蹲 的 `back_off` **必须为 0** | 身体落到相机背后 ⇒ 低头连腿都看不到 |
| R3 | **严禁把 Chest 骨缩到 1 cm** 来"躲镜头" | 胸口彻底消失，用户已明确否决 |
| R4 | 相机必须随 `pitch` **绕颈椎枢轴前倾**，不允许原地只转朝向 | 相机被身体 AABB 包住，主观像在身体后侧 |
| R5 | **严禁用"溶解/隐藏躯干"来露腿** | 会直接看到两条光腿，极不自然（用户已否决） |
| R6 | `set_bone_global_pose_override` 用后必须清除 | IK 是持久标记，腿会永久卡在腾空/乘员姿态 |
| R7 | 改任何一条参数前先跑 `--test-fpdiag` 取基线 | 无线索调参 = 复现历史 bug |

---

## 3. 坐标系与人体比例

Godot 坐标系，Y 向上，单位米，**原点在角色脚底**。身体朝向 `body.rotation.y = yaw`，
`rotation.x` 恒为 0（身体不随视线俯仰，只有 `AimPitch` 骨带手臂与枪）。

| 部位 | 高度 (m) | 来源 |
|---|---|---|
| 地面 / 靴底 | 0.00 | — |
| 靴顶 / 踝 | 0.12 | 实测 `FootL/FootR` |
| 膝 | 0.48 | 士兵 GLB |
| 胯 / Hips | 1.00 | 实测 |
| 腰 | 1.10 | 士兵 GLB |
| Chest 骨 | 1.25 | 实测（已含 `FP_CHEST_DROP`） |
| 胸顶（下压后） | 1.445 | 1.595 − 0.15 |
| 肩 | 1.45 | 士兵 GLB |
| Neck / Head 骨 | 1.41 | 实测 |
| **站立眼位（相机）** | **1.70** | `player.gd::eye_height` |
| 头顶 | ~1.80 | 士兵 GLB |

站立对齐实测：相机 **1.701** ↔ 模型眼位 **1.700**（差 1 mm）。

### 3.1 相机模型 —— 含头部前倾

```gdscript
# 位置 = 眼位 + 相机局部空间偏移
var lean_drop := HEAD_PIVOT_TO_EYE * (1.0 - cos(pitch))   # 眼高下降量
var lean_fwd  := HEAD_PIVOT_TO_EYE * sin(pitch)            # 沿角色前向位移(负=低头=前移)
var cam_base := Vector3(pos.x, pos.y + eye_height - lean_drop, pos.z)
cam_base += Vector3(-sin(yaw), 0.0, -cos(yaw)) * (-lean_fwd)
cam.global_position = cam_base + cam.global_transform.basis * motion_pos
```

`HEAD_PIVOT_TO_EYE = 0.20`（眼到颈椎枢轴，≈真人 C7–眼球距离）。
原理：真人低头时头绕颈根旋转，眼睛**同时向前和向下**移动，而不是原地转头。

实测（`--test-fpdiag` B 段）：

| pitch | 前移 (m) | 下降 (m) |
|---|---|---|
| 0.00 | 0.000 | 0.000 |
| −0.45 | 0.087 | 0.019 |
| −0.90 | 0.157 | 0.075 |
| −1.45 | 0.199 | 0.176 |

抬头（`pitch > 0`）对称后仰；平视时位移为 0。

### 3.2 各姿态眼高

| 姿态 | `eye_height` | 阻尼 | 说明 |
|---|---|---|---|
| 站立 / 走 / 跑 / 冲刺 | 1.70 | 12 | 基准 |
| 蹲伏 / 蹲走 | **1.08** | 12 | = 模型蹲姿真实眼位 |
| 滑铲 | 0.72 | 22（进）/ 12（出） | 快速压入、利落回正 |
| 趴下 | 0.45 | 12 | 配合 `back_off 0.6` |

### 3.3 蹲姿身体补偿（`CROUCH_FOOT_LIFT = 0.13`）

**问题**：GLB 的 `Crouch` 动画把**整个骨架连同脚踝**一起下沉，不是屈膝。
实测蹲下时 Hips 1.00→0.25、Head 1.41→0.66（整体 −0.75 m），
**FootL/FootR 0.12 → −0.01（穿地 0.13 m）**。
相机只降到 1.12 ⇒ 模型眼位（≈0.95）比相机低 0.17 m ⇒ 相机浮在身体上方，一蹲下就"分开"。

**修复**：按蹲伏程度把身体抬回地面。

```gdscript
_crouch_amt = Utils.damp(_crouch_amt, 1.0 if (crouched or slide_t > 0) else 0.0, 12.0, dt)
body.position.y += CROUCH_FOOT_LIFT * _crouch_amt
```

实测结果：脚踝回到 **0.12（着地）**；相机 **1.078** ↔ 模型眼位 **1.080**（差 2 mm，与站立同量级）。

---

## 4. 全身连续性 — 三机制

### M1 · 眼位对齐真实眼高

士兵 GLB 背心顶面 1.595 m、冲刺前倾最高 ~1.62 m。若眼高沿用旧的 **1.62**，
相机与胸口几乎等高 ⇒ 相机等于贴在胸腔里，主相机 `near = 0.08` 会把胸口整片裁掉。
→ 眼高 **1.70**（模型真实眼位，头骨 1.64–1.80）。

### M2 · 胸腔下压 `FP_CHEST_DROP = 0.15`

每帧把 `Chest` 骨的 pose position 下移 0.15 m（写绝对值，不累积）。
眼—胸间距从 ~10 cm 提升到 **~25 cm**（真人 ≈30 cm）。
Blender 逐帧量化：全兵种 × 全动画 × 全俯角**最小视深 ≥ 0.143 m > near 0.08**。

### M3 · 头部前倾（v2.0 **取代**旧的躯干溶解）

**旧方案（已废弃）**：俯角 >60° 时用 shader `discard` 把躯干段（0.92–1.55 m）抖动溶解掉，
好让大腿/靴子露出来。

**为什么废弃**：用户实测否决 —— *「设计成视角下移就隐藏身体的设计，导致能直接看到双腿，
这不对」*。溶解是治标：真问题是相机原地旋转，视线被自己的身体挡住。

**现方案**：相机绕颈椎枢轴前倾（§3.1），相机随低头移出躯干、落到身体**前方**，
低头看到的是正常胸口正面。**网格 / 骨骼 / 影子全程不动。**

```gdscript
# 恒写 0：保留 uniform 兼容旧材质，但任何路径都不再溶解躯干
fp_mat.set_shader_parameter("fp_yield", 0.0)
```

---

## 5. 姿态 → 动画映射

士兵 GLB 只有 **8 个**动画：`Crouch, CrouchWalk, Death, Idle, Prone, ProneCrawl, Run, Walk`
（**没有 Jump / Fall / Land，也没有 Sprint**，冲刺复用 Run）。

```gdscript
if _air_amt > 0.5:                        # 腾空 → Idle + 程序化摆腿(见 5.1)
    want = "Idle"
elif _prone_amt > 0.5:                    # 趴
    h_speed > 0.4  → ProneCrawl   speed_scale = clamp(h/1.3, 0.6, 1.4)
    else           → Prone
elif crouched or slide_t > 0:             # 蹲 / 滑铲
    h_speed > 0.6  → CrouchWalk   speed_scale = clamp(h/2.8, 0.6, 1.3)
    else           → Crouch
elif h_speed > 4.4 → Run              speed_scale = clamp(h/5.8, 0.7, 1.5)
elif h_speed > 0.6 → Walk             speed_scale = clamp(h/4.2, 0.5, 1.5)
else               → Idle
```

### 5.1 腾空姿态（程序化）

没有跳跃动画，所以用 IK 摆腿（`RidePose.air_legs`，与坐/骑姿同一路子）：

- `vy > 0` 上升 → **收腿**：脚抬到 0.60 m 高、前伸 0.20 m，膝盖朝前上
- `vy < 0` 下落 → **伸腿**：脚放低，准备触地
- `amt`（0→1）从站立腿位插值 ⇒ 起跳/落地平滑，不硬切

```gdscript
if _air_amt > 0.02 and _prone_amt < 0.5:
    RidePose.air_legs(skel, vel.y, _air_amt)
    _air_legs_active = true
elif _air_legs_active:
    skel.clear_bones_global_pose_override()   # ★必须清，否则腿永久卡住
    _air_legs_active = false
```

**`on_ground` 必须能反映离地**：
旧版只在「起跳」「落地」两处写，被传送到空中（跳伞 / 载具弹出 / 瞬移）时它停在 `true`
⇒ 腾空姿态永不触发。已补：

```gdscript
elif pos.y > gh + 0.05:      # 留 5cm 容差，避免贴地浮点误差锁死跳跃
    on_ground = false
```

实测跳跃全程（`--test-fpdiag` D 段）：`air` 0.64 → 1.00 → 0.00 平滑；
落地后腿位 **0.338 → 0.201 → 0.148 → 0.120** 平滑归位。

### 5.2 `AimPitch` 骨

跟随视线俯仰 `clampf(pitch, -0.6, 0.6)`，只带手臂与枪，身体朝向不受影响。

---

## 6. 第一人称手臂

模型 `models/fp_arms.glb`，6 段（左右各 上臂/前臂/手），2-bone IK 抓握把与护木。
驱动 `src/player/fp_arms.gd`，由 `gun.gd::_fp_arms_setup()` 创建（**全枪共享**一个实例）。

### 比例校正（`FP_ARM_SCALE = 1.25`）

FP 手臂按士兵 **0.80 缩比**建模，实测与身体 GLB 真实臂段对比：

| 段 | FP 手臂 | 身体 GLB | 差 |
|---|---|---|---|
| 上臂 | 0.324 | 0.332 | −2% |
| 前臂 | 0.329 | 0.421 | **−22%** |
| 整臂 | 0.653 | 0.753 | **−15%** |

表现为"手很小、前臂细到几乎看不见"。修复：

```gdscript
fp_arms.seg_scale = FP_ARM_SCALE                    # 只缩零件几何，不动位置
fp_arms.len_up    = FpArmsScript.LEN_UP   * FP_ARM_SCALE   # IK 长度必须同步
fp_arms.len_fore  = FpArmsScript.LEN_FORE * FP_ARM_SCALE
fp_arms.shoulder_off_l/r = SHOULDER_OFF_L/R * FP_ARM_SCALE # 保持肘弯比例
fp_arms.guard_drop       = GUARD_DROP       * FP_ARM_SCALE # 保持"手掌托护木"相切
```

实测：`LEN_UP 0.3319` ↔ 身体 0.3318、`LEN_FORE 0.4419` ↔ 身体 0.4206 ✓ 对齐。

**注意**：`seg_scale` 只缩放零件几何的基向量，`pos` 不受影响（见 `FpArms._place` 注释），
所以放大不会位移；但 **IK 用的 `len_up` / `len_fore` 必须同步乘同系数**，否则接缝错位。

---

## 7. 镜头运动层（FirstPersonMotionSystem）

`src/player/fp_motion.gd`，单层控制器，每帧只 update 一次。
11 套状态预设：`idle / walk / run / sprint / crouch / crouch_walk / aim / aim_walk / aim_sprint / jump / landing`

```
速度 + 加速度 + 鼠标增量 + 玩家状态 + 武器重量
  → 状态参数插值 → 呼吸 / Bob / Sway / Inertia / 落地冲量五层
  → Spring / Damping → Camera + Weapon + 手部 IK 偏移
```

设计约束（避免"过度晃动"）：

- Bob 不用 `sin(t)*amp` 作为唯一晃动源，而是**步距积分相位 + 多谐波叠加**。
- Camera 与 Weapon 用**不同频率/幅度/相位**，武器额外过低刚度弹簧，天然滞后。
- 转向 Sway 用**带饱和的非线性鼠标速度**，慢速自动趋近 0。
- 急停/换向用"加速度目标 + 欠阻尼弹簧"产生前冲→回弹。
- 全系统零每帧对象分配，弹簧预创建。

**注意**：`jump` / `landing` 只是**镜头层冲量**，与身体腾空姿态是两回事（后者见 §5.1）。

---

## 8. 禁止项 → 技术对策

| 禁止项 | 对策 |
|---|---|
| 胸腔横截面 / 身体模型断面 | M1 眼位对齐 + M2 胸下压；**禁止用溶解**（R5） |
| 悬浮的身体部件 | 单一连续 GLB 骨架，`body.position = pos` |
| 摄像机位于胸口后方 | R2：站立 `back_off = 0` |
| 相机被自己身体包住 | M3：头部前倾，相机随低头移出躯干 |
| 身体模型穿过摄像机 | M2 ⇒ 最小视深 ≥ 0.143 m > near 0.08 |
| 从胸腔内部向外观察 | M1 + M3 |
| 蹲下时相机浮在身体上方 | §3.3 蹲姿身体补偿 |
| 低头直接看到两条光腿 | R5：禁止溶解躯干 |
| 腾空后腿被永久卡住 | R6：清 `clear_bones_global_pose_override()` |
| 头 / 脖挡住视线 | 头、颈、双臂骨骼 pose scale → 0.01，影子由 `ShadowHead` 代理补 |
| 第一人称出现四条手臂 | 身体双臂骨骼隐藏，手臂只由 `fp_arms.glb` 渲染 |

---

## 9. 验收方法

### 9.1 纯数值诊断（推荐，不占内存）

```sh
Godot_v4.7.1-stable_win64_console.exe --path <项目根> \
  ++ --test-play conquest city --test-fpdiag
```

四段输出：

| 段 | 内容 | 判定 |
|---|---|---|
| A 蹲起同步 | 逐帧 `eye_h / cam_y` + `Hips/Spine/Chest/Neck/Head/FootL/FootR` 骨世界 y | 脚 0.12 着地；`cam_y` 与模型眼位差 ≤ 5 mm |
| B 低头前倾 | 各俯角相机 y / 前移量 | 与 `0.20×sin` / `0.20×(1−cos)` 一致 |
| C 手臂比例 | FP 各段世界尺寸 vs 身体 GLB rest 骨长 | `LEN_UP ≈ 0.332`、`LEN_FORE ≈ 0.42` |
| D 跳跃腾空 | `ground / vel_y / air / FootL` | `air` 平滑 0→1→0；落地后脚回 0.12 |

> **踩坑**：`Input.action_press("jump")` 在协程里产生不了 `is_action_just_pressed` 边沿，
> 测跳跃要直接置物理状态（`p.pos.y += 4.0; p.vel.y = 5.4`）。

### 9.2 出图体检（占内存，按需）

```sh
... ++ --test-play conquest city --test-pbody      # 7 姿态 × 3 俯角 + 剪影洞检测
... ++ --test-play conquest city --test-lookdown   # 低头 6 档 · 身体占屏比
```

判定：剪影帧内不得出现"洞"或横切边；地面影子必须保持完整人形。

> ⚠️ 这些 QA 会往 `E:/工作目录2/models_probe/` 写几十张 PNG，注意清理。

---

## 10. 已知缺口（待办）

1. **手臂「位置」**：腰射时手贴画面底边。旧记录里 `ARM_LIFT` 曾试 +0.045 观感变差
   （但那时手臂是 1.0 缩放的细臂）。可能需改 FOV 或重做枪位，**尚未定方向**。
2. **攀爬 / 翻越**：项目内**没有** vault / mantle / climb 系统。
3. **落地缓冲姿态**：腾空已有，但落地瞬间腿部仅靠 IK 渐出，没有专门的"屈膝缓冲"关键帧。

---

## 11. 附录 — 交给 AI Agent 的工程级 Prompt

```text
任务：在 Godot 4 项目中实现/校验标准第一人称玩家身体视角。

先做：读完 src/player/player.gd 的相机合成与下半身同步段、src/models/soldier_model.gd 的
build_player_body / FP_CHEST_DROP、src/player/gun.gd 的 _fp_arms_setup、
src/vehicles/ride_pose.gd，再动手。不要在不了解现有实现的情况下重写系统。

硬约束（任一条不满足即视为失败）：
- FIRST-PERSON CAMERA = EYE LEVEL。站立眼高必须等于角色模型真实站姿眼位。
- CAMERA LEANS WITH HEAD。低头时相机必须绕颈椎枢轴前倾(眼同时前移+下降)，
  不允许固定在世界轴线只转朝向。
- CAMERA POSITION = BETWEEN THE EYES。相机由 角色原点 + (0, eye_height, 0) 得到，
  叠加头部前倾位移；禁止额外水平偏移(趴姿除外)。
- FULL BODY CONTINUITY。身体与相机共享同一套骨骼与同一空间坐标原点。
- NO TORSO CROSS-SECTION / NO CUTAWAY BODY。禁止出现胸腔横截面或被相机裁掉的断面。
- NO HIDING THE TORSO。严禁用"溶解/隐藏躯干"来让腿露出来 —— 必须靠相机移到身体前方。
- NO CAMERA INSIDE CHEST。相机必须物理位于身体外部。
- NO BODY CLIPPING。相机近平面不得切开任何身体部件。
- REALISTIC HUMAN PROPORTIONS。头/颈/肩/胸/腰/腿比例符合真实人体。
- VISIBLE LOWER BODY。低头时能依次看到胸、腹、腰、腿、靴。
- 蹲姿相机眼高必须与模型蹲姿真实眼位对齐(先测骨骼，不要用蒙皮网格 AABB)。
- 第一人称手臂尺寸必须与身体 GLB 臂段对齐(上臂≈0.332m、前臂≈0.421m)。

实现要求：
1. 相机位置 = 角色原点 + 眼高 + 头部前倾位移；身体位置 = 同一角色原点。
2. 眼位对齐模型真实眼位(若胸口顶面与眼位距离 <15cm，必须抬高眼位或在骨骼层拉开净空)。
3. 若近平面仍会裁切胸口，用骨骼 pose position 整体下压胸段增加净空，禁止缩放 Chest 骨。
4. 蹲姿若发现身体(含脚踝)整体下沉导致穿地或相机浮空，按蹲伏程度把身体抬回地面，
   并让蹲姿眼高等于模型蹲姿真实眼位。
5. 无跳跃/坠落动画时，按垂直速度程序化摆腿(上升收腿 / 下落伸腿)，用 amt 插值避免硬切。
6. 使用 set_bone_global_pose_override 后必须在结束时 clear_bones_global_pose_override，
   否则骨骼永久卡住。
7. on_ground 必须能反映真实离地状态(不能只在起跳/落地两处写)。
8. 姿态需覆盖 站立/走/跑/冲刺/蹲/蹲走/滑铲/趴/匍匐/腾空，用 0.2–0.3s 淡入，
   速度驱动 speed_scale。
9. 镜头运动分 呼吸/Bob/Sway/惯性/落地冲量 五层，Camera 与 Weapon 用不同频率与相位，
   Sway 用带饱和的非线性鼠标速度；禁止单一 sin 晃动源。

禁止出现：
- 相机在胸口后方 / 相机在胸腔内 / 身体穿过相机 / 相机被身体 AABB 包住
- 胸腔横截面、身体模型断面、悬浮的身体部件
- 低头时胸口整片消失，或看到胸腔内壁，或直接看到两条光腿
- 蹲下时相机浮在身体上方、与身体脱开
- 第一人称手臂与身体比例明显不符(过小/过细)
- 第一人称出现四条手臂或两个头
- 腾空/落地后腿部姿态卡住不归位

验收：
运行 --test-play <模式> <地图> --test-fpdiag，检查四段数值：
蹲起同步(脚 0.12 着地、相机与模型眼位差 ≤5mm)、低头前倾(符合 0.20×sin/1-cos)、
手臂比例(LEN_UP≈0.332 / LEN_FORE≈0.42)、腾空(air 平滑 0→1→0、落地归位 0.12)。
先给出核验结果与差距清单，再实施修改。
```
