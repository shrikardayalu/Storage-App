# Cairo Geniza short: build notes

## Where things are
- **Remotion project** (outside this repo, on purpose): `C:\Users\shrik\shorts-studio`
  - Scenes: `src/videos/geniza/` (`story.ts` shots, cameras and lens; `world.ts` sets; `cast.ts` characters and effects;
    `toon.ts` characters with turbans, kippahs and beards; `paint.ts` textures; `lights.ts` light presets).
  - Shared engine from the cartoon-3d-short skill: `src/videos/bridge/` (ink, lens blur, grade, card shading).
  - Voice and sound: `geniza/` (`script.txt`, `timing.py`, `audio.py`, `scratch_voice.ps1`, `scratch_fit.py`).
  - Renders: `out/geniza/` (`video.mp4` picture, `final.mp4` with sound, stills and contact sheets).
- Composition: `GenizaShort`, 1080x1920 at 30 fps, rendered at 1440x2560.

## Status (2026-11-24)
- **Final cut is done** with the real narration (Gemini TTS, read from `VOICE_SCRIPT.md`, 71.4 s).
- It has 19 shots with continuous camera moves, blurred whips and short dissolves between places, one-word captions,
  an original score with light effects, and real SimpleShrink screens at the end.
- The final file is `C:\Users\shrik\shorts-studio\out\geniza\final.mp4` (1440x2560). The 1080p preview is
  `geniza-v4-final.mp4` in this folder.

## From voice to finished video (what worked)
1. Save the narration as `C:\Users\shrik\shorts-studio\geniza\voice\voice.wav`.
2. `python geniza/align.py` gets Whisper word timestamps (`small.en` on the CPU, via `faster-whisper`) and aligns them to
   `script.txt`. It joins words Whisper splits in two ("Worn" + "-out", "Simple" + "Shrink") and merges "eighteen
   ninety-six" into `1896`. Anything still unmatched is interpolated and listed; check that no line's first word is in
   that list.
3. `python geniza/timing.py geniza/voice/words.json` rewrites `timing.ts`. Every shot, camera move, effect and caption
   follows it.
4. Check stills at the cue words and fix anything that collides. A real read bunches some words closer than the
   placeholder timings did.
5. `python geniza/audio.py` mixes `voice.wav` at -16 LUFS, with the music about 13 dB under it (raised in the gaps)
   and the effects under that.
6. `bash scripts/final.sh <preview name>` renders with PNG frames, muxes the sound, writes a 1080p preview into this
   folder, and runs the motion stats and QA.

## Plan usage (Pro)
- Start of the build: 5-hour window 11 %, weekly 2 %.
- Scenes built and first stills checked: 5-hour window 22 %, weekly 3 %.
- First full render with score, effects and scratch voice: 5-hour window 29 %, weekly 4 %.
  So a whole first short cost about 18 % of one 5-hour window and 2 % of the week, far under the estimate.

## Previews (1080p, not in git)
- `geniza-v1-scratch-voice.mp4`: the first build.
- `geniza-v2-scratch-voice.mp4`: continuous camera, whips, captions, the real-app ending, lighter sound.
- `geniza-v4-final.mp4`: the real voice, the color and light pass, no star effects, climbers seen from behind, and the
  reworked hauling shot.
