# Generate dedicated gunshot + reload foley audio for the [9/10] pump-shotgun
# and revolver pack. Uses the same Stable Audio CLI documented in README.md:
#   raw 3s Stable Audio SFX -> pick best variant by peak dBFS -> trim to real duration.
# Output goes directly into the game audio folders:
#   audio/guns/<weapon_id>.wav
#   audio/reload/<action>.wav
import os
import subprocess
import sys
import wave

import numpy as np

CLI = r"E:\audio.cpp\audio.cpp\bin\audiocpp_cli.exe"
MODEL = r"E:\audio.cpp\audio.cpp\models\Stable-Audio-3-Small-SFX-GGUF\stable-audio-3-small-sfx-q8_0.gguf"
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUN_DIR = os.path.join(PROJECT, "audio", "guns")
RELOAD_DIR = os.path.join(PROJECT, "audio", "reload")
RAW_DIR = os.path.join(PROJECT, "audio", "_gen_raw")
GUN_VARIANTS = 2
FOLEY_VARIANTS = 1

GUNS = [
    ("rem870", "Remington 870 pump-action 12 gauge shotgun"),
    ("m590", "Mossberg 590A1 heavy barrel pump-action 12 gauge shotgun"),
    ("win1897", "Winchester model 1897 trench pump-action 12 gauge shotgun"),
    ("python", "Colt Python 357 magnum revolver with six inch barrel"),
    ("sw686", "Smith and Wesson model 686 stainless steel 357 magnum revolver with four inch barrel"),
    ("sw500", "Smith and Wesson model 500 five shot 500 magnum revolver with long barrel"),
]

