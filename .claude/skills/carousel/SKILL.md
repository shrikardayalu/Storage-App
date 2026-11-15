---
name: carousel
description: Write and render a SimpleShrink TikTok/Instagram carousel on a topic. Use when asked for a carousel, a slide post, or social content for SimpleShrink.
---

# Carousel

Make one carousel for the topic in the arguments (if there is none, pick a
topic from "Ideas that fit" that `marketing/carousels/carousels/` doesn't
cover yet).

1. Read `marketing/carousels/README.md` in full. Its JSON format and writing
   rules are binding.
2. Find the facts. Read the matching guide in `web/content/guides/` and, for
   anything about the app, `docs/PRICING.md`. Use only numbers and claims you
   can point to there. If the topic needs a fact you can't source, leave it
   out or pick another angle.
3. Write three different hooks, then keep the most specific one.
4. Write `marketing/carousels/carousels/<short-name>.json`: 6 to 8 slides,
   starting with `hook` and ending with `cta`.
5. Render it: `node marketing/carousels/render.mjs marketing/carousels/carousels/<short-name>.json`.
   Fix every error, and cut words wherever it reports a slide was shrunk.
6. Look at `marketing/carousels/out/<short-name>/overview-tiktok.png` and
   `overview-instagram.png`. Fix anything cramped, cut off or awkwardly
   wrapped, and render again.
7. Tell the user where the slides and `caption.txt` are, and list each
   factual claim with its source so they can check it before posting.

Don't post anything. The user uploads the slides themselves.
