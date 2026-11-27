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

## Motion, look, captions and sound (read `marketing/shorts/MOTION_LESSONS.md`)
These were measured frame by frame on a top reference short after the first Geniza cut looked static. They override
the base skill where they differ.
- **Captions are on** (the base skill says no captions). Use one word at a time (short words ride with the next),
  white heavy rounded sans with a thick black outline, at ~70 % of the frame height, swapping hard on each word.
  `captions.tsx` in the studio does this from the word timings.
- **The camera never parks.** Every shot is a continuous move (dolly, truck, orbit or crane) with wide lenses (FOV
  50-60) and low cameras. Aim for a median frame change of 8+ and under 3 % still frames on `scripts/motion_stats.py`
  (the reference measures 13 and 0.9 %; Geniza v1 measured 1.6 and 33 %).
- **No hard cuts.** A place change is a blurred whip (`WHIPS` plus the motion-blur pass, which runs only there) or a
  6-8 frame dissolve.
- **Moves run at a near-constant speed** (`go()` in `smithsonian/story.ts`: 30 % ease, 70 % linear). Full sine eases
  park the camera at both ends of every shot and pushed still frames to 5 %.
- **Every character acts:** walks in, climbs, throws, leans, jumps up, lifts a prop. Something else moves in the
  world as well (papers, flames, steam).
- **Sharpness (the user notices blur fast; the Smithsonian v1 cut looked smeared in about half its shots):**
  - **Motion blur runs only inside whips.** Gate the motion-blur pass on the whip (`inWhip(id, f)` in
    `smithsonian/story.ts`) and never use its radial zoom part. On ordinary moves (tracking a plane, a crane, an orbit
    around the phone) it smears the whole frame, and the black edge it drags in reads as a glitch.
  - **Lens blur stays light:** `LensBlur({ maxCoC: 8, nearScale: 0.25 })`. The old 24 / 1.2 turned anyone walking
    near the camera into a blob. Keep passers-by off the camera's path anyway.
  - **No shimmer on flat props.** Textures seen at a low angle (a tray on a desk, a floor sign) get
    `anisotropy = 16`, sit a few mm clear of the surface under them, and use big soft shapes with thick outlines.
    Thin lines and small high-contrast detail flicker frame to frame.
  - **No flicker (z-fighting).** Two surfaces at the same depth fight over every pixel and flip frame to frame. In
    the Smithsonian v2 cut, the Hudson set's riverbank floor ran under the pods' lawn at the same height, so the lawn
    flashed grey. A tray also shared its top face with the desk under it. Rules:
    - Sets sit side by side in one world, so every set's floor must end well before the next set's floor begins.
    - A prop resting on a surface starts at that surface's height and never shares a face with it. Decals, labels and
      front panels sit 1.5-3 cm proud, not 4 mm.
    - On wide outdoor shots, set `cam.near` to about 1 m so far walls keep their depth precision.
    - Freeze the shadow camera per shot (one centre and size, `shotShadow()`). A shadow frame that follows the look
      point every frame makes shadow edges crawl.
    - Keep fine repeating patterns (corrugated siding, stripes) wide and low-contrast; fine ones alias into shimmer.
  - **Check flicker, not just stills.** Render 4 consecutive frames of every moving shot. Count pixels that go up then
    down (a >12 luma swing each way) and look at where they sit. Moving outlines are fine; whole patches flipping are
    z-fighting. The pods shot went from 10.3 % to 0.6 % once the overlapping floors were fixed.
  - Render with `--image-format=png --crf 14` and paint close-up textures at 2x.
  - Before the final render, look at stills from inside the camera moves, not only from held moments, and check
    every moving shot for blur.
- **The ending shows the real app.** Use the actual screens from `marketing/app-store/screens/` on a proper phone. The
  home screen there is outdated (Test Mode pill), so use the picker and results screens. Keep the icon clear of the
  phone so nothing overlaps or gets cut off.
- **Color and light:** deep neutral-cool shadows, warm practical lights with floor pools against a cooler ambient,
  moderate saturation with a few strong accents, a light vignette. Targets: darkest 5 % around 0.15, median 0.3-0.4,
  saturation 0.3-0.4 (see the table in MOTION_LESSONS.md).
- **No spinning stars or bursts as decoration.** Use them at most once a video, on a story moment. A soft glow from
  the object itself is usually better.