# (file_stem, target_seconds, english prompt)
RELOAD_SOUNDS = [
    # ---- per-shotgun shell loading ----
    ("shell_grab_rem870", 0.35, "A 12 gauge shotgun shell grabbed from a shell carrier, short plastic and brass shell handling click, isolated weapon foley sound effect, no other sounds"),
    ("shell_insert_rem870", 0.35, "A 12 gauge shotgun shell pushed into a Remington 870 loading port, short plastic and steel insertion click, isolated weapon foley sound effect, no other sounds"),
    ("shell_grab_m590", 0.35, "A 12 gauge shotgun shell grabbed from a heavy duty shell carrier, short plastic and brass shell handling click, isolated weapon foley sound effect, no other sounds"),
    ("shell_insert_m590", 0.35, "A 12 gauge shotgun shell pushed into a Mossberg 590 loading port, short plastic and steel insertion click, isolated weapon foley sound effect, no other sounds"),
    ("shell_grab_win1897", 0.35, "A 12 gauge brass shotgun shell grabbed from an old leather shell belt, short brass shell handling click, isolated weapon foley sound effect, no other sounds"),
    ("shell_insert_win1897", 0.35, "A 12 gauge brass shotgun shell pushed into a Winchester 1897 loading port, short brass and old steel insertion click, isolated weapon foley sound effect, no other sounds"),
    # ---- per-shotgun pump mechanics ----
    ("pump_back_rem870", 0.38, "A Remington 870 pump-action shotgun forend racked sharply backward, one metallic pump slide clack, isolated weapon foley sound effect, no other sounds"),
    ("pump_fwd_rem870", 0.30, "A Remington 870 pump-action shotgun forend pushed forward into battery, one metallic pump slide clack, isolated weapon foley sound effect, no other sounds"),
    ("pump_finish_rem870", 0.26, "A Remington 870 pump-action shotgun action locking closed, one short metallic bolt lock click, isolated weapon foley sound effect, no other sounds"),
    ("pump_back_m590", 0.40, "A heavy Mossberg 590A1 pump-action shotgun forend racked backward, deep metallic pump slide clack, isolated weapon foley sound effect, no other sounds"),
    ("pump_fwd_m590", 0.32, "A heavy Mossberg 590A1 pump-action shotgun forend pushed forward into battery, deep metallic pump slide clack, isolated weapon foley sound effect, no other sounds"),
    ("pump_finish_m590", 0.28, "A heavy Mossberg 590A1 pump-action shotgun action locking closed, deep short metallic bolt lock click, isolated weapon foley sound effect, no other sounds"),
    ("pump_back_win1897", 0.42, "A Winchester 1897 old western pump-action shotgun forend racked backward, metallic slide and exposed hammer click, isolated weapon foley sound effect, no other sounds"),
    ("pump_fwd_win1897", 0.34, "A Winchester 1897 old western pump-action shotgun forend pushed forward into battery, metallic slide clack, isolated weapon foley sound effect, no other sounds"),
    ("pump_finish_win1897", 0.28, "A Winchester 1897 pump-action shotgun action locking closed with an old steel bolt click, isolated weapon foley sound effect, no other sounds"),
    # ---- revolver cylinder mechanics (python = classic blued, 686 = stainless, 500 = heavy X-frame) ----
    ("revolver_open_python", 0.55, "A Colt Python revolver cylinder released and swung out to the left, cylinder crane latch click and short metal swing, isolated weapon foley sound effect, no other sounds"),
    ("revolver_close_python", 0.50, "A Colt Python revolver cylinder pushed closed and locked into the frame, one firm metallic latch clack, isolated weapon foley sound effect, no other sounds"),
    ("revolver_eject_python", 0.55, "Six empty revolver cartridge cases ejected by a cylinder ejector rod, short brass cases falling clatter, isolated weapon foley sound effect, no other sounds"),
    ("revolver_round_python", 0.42, "A single 357 magnum revolver cartridge grabbed between fingers, small brass handling click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_insert_python", 0.40, "A single 357 magnum revolver cartridge pushed into an empty revolver cylinder chamber, short brass seat click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_loader_python", 0.80, "A six round revolver speedloader pressed into a revolver cylinder and released, brass rounds sliding and loader click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_hammer_python", 0.25, "A Colt Python revolver hammer cocked back with one sharp metallic click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_rotate_python", 0.30, "A revolver cylinder rotating one chamber with a short precise mechanical ratchet click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_open_sw686", 0.55, "A stainless steel Smith and Wesson 686 revolver cylinder released and swung out to the left, light metal latch click and swing, isolated weapon foley sound effect, no other sounds"),
    ("revolver_close_sw686", 0.50, "A stainless steel Smith and Wesson 686 revolver cylinder pushed closed and locked, one light firm stainless latch clack, isolated weapon foley sound effect, no other sounds"),
    ("revolver_eject_sw686", 0.55, "Six revolver cartridge cases ejected by a stainless revolver ejector rod, brass cases falling clatter, isolated weapon foley sound effect, no other sounds"),
    ("revolver_round_sw686", 0.42, "A single 357 magnum revolver cartridge picked from a belt ammo pouch, small brass handling click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_insert_sw686", 0.40, "A single 357 magnum revolver cartridge inserted into a stainless revolver chamber, short brass seat click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_loader_sw686", 0.80, "A six round revolver speedloader pressed into a stainless revolver cylinder and released, brass rounds sliding and loader click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_hammer_sw686", 0.25, "A stainless steel Smith and Wesson revolver hammer cocked back with one light sharp metallic click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_rotate_sw686", 0.30, "A stainless steel revolver cylinder rotating one chamber with a short light ratchet click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_open_sw500", 0.60, "A heavy Smith and Wesson 500 revolver cylinder released and swung out to the left, deep heavy metal latch clack and swing, isolated weapon foley sound effect, no other sounds"),
    ("revolver_close_sw500", 0.55, "A heavy Smith and Wesson 500 revolver cylinder pushed closed and locked, one deep heavy metallic latch clack, isolated weapon foley sound effect, no other sounds"),
    ("revolver_eject_sw500", 0.60, "Five heavy 500 magnum revolver cartridge cases ejected by a revolver ejector rod, deep brass cases falling clatter, isolated weapon foley sound effect, no other sounds"),
    ("revolver_round_sw500", 0.48, "A single heavy 500 magnum revolver cartridge grabbed from a belt pouch, heavy brass handling click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_insert_sw500", 0.45, "A single heavy 500 magnum revolver cartridge pushed into an empty revolver chamber, heavy brass seat click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_loader_sw500", 0.90, "A five round heavy revolver speedloader pressed into a Smith and Wesson 500 cylinder and released, heavy brass rounds sliding and loader click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_hammer_sw500", 0.30, "A heavy Smith and Wesson 500 revolver hammer cocked back with one deep metallic click, isolated weapon foley sound effect, no other sounds"),
    ("revolver_rotate_sw500", 0.32, "A heavy five shot revolver cylinder rotating one chamber with a deep ratchet click, isolated weapon foley sound effect, no other sounds"),
]


