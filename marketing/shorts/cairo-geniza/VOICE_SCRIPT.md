# Cairo Geniza: voice script for Gemini TTS

Paste the **Style** into the Style field (or `speech_metadata.style` in the API), and each numbered line into its own
speech block, or all of it into one block. Tags in angle brackets are Gemini's inline expression tags; the rest is read
word for word. "1896" is spelled out so it's read as a year.

## Speaker and style
- **Voice:** start with **Charon** (informative, male). Audition **Algieba** (smooth), **Sadaltager** (knowledgeable) and
  **Iapetus** (clear) on line 1 and pick by ear.
- **Style:**
  > Warm, curious male storyteller narrating a short animated history video. Fast and steady, about 220 words a minute,
  > with almost no pauses between sentences. Lightly amused, deadpan on the jokes, never dramatic or announcer-like.
  > Keep the same tone and pace all the way through, including the last two lines.

## Script
1. For almost a thousand years, one synagogue in Cairo refused to throw away a single piece of paper.
2. High up in its wall, there's a room with no door and no windows, <short pause> just a hole you reach with a ladder.
3. Worn-out prayer books get shoved through that hole. Then letters, contracts, doctor's notes, a merchant's account books.
4. Even a bored kid's alphabet homework goes in, <chuckle> stick-man doodle and all.
5. And the pile just keeps growing.
6. So why would anyone keep a kid's doodle for a thousand years?
7. You see, Hebrew letters were treated as the writing of God, so anything written in them couldn't be destroyed.
8. Most places buried old pages every so often. <short pause> This room never got emptied.
9. Then in eighteen ninety-six, two Scottish twins show a rabbi at Cambridge a few scraps from Cairo.
10. One is a lost book the world had only ever read in Greek and Latin.
11. So he heads to Cairo, climbs in through the dust and bugs, and hauls out over a hundred thousand pages.
12. Scholars are still sorting it, and most of it isn't holy at all. It's bills, wages and paperwork nobody meant to keep.
13. Turns out, if you never throw anything away, you don't get a library. <short pause> You get a junk drawer with a few treasures in it.
14. Your phone works the same way. Nothing gets thrown out, it just piles up in a room you never open.
15. SimpleShrink finds the junk and frees up gigabytes of storage in minutes. Link in bio.

## Notes
- Keep the tags this sparse. The reference narration is one steady voice, and every extra tag adds a pause or a
  performance that breaks the pace.
- If `<chuckle>` isn't in the voice's tag list, use `<laugh>` or drop it.
- Export as WAV and save it as `C:\Users\shrik\shorts-studio\geniza\voice\voice.wav`. NOTES.md has the steps to
  re-time the video to it.
