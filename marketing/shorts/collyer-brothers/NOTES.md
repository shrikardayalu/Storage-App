# The Trap That Caught Its Maker (Collyer brothers): build notes

## Where things are
- **Remotion project** (outside this repo, on purpose): `C:\Users\shrik\shorts-studio`
  - Scenes: `src/videos/collyer/` (`story.ts` shots, cameras, lens, the parlor's clutter level per shot; `world.ts` sets
    and moving props; `cast.ts` characters and effect cards; `paint.ts` textures; `lights.ts` light presets). Built
    from the Vivian folder; the post chain, captions and phone are the same. Characters use `geniza/toon.ts`, which
    gained a firefighter's helmet (`hat: "firehelmet"`).
  - Voice and sound: `collyer/` (`script.txt`, `timing.py`, `align.py`, `audio.py`, `scratch_voice.ps1`, `scratch_fit.py`).
  - Renders: `out/collyer/` (`video.mp4` picture, `final.mp4` with sound, stills and contact sheets).
  - One command for render, mux, 1080p preview, motion stats and QA: `bash scripts/final_collyer.sh <preview name>`.
- Composition: `CollyerShort`, 1080x1920 at 30 fps, rendered at 1440x2560.

## Shots (20)
Tunnel hook (Langley ties the wire, the leaning stack tips on "instead") → Homer in his chair by candle → the 1900s
stoop (faded like an old photo) → Langley walks blind Homer to the chair → the crate of oranges tips → he stacks the
first newspapers → the UNPAID bill drops → the lights cut out mid-move and the piles grow → dolly through the hoard
(pianos, books, specimen jars, the Model T chassis, each on its word) → night street, neighbours point at the one
candlelit window → Langley strings a tripwire → the police car, the knock → the ladder to the second floor → the empty
chair, an officer with his cap off → the crowd with newspapers → workers' torch down the tunnel to the fallen stack and
the spilled tray (an orange, bread; nothing gory) → the truck hauled away full → a firefighter's helmet light down a
packed modern hallway → the emptied parlor, one tied bundle on his chair → the phone rises over it for the plug.

## Sets (one world, side by side, every floor clear of the next)
- **Tunnel** (x 0): 1.5 m wide between walls of tied bundles, planks and papers over the top, a candle on a ledge.
  The wire at ankle height, the trap stack leaning off the right wall, and the heap with the spilled tray (shot 16 only).
- **Parlor** (x 400): papered walls, the back window (day / night glass), chandelier, Homer's armchair, side table with
  the candle and plate, grand piano, rug. 40 newspaper stacks on three levels; `clutterAt(id, f)` in story.ts sets how
  full the room is per shot (clean → first walls → grown → packed in 1947 → emptied at the end).
- **Street** (x -400): a brownstone row, the Collyer house at z 0..7 with three fronts (1900s, 1947 boarded and grimy,
  night with one candlelit window), its stoop, trees (leaves only in the 1900s), lamp posts (lit at night), the police
  car, the ladder, the pile of bundles, the truck.
- **Hoard** (x 800): a long room the dolly runs down; each thing sits on its own side so the camera turns to it.
- **Hallway** (x 1200): a narrow modern corridor with boxes and bags on both sides, ceiling panels, a door at the end.

## Status (2026-11-27, v1)
- Script approved with hook A; built with placeholder timings (3.7 words/s, 72.3 s) and a Windows scratch voice.
- Scratch cut: `collyer-v1-scratch-voice.mp4` in this folder (not in git); full size at
  `C:/Users/shrik/shorts-studio/out/collyer/final.mp4`.
- Checks: motion median 4.0, still frames 0.6 %, -15.2 LUFS, peak -1.1 dBFS, no silences, no black, white or frozen
  frames. One hard cut, on purpose: the lights going out ("lights", frame 796 at placeholder timing).
- Fixed after the first render: a missing dissolve into the bills shot, and a worker card that sat a metre from the
  lens in the tunnel discovery shot (removed; only the torch light moves there now).
- Waiting on the real narration (VOICE_SCRIPT.md).
- Post caption (draft): The brothers who booby-trapped their own house 🕯️ #history #truecrime #nyc #iphonestorage.
  On TikTok, switch on the "Your brand" content disclosure.

## From voice to finished video
1. Save the narration as `C:\Users\shrik\shorts-studio\collyer\voice\voice.wav`.
2. `python collyer/align.py` gets Whisper word times and aligns them to `script.txt` (check line-first words; Whisper
   has put them late before).
3. `python collyer/timing.py collyer/voice/words.json` rewrites `timing.ts`; every shot, effect and caption follows it.
4. Check stills at the cue words (`BRIDGE_COMP=CollyerShort node scripts/bridge-stills.mjs ...`).
5. `python collyer/audio.py` re-mixes the voice with the score and effects.
6. `bash scripts/final_collyer.sh collyer-v2-final` renders and runs the checks.

## Lessons from this build
- Characters card scale is easy to misjudge in a tunnel: a 2 m card 2.5 m from a 58° lens fills the frame. Keep the
  camera 4+ m back from anyone it isn't meant to close in on.
- A camera that trucks along the road will drive straight through a parked car: move props out of every path a later
  shot's camera takes, not just the shot they belong to.
- The Smithsonian `windows()` texture reads as a dotted grid on whole facades; a painted front with a few big windows
  per floor (`facade()` in paint.ts) reads as a brownstone.

## Plan usage (Pro)
- Script phase start: 5-hour window 2 %, weekly 26 % (2026-11-27).
- Scratch cut done (five new sets, new characters and props, three still rounds, two full renders): 5-hour window
  2 % -> 22 %, weekly 26 % -> 29 %.
