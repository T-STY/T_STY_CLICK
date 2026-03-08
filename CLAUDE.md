# T_STY_CLICK — Arcade Center (Flutter)

A handheld arcade emulator UI built in Flutter. All games are rendered via
`CustomPainter` on a Canvas; there is no game engine dependency.

## Active branch
`claude/add-hidden-retro-game-MhVIB`

## Architecture
- **Entry / shell**: `lib/app/game/arcade_center_screen.dart`
  - Game selector: **Neon Arcade Cabinet 3×3 grid** — alphabetical order
  - Each cell has a neon-colored border/glow from `_kNeonColors` (one per game)
  - Power-on **splash screen** on launch: boot lines animate in, then "¡BIENVENIDO, NAME!" is shown; user presses A/Start to continue. User name fetched from Firestore `users/{userId}['userInfo']['name']`.
  - **CRT scanline overlay** (`_CrtOverlayPainter`) renders over all bezel content
  - Top console strip (gray "ARCADE CENTER" + saldo) is the only place these are shown — they are NOT duplicated inside the grid
  - D-pad: left/right moves ±1, up/down moves ±3 (columns) in the grid
  - `_CartridgePainter` still used as card art background
  - Registered games: `kArcadeGames` list of `ArcadeGameDef` — **alphabetical by new Spanish title**
  - Shared point/score system via `HighScoreService` (IDs unchanged for score compatibility)
- **Input**: `lib/app/game/arcade_input_controller.dart` — virtual D-pad + ABXY/Select/Start

## Game Registry — Alphabetical by Title

| Grid pos | ID | Emoji | New Title | Game type |
|---|---|---|---|---|
| 0 (row0,col0) | `tetris` | 🟦 | **Bloques Caídos** | Tetris |
| 1 (row0,col1) | `logic` | 💣 | **Campo Minado** | Minesweeper |
| 2 (row0,col2) | `match3` | 🍬 | **Cascada Dulce** | Match-3 |
| 3 (row1,col0) | `shooter` | 🚀 | **Caza Estelar** | Space shooter |
| 4 (row1,col1) | `maze` | 👻 | **Comecocos** | Pac-Man maze |
| 5 (row1,col2) | `raycaster` | 🔥 | **Cripta Maldita** | Doom-style FPS |
| 6 (row2,col0) | `hopper` | 🐸 | **Rana Saltarina** | Frogger — frog 10% smaller (scale 0.90) |
| 7 (row2,col1) | `snake` | 🐍 | **Víbora Veloz** | Snake |
| 8 (row2,col2) | `flappy` | 🕊️ | **Vuelo Kamikaze** | Flappy Bird |

In-game titles also updated in each screen's start overlay.

## Cripta Maldita (raycaster_screen.dart) — current state

### Weapons
| Weapon | Rotation | Anchor | Fire rate | Unlock | Ammo/wave | Notes |
|---|---|---|---|---|---|---|
| Pistol | -0.32 rad | (0.82w, 0.95h) | 0.25s | always | +30 | semi-auto |
| Shotgun | -0.18 rad | (0.68w, 0.95h) | 0.55s | wave 2 | +6 shells | 7-pellet spread |
| SMG | -0.28 rad | (0.78w, 0.95h) | 0.08s | wave 4 | +20 | full-auto (hold A) |

- All weapon rotations computed so barrel aims toward crosshair (screen centre)
- B button cycles through all *unlocked* weapons
- Muzzle flash: directional star-burst (forward spike + side petals + white core), NOT circles
- Wall-check: `_hasLos()` DDA march before registering any bullet hit (no shooting through walls)

### Enemies — Wave Scaling
- HP: `baseHp × (1.0 + (wave-1) × 0.25)` — grows each wave
- Damage: `baseDamage × (1.0 + (wave-1) × 0.15)` — caps at 3×
- **Skeleton**: 1 hp base, 15 dmg base
- **Demon**: 3 hp base, 10 dmg base — **20% shorter** (kPad=0.10 compression), scarier: wide swept-back horns w/ edge highlight, glowing eyes + white hot core, fanged mouth + white fang pixels, clawed arm tips, knee highlights
- **Cacodemon**: 2 hp base, 7 dmg base, floating

### Radar
- Bottom-left mini-map — situational awareness only
- No wall-penetration shooting; radar is for navigation

### Floor / environment
- Dark stone floor + blood pools + screen-edge infernal vignette

## CRT Overlay (`_CrtOverlayPainter` in arcade_center_screen.dart)
- Horizontal scanlines every 2px at 14% opacity
- Vertical pixel grid every 2px at 4% opacity
- Radial vignette at 42% edge opacity
- Green phosphor tint at 2.2% opacity
- Applied over all bezel content via `Stack` + `IgnorePointer`

## Pending / next session tasks

### New game
- User wants to add a new game (topic TBD — discuss at start of session)

### Possible tweaks to revisit
- Weapon angles may need visual fine-tuning after seeing on device
- Radar range-limiting to reduce its tactical advantage further
- CRT overlay intensity (opacity values above are current baseline)
