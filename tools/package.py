"""Builds the release zip: dist/open-npc-morrowind-<version>.zip, to unzip into a Morrowind folder.

It holds Data Files/OpenNPC.esp (built fresh from the game's own Morrowind.esm), the mod's Lua files under
Data Files/MWSE/mods/opennpc, README.md and LICENSE. No tests, no tools.

    python tools/package.py <path to Morrowind.esm>
"""
import os
import subprocess
import sys
import zipfile

VERSION = "0.1.2"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    esm = sys.argv[1]
    esp = os.path.join(ROOT, "mod", "Data Files", "OpenNPC.esp")
    subprocess.run([sys.executable, "-I", os.path.join(ROOT, "tools", "make_esp.py"), esm, esp], check=True)
    dist = os.path.join(ROOT, "dist")
    os.makedirs(dist, exist_ok=True)
    out = os.path.join(dist, f"open-npc-morrowind-{VERSION}.zip")
    files = [(esp, "Data Files/OpenNPC.esp")]
    lua = os.path.join(ROOT, "mod", "Data Files", "MWSE", "mods", "opennpc")
    for name in sorted(os.listdir(lua)):
        if name.endswith(".lua"):
            files.append((os.path.join(lua, name), "Data Files/MWSE/mods/opennpc/" + name))
    files += [(os.path.join(ROOT, "README.md"), "README.md"), (os.path.join(ROOT, "LICENSE"), "LICENSE")]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arc in files:
            z.write(src, arc)
    print(f"wrote {out}: {len(files)} files, {os.path.getsize(out)} bytes")
    for _, arc in files:
        print("  " + arc)


if __name__ == "__main__":
    main()
