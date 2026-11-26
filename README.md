# Blocklands

A browser-playable, procedurally generated 3D voxel sandbox built with [Three.js](https://threejs.org) (r160, bundled in `lib/`).

## Play

**Live site:** https://qwerwork1314-boop.github.io/Micraft-game-/

On iPhone, open the link in Safari, hold the phone sideways, and tap **Play**. For a full-screen game, tap Share and then **Add to Home Screen**, and launch it from the new icon.

- **Easiest:** open `index.html` directly in a browser (double-click it). No build step or server needed.
- **Or serve it:** `python3 -m http.server` in this folder, then visit http://localhost:8000.
- **Online:** the workflow in `.github/workflows/pages.yml` publishes the game to GitHub Pages on every push to `main`. This needs a one-time setting: Settings → Pages → Source: **GitHub Actions**.

## Features

- Infinite procedural terrain (seeded simplex noise): plains, hills, mountains with snow, beaches, lakes and seas, ores, and a bedrock floor
- Forests with trees that grow across chunk borders
- Chunked world streaming with face culling and ambient-occlusion shading
- First-person movement with collision, jumping, swimming, sprinting and fly mode
- Block breaking and placement with a target outline and break particles
- 36-slot inventory (9-slot hotbar), stack merging and simple crafting recipes
- Day–night cycle with a sun, moon, stars, drifting clouds and sunset colours
- Mobile touch controls: a joystick that appears where you touch, drag-to-look, buttons for actions, and auto-jump
- Autosave to `localStorage`: the world seed, your block edits, inventory, position and time of day

## Controls

| Desktop | Action | Touch |
|---|---|---|
| WASD / arrows | Move | Left side of the screen (joystick) |
| Mouse | Look | Drag on the right side |
| Space | Jump / swim / fly up | ▲ |
| Shift | Fly down | ▼ |
| Ctrl | Sprint | Push the joystick all the way |
| Left click | Break a block | ⛏ (hold to keep breaking) |
| Right click | Place a block | ■ |
| 1–9 / mouse wheel | Choose a hotbar slot | Tap a slot |
| E | Inventory and crafting | ▦ |
| F | Toggle fly mode | ➤ |
| T | Skip ahead in time | — |
| Esc | Pause | ❚❚ |

## Files

- `index.html`: page layout and UI
- `style.css`: HUD, menu, inventory and touch-control styles
- `game.js`: world generation, meshing, physics, input, inventory, day–night cycle and saving
- `lib/three.min.js`: Three.js r160 (MIT license, see `lib/THREE-LICENSE`)
