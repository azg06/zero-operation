# 项目协作规范（AGENTS.md）

## 打包同步约定（强制）

**所有对本项目的修改（代码/资源/场景/配置）完成后，必须同步重新打包 Windows exe。**

- 输出目录：`E:\工作目录\exe`
- 导出命令：
  `& "E:\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\工作目录\steel_frontline_godot" --export-release "Windows Desktop" "E:\工作目录\exe\零度行动.exe"`
- 导出预设：Windows Desktop（`export_presets.cfg`，embed_pck=true 单文件自包含）
- 验收步骤：
  1. 命令 EXIT=0 且输出 `[ DONE ] savepack`
  2. 确认 `E:\工作目录\exe\零度行动.exe` 已更新（LastWriteTime）
  3. 启动 exe 确认进程稳定运行无崩溃（Start-Process + 8s 存活检测后关闭）

## 常用验证命令

- 冒烟测试：`& "E:\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\工作目录\steel_frontline_godot" --script "res://fx_smoke_test.gd"`
- 模式试玩（注意 `--quit-after` 放在 `--` 之前）：`--headless --quit-after 500 -- --test-play conquest|breakthrough|campaign`
