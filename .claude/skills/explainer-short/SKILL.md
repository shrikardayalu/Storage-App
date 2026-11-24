---
name: explainer-short
description: Make a SimpleShrink animated story short. It is a ~60 s curiosity explainer (2D cartoon characters in an ink-outlined 3D world) that ends with a light, natural plug for SimpleShrink. Use when asked for an explainer short, a story short, a "bait and switch" video, an animated short, or a cartoon video for SimpleShrink.
---

# SimpleShrink explainer short

This skill is the SimpleShrink layer on top of the global `cartoon-3d-short` skill
(`~/.claude/skills/cartoon-3d-short/SKILL.md`, from mromidev/claude-animated-shorts).
Read that file in full and follow its pipeline, script formula and look values. The
rules below add to it, and they win where the two disagree.

## Why these exist
These shorts are for reach, not installs. They earn views and engagement so the
account's conversion posts get seen. A viewer who smells an ad early swipes away, and
that kills the reach the video exists for. So the story is the product here, and the
plug is a small thank-you at the end.

## The ending: a light plug, never a pitch
- The first ~85-90 % is a complete, satisfying story, with no hint of an app, a phone or
  storage. The payoff of the story lands fully before any plug starts.
- The plug fits in the last ~5-15 s. It is one or two sentences, in the same narrator
  voice and pace, and the video ends on it.
- Give up detail before you give up naturalness. Leave out features, prices, "Pro" and
  any list. Say one benefit, the name, and at most "link in bio" or "free to try".
- It must never feel like the story was a trick. No "but first", no "this video is
  sponsored by", and no hard turn like the "Wants and Needs" style.

Use one of these endings (rotate them across videos):

1. **Callback twist (default).** The story's ironic last line turns to the viewer's
   phone, and then a quick plug follows.
   Example (a hoarder who filled five houses): "...which is why your camera roll has
   4,000 screenshots. SimpleShrink cleans up gigabytes in minutes. Link in bio."
2. **Self-aware thank-you.** After the payoff, the narrator says something short and honest,
   10-15 s at most: "Thanks for watching. We built an app called SimpleShrink. If your
   phone's always full, you can try it free." No hype words.
3. **Mechanism bridge.** Use it only when the story's mechanism really is the reason phones
   fill up (duplicates, hidden copies, things nobody looks at again). If the link needs
   explaining, use the callback twist instead.
4. **In-world, near the end only.** A character pulls out a phone with SimpleShrink in the
   final beat, as part of the joke. It never appears earlier in the video.

## Topic fit
- Pick stories where the link to phone clutter feels obvious once said. Good themes:
  hoarding and keeping everything, collections that got out of hand, storage and space
  limits, copies of copies, "just in case" thinking, forgotten archives, things nobody
  throws away.
- The story still has to stand on its own as a great short (paradox hook, real facts).
  Don't pick a weak story because it links neatly to storage.
- The only app claims allowed are the ones in `docs/PRICING.md` (see "Marketing claims") and the live app.
  "Frees up gigabytes of storage in minutes" is backed and is the standard plug line.
  Facts in the story are researched and sourced at the top of `SCRIPT.md`, as the base
  skill requires.

## Running on the Pro plan (keep it lean)
The base skill was built with many parallel agents and several Opus max verifier rounds.
That is too heavy for this plan. Instead:
- Start every short from the finished look in `templates/bridge/`. Don't run the
  look-match loop (no sandboxes, no per-topic analysis agents).
- Do one verifier pass on 2-3 stills before the final render, plus `short_qa.py` on
  the final file. Add a second pass only if the first one finds real problems.
- Reuse world pieces and characters from earlier shorts wherever the story allows.
- Before you start and after you finish, check plan usage with
  `mcp__ccd_session_mgmt__get_usage` and note both numbers in the video's notes, so the
  cost estimates stay real.

## The studio project (set up 2026-11-24)
- `C:\Users\shrik\shorts-studio` is the Remotion project (pinned versions from the base skill's README, ffmpeg via
  winget, `REMOTION_TMP=C:/remotion-tmp`). `src/videos/bridge/` is the shared engine; each short gets its own folder
  (the first one is `src/videos/geniza/`, see `marketing/shorts/cairo-geniza/NOTES.md`). Copy that folder for a new
  short rather than starting from the bridge again.
- Times come from a generated `timing.ts` (`geniza/timing.py`). Without a voice it makes placeholder timings, so the
  picture can be built before the narration exists. Shots key off line starts and words (`LS(n)`, `W(n, "word")`).
- Stills: `BRIDGE_COMP=<Comp> node scripts/bridge-stills.mjs out/<name>/v1_ <frames> 0.5`, then
  `python scripts/sheet.py out/<name>/v1_ out/<name>/sheet.jpg` to review every shot on one contact sheet.
- Final render: `--scale 1.3333333333333333` (the base skill's `1.3333` gives 2559.94 px and Remotion refuses it),
  `--gl=angle`, Chrome as `--browser-executable`, `TEMP`/`TMP` set to `C:/remotion-tmp`.
- Kenney models aren't installed (their download is behind a JS page). Props are built from boxes and textures instead.

## Voice
- Audition first: put the same script through Gemini Flash TTS (voices Charon, Algieba,
  Sadaltager, Iapetus) and one ElevenLabs voice. The user picks.
- Gemini gives no word timings. Make `words.json` with a local Whisper model that
  returns word times, then check the timings by hand.
- Direct the voice to be fast and steady (~3.7 words/s), slightly deadpan, with no long
  pauses. The plug is read in the same tone, not as an "ad voice".
- API keys only come from environment variables. Never write them into files (this repo is public).

## Output
- Project files go in `marketing/shorts/<short-name>/`: `SCRIPT.md`, the voice and audio
  folders, notes and the final mp4. The Remotion project and renders stay outside the repo.
- Never commit the reference frames, sheets or reports from the base skill. They are
  private study material, and this repo is public. Never name the reference channel.
- Post caption: one line plus hashtags. On TikTok, tell the user to switch on the
  "Your brand" content disclosure.
- Don't post anything. The user uploads the videos.
