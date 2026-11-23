"""Writes OpenNPC.esp: one plugin with the companion's own NPC records (Morrowind can't make a new person at run time),
one for each race she can be: the game can't change a person's race while it runs, so picking a race in her look menu
swaps her for that race's copy. Her first face and hair for each race are that race's first women's ones in Morrowind.esm.

Layouts checked against the game's own Morrowind.esm and Tribunal.esm (tools/esm_peek.py): HEDR version 1.3, file type 0 for a
plugin, record count without the TES3 header, strings null-terminated with the null counted, NPDT 12 bytes when her stats are
worked out by the game from her level and class (the autocalc flag), NPCO = int32 count + 32-byte item id.

    python tools/make_esp.py <path to Morrowind.esm> <output .esp>
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from esm_peek import records, zs  # noqa: E402

NPC_ID = "opennpc_companion"   # (the Imperial one; the first record, from before she had other races)
RACES = ["Argonian", "Breton", "Dark Elf", "High Elf", "Imperial", "Khajiit", "Nord", "Orc", "Redguard", "Wood Elf"]


def record_id(race):
    return NPC_ID if race == "Imperial" else NPC_ID + "_" + "".join(c for c in race.lower() if c.isalpha())


def first_faces(esm):
    """{race: (head id, hair id)}: the first (by id) playable women's head and hair of each race."""
    found = {}
    for rtype, flags, subs in records(esm):
        if rtype != "BODY":
            continue
        d = dict((st, sd) for st, sd in subs)
        b = d.get("BYDT", bytes(4))
        part, vampire, fl, ptype = b[0], b[1], b[2], b[3]
        # (skin layer, head 0 or hair 1, female flag 1, not the "not playable" flag 2, not a vampire's)
        if ptype != 0 or part not in (0, 1) or not (fl & 1) or (fl & 2) or vampire:
            continue
        race, bid = zs(d.get("FNAM", b"")), zs(d.get("NAME", b""))
        found.setdefault((race, part), []).append(bid)
    return {r: (sorted(found[(r, 0)], key=str.lower)[0], sorted(found[(r, 1)], key=str.lower)[0]) for r in RACES}


def sub(tag, data):
    return tag.encode("ascii") + struct.pack("<I", len(data)) + data


def zstr(s):
    return s.encode("latin1") + b"\0"


def fixed(s, n):
    b = s.encode("latin1")[: n - 1]
    return b + b"\0" * (n - len(b))


def record(tag, subs, flags=0):
    body = b"".join(subs)
    return tag.encode("ascii") + struct.pack("<III", len(body), 0, flags) + body


def companion(race, head, hair):
    items = [
        "common_shirt_04_b",
        "common_pants_01",
        "netch_leather_boots",
        "netch_leather_cuirass",
        "imperial shortsword",
    ]
    subs = [
        sub("NAME", zstr(record_id(race))),
        sub("FNAM", zstr("Ana")),            # (her shown name; the mod renames her from its settings, and later from the voice app)
        sub("RNAM", zstr(race)),
        sub("CNAM", zstr("Warrior")),
        sub("ANAM", zstr("")),               # (no faction)
        sub("BNAM", zstr(head)),
        sub("KNAM", zstr(hair)),
        # level 5, disposition 70, reputation 0, rank 0, 3 pad bytes, gold 0
        sub("NPDT", struct.pack("<hBBB3xi", 5, 70, 0, 0, 0)),
        # female 0x01 + base 0x08 + autocalc 0x10 (as the game's own autocalc NPCs)
        sub("FLAG", struct.pack("<I", 0x01 | 0x08 | 0x10)),
    ]
    for it in items:
        subs.append(sub("NPCO", struct.pack("<i", 1) + fixed(it, 32)))
    # hello 30, fight 30, flee 30, alarm 0 (she never reports him), 3 pad bytes, no services
    subs.append(sub("AIDT", struct.pack("<HBBB3xi", 30, 30, 30, 0, 0)))
    return record("NPC_", subs)


def header(master_name, master_size, n_records):
    hedr = struct.pack("<fI", 1.3, 0) + fixed("Open NPC", 32) + fixed("A companion who plays the whole game with you.", 256) + struct.pack("<I", n_records)
    return record("TES3", [sub("HEDR", hedr), sub("MAST", zstr(master_name)), sub("DATA", struct.pack("<Q", master_size))])


def main():
    esm, out = sys.argv[1], sys.argv[2]
    faces = first_faces(esm)
    # (the Imperial record keeps the face and hair she had before)
    faces["Imperial"] = ("b_n_imperial_f_head_02", "b_n_imperial_f_hair_01")
    recs = [companion("Imperial", *faces["Imperial"])] + [companion(r, *faces[r]) for r in RACES if r != "Imperial"]
    data = header(os.path.basename(esm), os.path.getsize(esm), len(recs)) + b"".join(recs)
    with open(out, "wb") as f:
        f.write(data)
    print(f"wrote {out}: {len(data)} bytes, {len(recs)} record(s)")


if __name__ == "__main__":
    main()
