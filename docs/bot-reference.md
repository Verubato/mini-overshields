# MiniOvershields - bot reference

Version 2.2.6. Interface versions: 120100 (retail), 50504 (Mists of Pandaria Classic).

## What it does

Draws a shield/absorb overlay on top of health bars so you can see overshields
(absorb shields larger than the target's missing health). Useful for Disc
priest shields, Prot warrior Ignore Pain, and mage barriers. Display only; it
changes no gameplay behaviour.

## Where it draws

- Blizzard player, target, and focus frames.
- Blizzard compact party and raid frames, and Blizzard nameplates (via hooks
  on CompactUnitFrame_UpdateAll and CompactUnitFrame_UpdateHealPrediction).
- The Blizzard personal resource display, only while the "Personal Resource
  Display" option is enabled (CVar nameplateShowSelf = 1). The addon reacts
  when that CVar is toggled.

Only Blizzard frames are supported. It does not attach to ElvUI, Shadowed
Unit Frames, custom nameplate addons, or any other unit frame replacement.

## How the overlay behaves

- The overlay is a reverse-filled bar using Blizzard's Shield-Overlay texture
  (white, 50% opacity, tiled), scaled as total absorbs out of max health.
- On frames that have Blizzard's over-absorb glow (the bright edge spark), the
  overlay is shown only while that glow is visible, i.e. only when there is an
  actual overshield. On frames without the glow the overlay is always shown
  while absorbs exist.
- The addon also re-anchors Blizzard's over-absorb glow so it tracks the edge
  of the overlay instead of sticking to the end of the health bar.
- Updates fire on target/focus change, absorb amount changes for player,
  target and focus, and on entering the world.
- Compound units such as "boss1target" or "raid1target" are deliberately
  skipped on compact frames.
- Handles Midnight "secret values": if a frame's strata is secret the overlay
  falls back to the LOW strata.

## Settings

Open with a slash command or Options -> AddOns -> MiniOvershields. The panel
is informational only: its subtitle says the addon has no settings and
simply works out of the box. There are no options and no saved variables.

## Slash commands

/miniovershields, /minios, /mos - all open the settings panel.

## Troubleshooting

- "Nothing shows on my raid frames": on compact frames the overlay only
  appears when the shield exceeds missing health (an overshield). A shield on
  a damaged player that is smaller than the missing health shows Blizzard's
  normal absorb display, not this overlay.
- "Nothing on the personal resource display": enable Personal Resource
  Display in Blizzard's nameplate options (CVar nameplateShowSelf).
- "Nothing on my unit frames": the addon only draws on default Blizzard
  frames. If another addon replaces your frames or nameplates, MiniOvershields
  has nothing to draw on.
- "Where are the options?": Options -> AddOns -> MiniOvershields opens a
  panel, but it is informational only; there is nothing to configure.
