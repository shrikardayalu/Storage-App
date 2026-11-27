# Why Squirrels Fake-Bury Their Nuts: build notes

## Where things are
- **Remotion project** (outside this repo, on purpose): `C:\Users\shrik\shorts-studio`
  - Scenes: `src/videos/squirrel/` (`story.ts` shots, cameras, lens and story clocks; `world.ts` sets and moving
    props; `cast.ts` the squirrel drawing, the scientist and effect cards; `paint.ts` textures; `lights.ts` light
    presets). Built from the Vivian folder; the post chain, captions and phone are the same.
  - Voice and sound: `squirrel/` (`script.txt`, `timing.py`, `align.py`, `audio.py`, `scratch_voice.ps1`, `scratch_fit.py`).
  - Renders: `out/squirrel/` (`video.mp4` picture, `final.mp4` with sound, stills and contact sheets).
  - One command for render, mux, 1080p preview, motion stats and QA: `bash scripts/final_squirrel.sh <preview name>`.
- Composition: `SquirrelShort`, 1080x1920 at 30 fps, rendered at 1440x2560.

## The squirrel
- A new flat card drawn in `cast.ts` (`squirrel()`), side-on, ink outlines, on the same 600 x 1000 design as the
  people, shown at scale 0.42 (about half a metre with the tail up). Poses: sit, dig, pat, run, sleep. Options: head
  turned back, head tilted up, nut in the cheek, nut in the paws, fat (winter), chew, eyes open / smug / shock /
  closed / happy, blinks. Grey and fox colourings.
- The card is mirrored when the direction it faces points to screen left (`sq()` in cast.ts).
- Leaning poses rotate about the hips **and shift back** (`pose` in `squirrel()`); without the shift the head was
  pushed off the card and clipped (the first hook stills showed only a tail).

## Sets (one world, side by side, every floor clear of the next)
- **Park** (x 0): autumn lawn with painted fallen leaves, 14 oaks, the scientist's bush, a log, a bench, lamp posts.
  The hook's hole and dirt pile, 46 mounds that pop up on a spiral (shot 2), the fake spot, the dig pit.
- **Under the lawn** (x 400): a soil room with hanging roots and a lantern; a 9 x 4 cabinet of drawers with nut
  labels sorted by type in columns; drawer (5, 0) opens for the fox squirrel, three others drift in and out.
- **Winter** (x 800): grass under a snow plane that fades out in shot 9 (the melt); a bare oak with the drey; the
  mound and the sprout.
- **Forest** (x 1200): spring lawn, the big oak that grows from a sprout (shot 10), 22 oaks that pop up around it
  (kept out of the camera's pull-back sector), the stump, the phone's mound.

## Status (2026-11-27, v1)
- Script approved with hook A; built with placeholder timings (3.7 words/s, 65.5 s) and a Windows scratch voice.
- Scratch cut: `squirrel-v1-scratch-voice.mp4` in this folder (not in git); full size at
  `C:\Users\shrik\shorts-studio\out\squirrel\final.mp4`.
- Waiting on the real narration (VOICE_SCRIPT.md).

## From voice to finished video
1. Save the narration as `C:\Users\shrik\shorts-studio\squirrel\voice\voice.wav`.
2. `python squirrel/align.py` gets Whisper word times and aligns them to `script.txt` (check line-first words; Whisper
   has put them late before).
3. `python squirrel/timing.py squirrel/voice/words.json` rewrites `timing.ts`; every shot, effect and caption follows it.
4. Check stills at the cue words (`BRIDGE_COMP=SquirrelShort node scripts/bridge-stills.mjs ...`).
5. `python squirrel/audio.py` re-mixes the voice with the score and effects.
6. `bash scripts/final_squirrel.sh squirrel-v2-final` renders and runs the checks.

## Lessons from this build
- Measure motion per shot. A push-in over a white snow field read as 43 % still frames; an arc round the mound fixed it.
- Trees that pop up during a camera pull-back must stay out of the camera's path: the first cut had a trunk appear
  right in front of the lens (a hard cut at frame 1676).
- A ground plane that ends inside the view shows as a line on the horizon; make winter and forest floors much bigger
  than the shot.

## Plan usage (Pro)
- Script phase start: 5-hour window 17 %, weekly 22 % (2026-11-27).
- Scratch cut done (four sets and a new character from scratch, five still rounds, two full renders): the 5-hour
  window reset mid-build (17 % -> reset -> 4 %), weekly 22 % -> 25 %.
- Scratch cut checks: motion median 3.8, still frames 0.9 %, no hard cuts, -15.2 LUFS, peak -1.1 dBFS, no silences,
  no black, white or frozen frames.
