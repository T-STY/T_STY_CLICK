# T_STY_CLICK — Arcade Center (Flutter)

A handheld arcade emulator UI built in Flutter. All games are rendered via
`CustomPainter` on a Canvas; there is no game engine dependency.

## Active branch
`claude/add-hidden-retro-game-MhVIB`

## Architecture
- **Entry / shell**: `lib/app/game/arcade_center_screen.dart`
  - Game selector: **Neon Arcade Cabinet 3×3 grid** (carousel was replaced)
  - Each cell has a neon-colored border/glow from `_kNeonColors` (one per game)
  - Marquee header with pink→cyan gradient title + green dot indicator
  - D-pad: left/right moves ±1, up/down moves ±3 (columns) in the grid
  - `_CartridgePainter` still used as card art background
  - Registered games: `kArcadeGames` list of `ArcadeGameDef`
  - Shared point/score system via `HighScoreService`
- **Input**: `lib/app/game/arcade_input_controller.dart` — virtual D-pad + ABXY/Select/Start
- **Games** (all in `lib/app/game/`):

| File | Title (Spanish) | Notes |
|---|---|---|
| `snake_game_screen.dart` | La Sierpe | Snake |
| `maze_chase_screen.dart` | Tragalaberinto | Pac-Man style maze |
| `flappy_bird_screen.dart` | Alas Locas | Flappy Bird |
| `traffic_hopper_screen.dart` | Paso a Paso | Frogger — frog 10% smaller (scale 0.90) |
| `space_shooter_screen.dart` | Astrocaza | Space shooter — enemies fire single OR 3-burst |
| `raycaster_screen.dart` | Inframundo 2D | Doom-style raycaster FPS |
| `tetris_game_screen.dart` | Tetromuro | Tetris |
| `logic_grid_screen.dart` | Busca-Trampas | Minesweeper |
| `match3_screen.dart` | Dulce Racha | Match-3 — right panel candies auto-fit by size |
| `mario_game_screen.dart` | (hidden bonus) | Platformer unlocked via secret input |

## Inframundo 2D (raycaster_screen.dart) — current state

### Weapons
| Weapon | Rotation | Anchor | Fire rate | Unlock | Notes |
|---|---|---|---|---|---|
| Pistol | -0.95 rad | (0.82w, 0.95h) | 0.25s | always | semi-auto |
| Shotgun | -0.82 rad | (0.68w, 0.95h) | 0.55s | wave 2 | 7-pellet spread |
| SMG | -0.95 rad | (0.78w, 0.95h) | 0.08s | wave 4 | full-auto (hold A), compact pixel model |

- B button cycles through all *unlocked* weapons
- Muzzle flash: directional star-burst (forward spike + side petals + white core), NOT circles
- Wall-check: `_hasLos()` DDA march before registering any bullet hit (no shooting through walls)
- SMG: `_fireSmg()` with slight random spread per bullet, granted ammo = `(wave+3)*4` per wave

### Enemies
- **Skeleton**: white pixel art, 1hp
- **Demon** (red): column-based art with high-contrast pec/ab/arm muscles (1.65× highlight, 0.22× shadow)
- **Cacodemon**: crimson sphere with spherical shading

### Radar
- Bottom-left mini-map, range-based visibility (enemies displayed at all ranges but within clip circle)
- Skull icon = skeleton, red diamond+horns = demon, blue circle+horn = cacodemon
- No wall-penetration shooting — radar is for situational awareness only

### Floor / environment
- Dark stone floor with distance lines + blood pool splotches (no lava animation)
- Screen-edge infernal vignette

## Pending / next session tasks

### New game
- User wants to add a new game (topic TBD — discuss at start of session)

### Possible tweaks to revisit
- Inframundo gun angles may still need fine-tuning (pistol -0.95, shotgun -0.82)
- Radar could optionally be range-limited to reduce its power further
