"""Builds OpenNPC.esp and installs the mod into a Morrowind folder (the test copy), and adds the plugin to that folder's
Morrowind.ini. With --test it also installs the in-game tests and turns them on; without it, they're removed.

    python tools/deploy.py <Morrowind folder> [--test]
"""
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = "OpenNPC.esp"


def copy_tree(src, dst):
    n = 0
    for base, _, files in os.walk(src):
        for f in files:
            s = os.path.join(base, f)
            d = os.path.join(dst, os.path.relpath(s, src))
            os.makedirs(os.path.dirname(d), exist_ok=True)
            shutil.copy2(s, d)
            n += 1
    return n


def add_plugin_to_ini(game):
    ini = os.path.join(game, "Morrowind.ini")
    with open(ini, "rb") as f:
        lines = f.read().decode("cp1252").replace("\r\n", "\n").split("\n")   # (written back with Windows line ends)
    start = next(i for i, l in enumerate(lines) if l.strip().lower() == "[game files]")
    end = start + 1
    while end < len(lines) and lines[end].strip().lower().startswith("gamefile"):
        end += 1
    entries = [l.split("=", 1)[1].strip().lower() for l in lines[start + 1:end] if "=" in l]
    if PLUGIN.lower() in entries:
        return False
    lines.insert(end, f"GameFile{end - start - 1}={PLUGIN}")
    with open(ini, "wb") as f:
        f.write("\r\n".join(lines).encode("cp1252"))
    return True


def main():
    game = sys.argv[1]
    test = "--test" in sys.argv
    data = os.path.join(game, "Data Files")
    esp = os.path.join(ROOT, "mod", "Data Files", PLUGIN)
    subprocess.run([sys.executable, "-I", os.path.join(ROOT, "tools", "make_esp.py"), os.path.join(data, "Morrowind.esm"), esp], check=True)
    n = copy_tree(os.path.join(ROOT, "mod", "Data Files"), data)
    print(f"installed {n} mod files into {data}")
    print("plugin added to Morrowind.ini" if add_plugin_to_ini(game) else "plugin already in Morrowind.ini")
    flag = os.path.join(data, "MWSE", "opennpc_test.run")
    results = os.path.join(data, "MWSE", "opennpc_test_results.txt")
    if os.path.exists(results):
        os.remove(results)
    test_dir = os.path.join(data, "MWSE", "mods", "opennpc_test")
    # (her settings: with the tests she asks the stand-in AI on port 41799; without them, the defaults: a voice app on 41751)
    cfg = os.path.join(data, "MWSE", "config", "Open NPC.json")
    if test:
        os.makedirs(os.path.dirname(cfg), exist_ok=True)
        with open(cfg, "w", encoding="utf-8") as f:
            json.dump({"name": "Ana", "url": "http://127.0.0.1:41799/v1", "key": "", "model": "", "useAppName": True}, f, indent=2)
        print("her AI for the tests: the stand-in on 127.0.0.1:41799")
    elif os.path.exists(cfg):
        os.remove(cfg)
        print("her settings back to the defaults (AI at 127.0.0.1:41751)")
    if test:
        n = copy_tree(os.path.join(ROOT, "test", "Data Files"), data)
        open(flag, "w").close()
        print(f"tests installed ({n} files) and turned on")
    else:
        if os.path.isdir(test_dir):
            shutil.rmtree(test_dir)
        if os.path.exists(flag):
            os.remove(flag)
        print("tests removed")


if __name__ == "__main__":
    main()
