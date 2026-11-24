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
- The picture is built for all 15 lines (19 shots). It is timed to **placeholder word timings** (3.7 words/s).
- The sound is an original score plus synthesized effects. The narration in the cut is a **scratch voice** (the built-in
  Windows voice, stretched to fit each line). It is there only to judge pacing, and the real voice replaces it.

## Swapping in the real voice
1. Save the narration as `C:\Users\shrik\shorts-studio\geniza\voice\voice.wav`.
2. Get word timings from any speech-to-text that gives word times (for example Whisper on the GPU), as
   `[{"word", "start", "end"}]` with one entry per script word in order (`1896` counts as one word). Save as `voice/words.json`.
3. `python geniza/timing.py geniza/voice/words.json` rewrites `src/videos/geniza/timing.ts`. Every shot, camera move and
   effect follows it.
4. Re-render stills to check, then the video, then `python geniza/audio.py` (it picks up `voice.wav`), then mux:
   `ffmpeg -i out/geniza/video.mp4 -i geniza/audio/mix.wav -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 256k out/geniza/final.mp4`

## Plan usage (Pro)
- Start of the build: 5-hour window 11 %, weekly 2 %.
- Scenes built and first stills checked: 5-hour window 22 %, weekly 3 %.
- First full render with score, effects and scratch voice: 5-hour window 29 %, weekly 4 %.
  So a whole first short cost about 18 % of one 5-hour window and 2 % of the week, far under the estimate.

## Preview
`geniza-v1-scratch-voice.mp4` (1080p, not in git). Since then the junk-drawer close-up has been re-aimed at the
glowing scroll; that change shows up in the next render.
