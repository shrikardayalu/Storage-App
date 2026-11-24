# Motion and look lessons for explainer shorts

These come from a frame-by-frame study of one of the reference channel's top shorts (2026-11-24, 31M views, a railroad
story). Its frames were sampled in the browser and measured with the same method as our own renders
(`scripts/motion_stats.py` in the studio project: mean absolute grey change between frames at 72x128).
The same study was run on our first Cairo Geniza cut.

| Measure | Reference | Geniza v1 | Target |
|---|---|---|---|
| Median change per frame | 13.1 (p25 8.2, p75 21.3) | 1.6 | 8 or more |
| Frames that are nearly still (< 1) | 0.9 % | 33 % | under 3 % |
| Frames under 3 | 5.4 % | 81.5 % | under 20 % |
| Hard cuts | **0** in 54 s | 21 | 0-2 |

## Camera
- **The camera never stops.** Every shot is a move: a dolly toward a character, a truck along the rails, an orbit, a
  crane up or down. A slow push-in on a still frame is not enough; that reads as static.
- **No hard cuts.** Places change in one of two ways:
  - a **fly-through or whip**: the camera races to the next place in 0.5-0.8 s with heavy directional motion blur
    (for example over the desert and into the station, 9.9-10.6 s);
  - a short **dissolve** of 5-6 frames between two moving shots (the train window to the station, 31.1-31.3 s).
- **Wide lenses, low cameras.** The lens often sits near the ground or right beside a character, with strong
  perspective (rails converging hard to the horizon) and something close in the foreground.
- Characters are big in frame and often off-centre or cut by the frame edge, not small figures in a wide set.

## Characters
- **Someone is always doing something.** People walk toward the lens while it backs away, lean, point, bounce with the
  train, hold and raise props (a newspaper), turn their heads. Standing figures with a changing face are not enough.
- Expressions swap on the words, often several times per sentence, and every swap has a blink across it.
- Objects in the world move too: steam, wheels, swaying lamps, papers, a bouncing window frame.

## Look
- Bright, saturated, high-contrast colour: deep blue sky with soft clouds, a strong sun, warm materials.
- Detailed textures that hold up close: gravel ballast, wood grain, brick, rivets. Nothing large and flat.
- Interiors have warm practical lights (lamps, windows) and rich colours (red velvet, brass, polished wood).
- Sharp. Lens blur is used, but the subject is always crisp, and there is no softness from the render itself.

## Color, light and shadow (the four most recent shorts, 2026-11-24)
Measured on 36 sampled frames (luminance percentiles, mean saturation, mean colour of shadow pixels):

| Measure | Recent reference shorts | Geniza v1 | Geniza v3 |
|---|---|---|---|
| Darkest 5 % (luma) | 0.10-0.20 (space scenes ~0.01) | 0.23 | 0.14 |
| Median luma | 0.2-0.45 | 0.49 | 0.36 |
| Brightest 5 % | 0.6-0.95 | 0.74 | 0.70 |
| Mean saturation | 0.2-0.45, with a few strong accents | 0.45 everywhere | 0.37 |
| Shadow colour | neutral to cool grey-blue, about (60, 55, 70) | warm purple-brown | neutral-warm grey |

- **Real darks and dramatic light.** Shadows go deep; scenes are lit by a key light plus warm practicals (lamps, neon,
  fire) that throw visible pools of light against a cooler ambient. Bloom and haze around light sources.
- **Moderate overall saturation with strong accents.** Bases are neutral (stone, metal, tile) and a few things carry
  the colour (a red sign, an orange glow, a costume). An all-warm, all-saturated frame looks cheap next to them.
- **Shadows are neutral to cool, never purple or brown.**
- A light vignette and darker frame edges keep the eye in the centre.
- **No decorative sparkle.** Glints and glows come from something in the story (the lost book, the treasure) and are
  soft, not spinning stars.
- **Characters face where they're going.** Someone climbing a ladder is seen from behind (`back: true` in `toon.ts`).

## Captions
- One word at a time, sometimes two or three short words ("the youngest", "every gap."), swapping hard on each word.
- White, very heavy rounded sans with a thick black outline and a soft drop shadow, centred at about 70 % of the frame
  height, cap height about 4 % of the frame height.

## Sound
- Effects follow what moves on screen and sit under the voice. They don't repeat the same sound on every cut.

## How we apply this (studio project)
- `story.ts`: every key is a move (`track`/`orbit`/`crane` helpers), and place changes use `WHIPS` (fast blurred
  moves that hide the cut) or a 6-frame `XFADE`. Check with `scripts/motion_stats.py` after a render.
- `Geniza.tsx`: a motion-blur post pass driven by the camera's screen-space speed, and the caption layer.
- `cast.ts`: every shot gives each character an action (walk, lean, lift, point, bounce), not just an expression.
- Render with `--image-format=png` (Remotion's default JPEG frames at quality 80 soften everything).
