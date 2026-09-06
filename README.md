# 零度行动 · ZERO OPERATION

> 大型多兵种征服/突破/战役作战 FPS —— Godot 4.7 引擎驱动的类《战地》射击游戏（AI 协作创作）。

## 游戏特色

- **征服模式（Conquest）**：320-360m 大地图，占点争夺 + 多数旗帜流血，AI 士兵全战术行为（掩体、小队协同、侧翼包抄、动态平衡）
- **突破模式（Breakthrough）**：攻防推进逐区争夺，区域按顺序解锁、未开放区域封锁（越界遣返/不可部署），可选进攻方/防守方，前线出生线
- **战役模式（Campaign / 战争故事）**：6 章完整原创剧情（城市《夺路》→ 沙漠《燃点》→ 雪地《冰刃》→ 丛林《渡河》→ 码头《夜港》→ 雷达站《零度》），四人小队（曹锐/林雪/老周/铁柱）、开场过场飞越、目标点名卡、击杀里程碑台词、交互任务（破门/装药引爆/电台呼叫/救助幸存者）、线性关卡封锁与路线引导、章节解锁存档
- **4 大兵种**：突击兵 / 工程兵 / 支援兵 / 侦察兵（侦察兵夜视仪夜间索敌）
- **载具**：坦克 / 步战车 / 防空车 / 侦察吉普 / 武装直升机 / 战斗机（AI 驾驶，含盘旋/俯冲扫射/返航维修战术状态机）
- **武器**：55 把枪械，带下坠/穿透/部位倍率的弹道、首发高后坐曲线；霰弹枪逐发装填 + 真实泵动循环（后拉/前推/抛壳/首壳上膛），左轮手枪弹巢逐膛管理（快速装弹器 / 逐发装填 / 部分装填 / 可中断）；弹鼓轻机枪与弹链轻机枪使用独立的摘鼓/对位/锁定与开盖/抽链/铺链/闭锁换弹动画
- **画面**：Sky3D 大气昼夜、体积雾、多层纹理混合地形、MultiMesh 批绘植被、六阶段爆炸时间轴、画质四档（LOW→ULTRA）自动硬件检测
- **音频**：分层总线（Master/Music/SFX/Ambience/UI/Steps）、3D 空间化、脚步低通滤波、直升机引擎随速联动

## 运行环境

- Godot **4.7.1**（Forward+ / Vulkan），Windows / Web 均可导出
- 纯 GDScript，无第三方依赖（内含 Sky3D 开源插件）

## 快速开始

1. 安装 Godot 4.7.1
2. 打开项目 `project.godot` → F5 运行
3. 主菜单：征服模式 / 突破模式 / 战争故事（战役）

## 目录结构

```
src/
  autoload/   全局单例（G / AudioSys / GraphicsQuality）
  core/       主循环与对局逻辑（main / game）
  data/       武器 / 兵种 / 地图数据
  campaign/   战役控制器与 6 章剧情数据
  ai/         AI 士兵（状态机 / 感知 / 战术 / 载具驾驶）
  player/     玩家控制（移动 / 武器 / 载具镜头）
  vehicles/   地面载具与空中载具（含 AI 飞行状态机）
  models/     程序化模型（士兵 / 武器 / 载具 / 飞机）
  world/      程序化世界构建（地形 / 建筑 / 植被 / 特效物件）
  fx/         粒子特效与全屏后处理（FXAA / 爆炸 / 弹道特效）
  ui/         HUD / 菜单 / 部署地图 / 小地图
```

## 构建发布

`export_presets.cfg` 已配置两个导出模板：

| 模板 | 平台 | 输出位置 |
|---|---|---|
| Windows Desktop | Windows x86_64，PCK 内嵌的单文件 `.exe` | `E:\工作目录\zero\exe\零度行动.exe`（项目内相对路径 `../exe/零度行动.exe`） |
| Web（Windows WebAssembly） | WebAssembly / HTML5 | `E:\工作目录\zero\exe\web\index.html`（项目内相对路径 `../exe/web/index.html`） |

> 每次完成一个大项目 / 重大功能，必须**先做一次无头测试，测试通过后再导出**。

### 标准发布流程

1. **无头测试**（先跑，无报错才继续）：

```powershell
E:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless --path E:\工作目录\zero\steel_frontline_godot --quit-after 120
```

2. **导出 Windows Desktop**：

```powershell
E:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless --path E:\工作目录\zero\steel_frontline_godot --export-release "Windows Desktop"
```

产物固定输出到 `E:\工作目录\zero\exe\零度行动.exe`。

3. **导出 Web（Windows WebAssembly）**（需要时）：

```powershell
E:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless --path E:\工作目录\zero\steel_frontline_godot --export-release "Web"
```

产物输出到 `E:\工作目录\zero\exe\web\index.html`。

也可以使用编辑器 GUI：Godot → 项目 → 导出 → 选择 `Windows Desktop` 或 `Web` 预设。

## 新增枪械枪声合成教程

> 新增枪械必须使用 `E:\audio.cpp\audio.cpp` 里的合成工具生成专属枪声，不允许拿别的枪声直接改名顶替。

### 1. 生成原始枪声

- 工具：`E:\audio.cpp\audio.cpp\bin\audiocpp_cli.exe`
- 模型：`E:\audio.cpp\audio.cpp\models\Stable-Audio-3-Small-SFX-GGUF\stable-audio-3-small-sfx-q8_0.gguf`

提示词固定用“单发、干净、无其他声音”的格式，并把武器描述写清楚：

