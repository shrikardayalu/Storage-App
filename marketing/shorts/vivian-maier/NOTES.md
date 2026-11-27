# The Nanny's Boxes (Vivian Maier): build notes

## Where things are
- **Remotion project** (outside this repo, on purpose): `C:\Users\shrik\shorts-studio`
  - Scenes: `src/videos/vivian/` (`story.ts` shots, cameras and lens; `world.ts` sets and moving props; `cast.ts`
    characters and effect cards; `paint.ts` textures; `lights.ts` light presets). Characters use `geniza/toon.ts`, which
    gained a wide-brim felt hat (`hat: "brimhat"`) for Vivian.
  - Voice and sound: `vivian/` (`script.txt`, `timing.py`, `align.py`, `audio.py`, `scratch_voice.ps1`, `scratch_fit.py`).
  - Renders: `out/vivian/` (`video.mp4` picture, `final.mp4` with sound, stills and contact sheets).
  - One command for render, mux, 1080p preview, motion stats and QA: `bash scripts/final_vivian.sh <preview name>`.
- Composition: `VivianShort`, 1080x1920 at 30 fps, rendered at 1440x2560.

## Sets (one world, side by side, every floor clear of the next)
- **Auction hall** (x 0): wood floor, lot tables, the podium with a gavel, bidders seen from behind, John with the box.
- **Storage corridor** (x 400): rows of roll-up doors; the opened unit (z 10.5) is packed with boxes; the open box on
  the floor spills negative strips, and one film canister rolls away.
- **John's room** (x 800): desk, lamp, bookshelf, night window, the laptop with the death notice.
- **Chicago street** (x -400): brick blocks with shopfronts, the L overhead with a train running, two fifties cars,
  the shop window with her reflection and her long shadow. Shown grey (a CSS saturate filter on the whole frame) until
  her name, then colour floods in.
- **Her room** (x 1200): newspaper stacks to the ceiling on a floor that sags on "floor sagged" (the floor mesh bends
  and the stacks ride it).
- **Gallery** (x 1600): 8.4 m wide (a 16 m room kept its side walls out of the vertical frame), prints pop onto both
  walls on "online", visitors walk in on "museums", the statuette glints on "Oscar", the lone box under junk at the far
  end, and the phone above it for the plug.

## Status (2026-11-26)
- Script approved; built with placeholder timings (3.7 words/s, 66.8 s) and a Windows scratch voice.
- Scratch cut rendered: `vivian-v1-scratch-voice.mp4` in this folder (not in git), full size at
  `C:\Users\shrik\shorts-studio\out\vivian\final.mp4`.
- Checks on the scratch cut: motion median 2.3, still frames 5.2 % (target under 3 %; the slowest shots are the dark
  desk and laptop shots), -15.1 LUFS, peak -1.1 dBFS, no silences, no black, white or frozen frames. Hard cuts only at
  the planned flash after the hook and the two whips (into the desk and into the gallery).
- Fixed along the way: the phone shot's orbit started outside the gallery wall (a black frame and three hard cuts).
- Waiting on the real narration (VOICE_SCRIPT.md).

## From voice to finished video
1. Save the narration as `C:\Users\shrik\shorts-studio\vivian\voice\voice.wav`.
2. `python vivian/align.py` gets Whisper word times and aligns them to `script.txt` ("two thousand seven", "four
   hundred", "forty", "four thousand" are merged back into the digit tokens the captions use).
3. `python vivian/timing.py vivian/voice/words.json` rewrites `timing.ts`; every shot, effect and caption follows it.
4. Check stills at the cue words (`BRIDGE_COMP=VivianShort node scripts/bridge-stills.mjs ...`).
5. `python vivian/audio.py` re-mixes the voice with the score and effects.
6. `bash scripts/final_vivian.sh vivian-v2-final` renders and runs the checks.

## Lessons from this build
- In a 9:16 frame the horizontal view is only about 30 degrees wide. Rooms wider than ~9 m lose their side walls, so
  anything hung on them never shows. Keep interiors narrow or aim the camera at the wall.
- Repeating doors on a fixed grid must line up with any special unit, and a solid wall box behind the doors has to be
  split where an opening is meant to be seen.
- Looking down +z, screen right is world -x. Place things that must be on screen right at lower x.

## Plan usage (Pro)
- Start of the script phase: 5-hour window 2 %, weekly 17 %.
- Scratch-voice cut done (sets built from scratch, three still rounds, two full renders): 5-hour window 23 %, weekly
  19 %. So script plus build cost about 21 % of one 5-hour window and 2 % of the week.
