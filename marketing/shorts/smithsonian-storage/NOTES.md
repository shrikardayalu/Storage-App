# America's Attic (Smithsonian storage): build notes

## Where things are
- **Remotion project** (outside this repo, on purpose): `C:\Users\shrik\shorts-studio`
  - Scenes: `src/videos/smithsonian/` (`story.ts` shots, cameras and lens; `world.ts` sets and moving props; `cast.ts`
    characters and effect cards; `paint.ts` textures; `lights.ts` light presets). Characters reuse `geniza/toon.ts`.
  - Voice and sound: `smithsonian/` (`script.txt`, `timing.py`, `align.py`, `audio.py`, `scratch_voice.ps1`,
    `scratch_fit.py`).
  - Renders: `out/smithsonian/` (`video.mp4` picture, `final.mp4` with sound, stills and contact sheets).
  - One command for render, mux, 1080p preview, motion stats and QA: `bash scripts/final_smithsonian.sh <preview name>`.
- Composition: `SmithsonianShort`, 1080x1920 at 30 fps, rendered at 1440x2560.

## Sets (one world, side by side)
- **Hall** (x 0): marble exhibit hall, columns, lit display cases, the blue gem on a plinth, visitors strolling.
- **Pods** (x -400): five football-field storage pods in a lawn, a long corridor building, trees.
- **Store** (x 400): one long warehouse aisle under hanging lamps. Whale rack (z -4..12), bug and bird cabinets on both
  sides (z 14..44) with label cards that can light up, sliding drawers, and the feather lab at the end (z ~50).
- **Suits** (x 800): steel racks of space suits lying down. **Jars** (x 1200): shelves of specimen jars, the
  NO OPEN FLAMES sign. **City** (x -800): the Hudson with the Manhattan skyline.
- The warehouse aisle, cabinets, lamps and drawers are built to be reused in later shorts.

## Status (2026-11-25)
- **Final cut is done** with the real narration (Gemini TTS, 70.5 s): `smithsonian-v2-final.mp4` in this folder, full
  size at `C:\Users\shrik\shorts-studio\out\smithsonian\final.mp4` (1440x2560).
- v2 fixes after the user's review of v1: motion blur now runs only inside whips (it had smeared the plane, the pods
  crane and the phone pan), lens blur is much lighter (a visitor near the camera was a blob), and the geese tray is
  redrawn as side-view geese with anisotropic filtering (it flickered and read as keys).
- Final checks: motion median 3.7, still frames 0.9 %, -14.3 LUFS, peak -1.1 dBFS, no silences, no black, white or
  frozen frames; hard cuts only at the planned flash and the pods-to-warehouse whip.

## From voice to finished video
1. Save the narration as `C:\Users\shrik\shorts-studio\smithsonian\voice\voice.wav`.
2. `python smithsonian/align.py` gets Whisper word times and aligns them to `script.txt`. Spoken numbers ("a hundred and
   fifty", "two thousand nine") are merged back into the digit tokens the captions use. Check that no line's first word
   is in the interpolated list it prints.
3. `python smithsonian/timing.py smithsonian/voice/words.json` rewrites `timing.ts`; every shot, effect and caption
   follows it.
4. Check stills at the cue words (`BRIDGE_COMP=SmithsonianShort node scripts/bridge-stills.mjs ...`).
5. `python smithsonian/audio.py` re-mixes the voice with the score and effects.
6. `bash scripts/final_smithsonian.sh smithsonian-v2-final` renders and runs the checks.

## Plan usage (Pro)
- Start of the script phase: 5-hour window 19 %, weekly 9 %.
- Scenes built, stills checked, render started: 5-hour window 38 %, weekly 11 %.
- Scratch-voice cut done (two full renders): 5-hour window 41 %, weekly 12 %. So the build cost about 22 % of one
  5-hour window and 3 % of the week, close to the Geniza short.

## Checks on the scratch cut (v1)
- Motion: median frame change 3.8, still frames 1.0 % (the Geniza final measured 4.5 and 2.6 %). The first render
  measured 3.6 and 4.9 %; switching the camera moves to near-constant speed and lengthening the slow shots (hall, pods,
  jars, birds, plane, lab, labels) fixed the parked ends. Still under the reference's 13; the next lift would be faster
  moves in the big interiors.
- Loudness -15 LUFS, peak -1 dBFS, no silences, no black, white or frozen frames. The only hard cuts are the planned
  flash after the hook and the whip from the pods into the warehouse.