def peak_db(path):
    with wave.open(path, "rb") as w:
        n = w.getnframes()
        ch = w.getnchannels()
        data = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64).reshape(-1, ch)
    mono = data.mean(axis=1) / 32768.0
    peak = float(np.max(np.abs(mono)))
    return 20.0 * np.log10(max(peak, 1e-9))


def trim(src, dst, seconds, gun=True):
    with wave.open(src, "rb") as w:
        rate = w.getframerate()
        ch = w.getnchannels()
        sw = w.getsampwidth()
        n = w.getnframes()
        data = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64).reshape(-1, ch)
    mono = data.mean(axis=1)
    win = max(1, rate // 100)
    env = np.array([np.max(np.abs(mono[i * win:(i + 1) * win])) for i in range(mono.size // win)])
    peak_i = int(np.argmax(env))
    thresh = max(float(env[peak_i]) * 0.15, 0.003)
    onset_i = peak_i
    for i in range(peak_i, -1, -1):
        onset_i = i
        if float(env[i]) < thresh:
            break
    lead = int(rate * (0.1 if gun else 0.08))
    start = max(0, onset_i * win - lead)
    want = int(rate * seconds)
    trim_data = data[start:start + want]
    if trim_data.shape[0] < want:
        pad = np.zeros((want - trim_data.shape[0], ch), dtype=np.float64)
        trim_data = np.vstack([trim_data, pad])
    with wave.open(dst, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(sw)
        w.setframerate(rate)
        w.writeframes(trim_data.astype(np.int16).tobytes())


def run_cli(out, prompt, seed, duration=3):
    return subprocess.run(
        [CLI, "--task", "gen", "--family", "stable_audio", "--model", MODEL,
         "--backend", "cuda", "--text", prompt, "--duration-seconds", str(duration),
         "--seed", str(seed), "--out", out],
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900,
    )


def make_final(name, desc, out_dir, seconds, variants, gun):
    final = os.path.join(out_dir, f"{name}.wav")
    if os.path.exists(final):
        print(f"  {name}: exists, skip", flush=True)
        return True
    prompt = f"A single {desc} gunshot, one isolated clean gunshot sound effect, loud and clear, no other sounds" if gun else desc
    if not gun:
        prompt = prompt.replace("isolated foley sound effect", "loud and clear isolated foley sound effect")
        prompt = prompt.replace("isolated weapon foley sound effect", "loud and clear isolated weapon foley sound effect")
    best_raw = None
    best_db = -999.0
    for v in range(variants):
        raw = os.path.join(RAW_DIR, f"{name}_v{v}.wav")
        seed = 20260900 + (abs(hash(name)) % 4000) + v * 137
        r = run_cli(raw, prompt, seed, 3)
        if r.returncode != 0 or not os.path.exists(raw):
            print(f"    variant {v} FAILED rc={r.returncode}", flush=True)
            continue
        db = peak_db(raw)
        print(f"    variant {v}: peak {db:.2f} dBFS", flush=True)
        if db > best_db:
            best_db = db
            best_raw = raw
        else:
            try:
                os.remove(raw)
            except OSError:
                pass
    if best_raw is None:
        print(f"  {name}: ALL VARIANTS FAILED", flush=True)
        return False
    try:
        trim(best_raw, final, seconds, gun=gun)
        os.remove(best_raw)
    except Exception as exc:
        print(f"  {name}: TRIM FAILED {exc}", flush=True)
        return False
    print(f"  {name}: OK {best_db:.2f} dBFS -> {final}", flush=True)
    return True


def main():
    os.makedirs(RAW_DIR, exist_ok=True)
    os.makedirs(GUN_DIR, exist_ok=True)
    os.makedirs(RELOAD_DIR, exist_ok=True)
    ok = 0
    fail = 0
    print("== gunshots ==", flush=True)
    for stem, desc in GUNS:
        print(f"[gun] {stem}", flush=True)
        if make_final(stem, desc, GUN_DIR, 1.0, GUN_VARIANTS, True):
            ok += 1
        else:
            fail += 1
    print("== reload foley ==", flush=True)
    for stem, seconds, prompt in RELOAD_SOUNDS:
        print(f"[foley] {stem} ({seconds:.2f}s)", flush=True)
        if make_final(stem, prompt, RELOAD_DIR, seconds, FOLEY_VARIANTS, False):
            ok += 1
        else:
            fail += 1
    print(f"\nDONE ok={ok} fail={fail}", flush=True)
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