- **Characters face their action.** Climbers are drawn from behind (`back: true`), and props are never held in
  front of a face.
- **Sound effects stay light.** Each one follows something that moves on screen. There's no whoosh on every cut and no
  repeated copies; use a soft bed for continuous actions (paper rain, rustling). Effects sit about 12 dB under the voice.

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
  (`src/videos/geniza/`, then `src/videos/smithsonian/`, which has the sharpness fixes and a reusable warehouse aisle;
  see each short's NOTES.md). Copy the newest folder for a new short rather than starting from the bridge again.
- Times come from a generated `timing.ts` (`geniza/timing.py`). Without a voice it makes placeholder timings, so the
  picture can be built before the narration exists. Shots key off line starts and words (`LS(n)`, `W(n, "word")`).
- Stills: `BRIDGE_COMP=<Comp> node scripts/bridge-stills.mjs out/<name>/v1_ <frames> 0.5`, then
  `python scripts/sheet.py out/<name>/v1_ out/<name>/sheet.jpg` to review every shot on one contact sheet.
- Final render: `--scale 1.3333333333333333` (the base skill's `1.3333` gives 2559.94 px and Remotion refuses it),
  `--gl=angle`, Chrome as `--browser-executable`, `TEMP`/`TMP` set to `C:/remotion-tmp`.
- Kenney models aren't installed (their download is behind a JS page). Props are built from boxes and textures instead.

## The hook (first line and first frames)
Most viewers who leave do it in the first ~3 seconds, so the hook decides whether anything else gets seen. Researched
2026-11-27 on the top story shorts in this style (2D cartoon cards in 3D sets) and on short-form retention write-ups.
What the best ones share:
- **The first words are the strange thing.** One plain sentence, 9-14 words (~3 s), about something someone did that
  makes no sense yet. No date, no "in the 1950s", no "this is the story of", no "did you know", no name first. A date
  or a setup clause spends the most valuable second on nothing.
- **Hide the reason, keep the loop open.** The hook raises one question the viewer needs answered (why would she? what
  was in it?) and the payoff answers it at the end. Never state the payoff in the hook ("...one of the great finds of
  the century" closes the loop before it opens).
- **Concrete and small.** One exact number, one object, one person: "four hundred dollars", "a box", "a nanny". Small
  concrete things beat big abstract claims.
- **A contradiction or an irony** inside the sentence (a nanny who was a master photographer; film she shot and never
  developed; a box of junk that was worth millions).
- **Second line, a reaction or an escalation.** Within 2 s of the hook, someone reacts (laughs, scoffs, refuses) or the
  claim gets weirder. Then the story fills in who, where and what is at stake, with the camera already moving.
- **The first frame is mid-action and shows the words literally**: the object or action the hook names, moving, at a
  low wide angle, from frame 0. No title card, no establishing shot, no fade in. Captions start on the first word.
- **The last line flips the first.** The ending callback answers the hook's question, so the video loops into a rewatch.
- **Titles use the same shapes**: "The X that Y", "Why X", "The job nobody wants", strange action with the reason
  hidden. Write the title and the hook together.
- The hook never mentions phones, storage or the app.

**Every time a script is shown, give hook options with it.** Write 4-5 different openings (the first one or two lines
only), each with a short label for its angle (strange action, contradiction, money, irony, reaction), the first frame it
needs, and a matching title. Say which one you recommend and why in one line, and note what in the rest of the script
or the build would change for each. The user picks before the voice is made. Save the options in `SCRIPT.md` next to
the script.

## Script format (every time a script is shown or saved)
Whenever the user asks for a script, give it in the form it gets pasted into the TTS, in a code block in chat and the
same way in `SCRIPT.md`:
- One sentence group per line, as plain lines. No numbers, bullets or headings inside the script.
- Write numbers as they're spoken ("eighteen ninety-six", "thirty-five million", "ninety-nine percent").
- Add Gemini's inline tags (`<short pause>`, `<chuckle>`, and the like) only where the voice needs them, such as a beat
  before a punchline or a laugh on a joke. Most videos need 2-5 tags in all. An extra tag adds a pause or a
  performance and breaks the steady pace.
- Sources, shot ideas and the caption go outside the script block. For shot ideas, refer to the line by its words, not
  by a number.

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