```powershell
E:\audio.cpp\audio.cpp\bin\audiocpp_cli.exe `
  --task gen --family stable_audio `
  --model "E:\audio.cpp\audio.cpp\models\Stable-Audio-3-Small-SFX-GGUF\stable-audio-3-small-sfx-q8_0.gguf" `
  --backend cuda `
  --text "A single M249 SAW light machine gun gunshot, one isolated clean gunshot sound effect, loud and clear, no other sounds" `
  --duration-seconds 3 --seed 20260820 `
  --out "E:\audio.cpp\audio.cpp\out\guns\_raw_m249.wav" `
  --metrics
```

- 有 NVIDIA GPU 用 `--backend cuda`；没有就改成 `--backend best` 或 `--backend cpu`。
- 模型输出有静音头/尾，所以先生成 3 秒，再裁成 1 秒。

### 2. 裁成 1 秒

以起振点为基准，保留峰值前 0.1 秒到峰值后 0.9 秒：

```python
import wave
import numpy as np

src = r"E:\audio.cpp\audio.cpp\out\guns\_raw_m249.wav"
dst = r"E:\audio.cpp\audio.cpp\out\guns\m249_new.wav"

with wave.open(src, "rb") as w:
    rate, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
    data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch)

mono = data.mean(axis=1)
onset = int(np.argmax(np.abs(mono) > 1000))       # 起振点
start = max(0, onset - int(rate * 0.1))
trim = data[start:start + rate]                   # 精确 1 秒

with wave.open(dst, "wb") as w:
    w.setnchannels(ch)
    w.setsampwidth(sw)
    w.setframerate(rate)
    w.writeframes(trim.astype(np.int16).tobytes())
```

> 也可以直接改好 `tools/regenerate_gun.py` 里的 `CLI / MODEL / OUT_DIR` 路径后运行，它会自动多候选择优并裁 1 秒。

### 3. 用波形采集器检查效果

用 `scipy + matplotlib` 采集时间域波形和频谱，检查枪声是否可入库：

```python
import math, wave
import numpy as np
from scipy import signal

path = r"E:\audio.cpp\audio.cpp\out\guns\m249_new.wav"
with wave.open(path, "rb") as w:
    rate = w.getframerate()
    data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768.0
    mono = data.reshape(-1, w.getnchannels()).mean(axis=1)

peak = np.max(np.abs(mono))
rms = np.sqrt(np.mean(mono ** 2))
onset = int(np.argmax(np.abs(mono) > 0.05))
seg = mono[onset:onset + int(rate * 0.3)]
spec = np.abs(np.fft.rfft(seg * signal.windows.hann(seg.size)))
centroid = np.sum(np.fft.rfftfreq(seg.size, 1 / rate) * spec) / max(np.sum(spec), 1e-9)
print("peak=%.2f dBFS rms=%.2f dBFS crest=%.2f onset=%.2f ms centroid=%.0f Hz" % (
    20 * math.log10(max(peak, 1e-9)), 20 * math.log10(max(rms, 1e-9)),
    peak / max(rms, 1e-9), onset / rate * 1000.0, centroid))
```

参考验收标准（实测 M249 合成样本）：

| 指标 | 合格范围 | 实测值 |
|---|---|---|
| 峰值 | ≥ -3 dBFS | -0.00 dBFS |
| RMS | -18 ~ -8 dBFS | -10.46 dBFS（1s 版） |
| 峰值因数 | 3 ~ 8 | 3.33（1s 版） |
| 起振点 | < 100 ms | 5.56 ms |
| 频谱质心 | 4000 ~ 9000 Hz | 约 6500 Hz |

如果峰值太弱（低于 -25 dBFS）就换 seed / 改提示词重新生成，不要强行放大噪声。

### 4. 接入游戏

1. 把裁好的 WAV 放到 `steel_frontline_godot/audio/guns/<weapon_id>.wav`；
2. 有 ffmpeg 时转一份 OGG：`ffmpeg -i <weapon_id>.wav -c:a libvorbis -q:a 6 <weapon_id>.ogg`；
3. 在 `src/autoload/audio_sys.gd` 的 `GUN_SOUND_FILES` 注册：`"<weapon_id>": "<weapon_id>"`；
4. 如果峰值明显偏低，在 `GUN_GAIN` 按文件名加增益补偿；
5. 走一遍本 README 的“无头测试 → 导出”发布流程。

### 5. 换弹动作音效

换弹动作音效使用 `E:\audio.cpp\audio.cpp\tools\gen_reload_sfx.py` 批量生成：每个动作生成 3 个候选、自动选峰值最高的一版，并按游戏内对应换弹阶段的实际时长裁剪（弹匣拔插 0.35~0.45s，弹鼓/弹链/供弹盖动作 0.9~1.1s）。生成结果在 `steel_frontline_godot/audio/reload/`，由 `src/autoload/audio_sys.gd` 的 `RELOAD_ACTION_FILES` 注册，`WeaponReloadController` 按阶段调用 `AudioSys.reload_action()`。

### 6. 泵动霰弹枪 / 左轮扩展音效

新增的 3 把泵动霰弹枪与 3 把左轮手枪使用 `tools/gen_shotgun_revolver_audio.py` 走同一 Stable Audio CLI 生成专属枪声与逐阶段机械音（泵动后拉/前推/闭锁、弹巢开合/甩壳/逐发装填/快速装弹器/击锤/换膛）。产物直接写入 `audio/guns/` 与 `audio/reload/`，运行时优先加载 AI 合成文件；文件缺失时才回退到 `AudioSys` 内置的程序化合成器，保证导出包不会静音。

## 版权

本仓库源码仅供学习交流。游戏音频/字体资源版权归各自作者所有。
