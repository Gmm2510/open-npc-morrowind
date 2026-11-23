# open-npc-morrowind

A companion for The Elder Scrolls III: Morrowind who plays the whole game with you, like a sidekick: she follows you, waits
when you tell her to, fights beside you, levels up with you, and never gets lost, on silt striders and boats, through doors,
while you levitate or swim. An AI can drive her, and a voice app on your PC can let you talk to her out loud. Free and open
source (MIT). Part of [Open NPC](https://github.com/Gmm2510/open-npc).

## What she does

- **Shows up** next to you once your character is made, in an old save too.
- **Follows** you on foot, **waits** where you tell her, and **comes** when called, from anywhere.
- **Fights** whatever attacks you, and helps when you start a fight.
- **Levels up with you:** more health, stronger, better with blades, armor and running. Her level-ups stay with her for good.
- **Never dies for good:** a hit that would kill her knocks her down instead. While she's down nothing hurts her, and she gets
  back up when the fight around you is over (30 seconds at most) with part of her health. If she's killed some other way, she
  comes back next to you a few seconds later, as she was.
- **Never gets lost:**
  - Silt striders and boats take her along (the game does it when she's following close by); if she was left behind, even
    indoors somewhere else, she turns up next to you when you arrive.
  - Doors: she comes through with you, both ways.
  - Recall, Intervention and other long jumps: she turns up next to you.
  - Levitating: she stays on the ground under you instead of being put up in the air, keeps up below you when you fly off, and
    comes up to you when you land somewhere she can't walk to (a roof, a tower floor).
  - Swimming: she comes to you at the surface, never sinks to the bottom, and doesn't drown under water with you.
  - Stuck behind something: after a few seconds she comes over to you.
- **Her look:** pick her race, face, hair and outfit in **Esc > Mod Config > Open NPC**, from the game's own faces, hair styles,
  clothes and armor. Each companion name keeps her own look.

## What you need

- Morrowind (the Game of the Year edition from Steam or GOG). Tribunal and Bloodmoon are not needed.
- [MWSE](https://github.com/MWSE/MWSE) 2.1 (the Morrowind Script Extender, its latest build) and
  [MGE XE](https://www.nexusmods.com/morrowind/mods/41102), which loads it. The
  [Morrowind Code Patch](https://www.nexusmods.com/morrowind/mods/19510) is recommended.
- For her to act on what you say: an AI that speaks the OpenAI-style "chat completions" API with tool calls, and a voice app on
  your PC that serves the wait door (below). Without them she still follows, waits and fights; you tell her through her own menu.

## Install

1. Download the zip from the [Releases page](https://github.com/Gmm2510/open-npc-morrowind/releases).
2. Unzip it into your Morrowind folder (the one with `Morrowind.exe`), so its `Data Files` folder merges with yours.
3. In the Morrowind Launcher, **Data Files**, tick `OpenNPC.esp`.
4. Start the game and load a save (or start a new one). She shows up next to you.

Talk to her (activate her) for her menu: **Follow me**, **Wait here**, **Talk** (the game's own talk), **Never mind**.

## Settings

The first start writes `Data Files\MWSE\config\Open NPC.json`:

```json
{
  "name": "Ana",
  "useAppName": true,
  "url": "http://127.0.0.1:41751/v1",
  "key": "",
  "model": "",
  "looks": {}
}
```

- `name`: her name in the game.
- `useAppName`: `true` lets a voice app with the wait door (below) name her: the companion picked in that app, changed in the
  game the moment you pick another.
- `url`: the AI's address, ending in `/v1`. For example `https://api.openai.com/v1`, `https://openrouter.ai/api/v1`, a model
  on your own PC (LM Studio, Ollama and llama.cpp all serve this API), or a voice app on your PC.
- `key`: the API key for that address, or empty.
- `model`: the model name. Empty: the first one the address lists.
- `looks`: each companion's look, by name. Set them in the look menu (Esc > Mod Config > Open NPC).

## What the AI hears and can do

When she asks, the AI hears who she is (health, level, following or waiting, who she's fighting), how you are, where you both
are (the place and region), the time of day, how far apart you are, who's nearby, what happened lately (doors, travel, fights,
level-ups, your journal, being knocked down and getting up) and what she was told lately. It answers with the `act` tool: `follow`, `wait`, `come`, `fight`
or `stop_fighting`.

### Voice apps: the wait door

She asks the AI the moment you speak to her. An app that hears you some other way, like a voice call app on your PC, can
serve one more address next to the AI: `GET <url>/wait`.

- `GET /wait` answers right away with `{ "call": true|false, "words": <number> }`, plus `"name": "<her name>"` if the app
  names her.
- `GET /wait?since=<words>&call=<0|1>&ms=<up to 25000>` answers as soon as `words` grows past `since` (you said something),
  `call` changes or her name changes, or after `ms`.

When it answers she asks the AI at once, and the app adds your words to that question. When the address has the door, she
shows no words on screen (the app speaks for her). The game never waits for the AI: every request runs in the background.

## If the game crashes at loading screens

On some PCs (Intel graphics, for example) Morrowind's own renderer crashes when Windows says the graphics device was lost,
with or without mods. [DXVK](https://github.com/doitsujin/dxvk)'s 32-bit `d3d9.dll` in the Morrowind folder fixed it for us.

## Build and test

Needs Python 3 and the game's own `Morrowind.esm`.

```bash
python tools/make_esp.py "<Morrowind>/Data Files/Morrowind.esm" "mod/Data Files/OpenNPC.esp"   # her records
python tools/deploy.py "<a copy of Morrowind>" --test   # install into a test copy, with the in-game tests
python tools/package.py "<Morrowind>/Data Files/Morrowind.esm"   # the release zip, in dist/
```

The in-game tests run in a copy of the game (never your own install), from a save named in
`Data Files\MWSE\opennpc_test.save`: `tools\run_tests.ps1 -Game <copy> -StandIn` starts the game, plays a stand-in AI
(`tools/standin_ai.js`, Node) and writes the results to `Data Files\MWSE\opennpc_test_results.txt`. They check, in the real
game: she shows up, takes the app's name, acts on words through the wait door (wait, follow, fight), hears where she is;
walks after you, follows, waits, comes through doors both ways, stays behind when waiting, comes when called, comes along on a
long jump, fights what attacks you, levels up; stays on the ground while you levitate, keeps up under you, gets up to a high
place; comes along on a silt strider and a boat (through the game's own travel menus) and isn't left behind; keeps her
level-ups after time apart; comes to you in the water at the surface; doesn't drown; is never hurt by a fall or by drowning;
her look menu changes her face, hair and outfit, a new race swaps her and keeps what's hers, each companion keeps her own look;
goes down instead of dying, takes no hits while down, stays down while a fight goes on and gets up after, comes back if killed;
and all of it after saving and loading. The look checks also take photos (the runner saves them in a
`morrowind-work\photos` folder next to the copy).

## License

MIT. Her records are new; everything she looks like and wears is the game's own. No other mod's code or assets are in it.
