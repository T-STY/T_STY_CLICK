# T_STY_CLICK — Arcade Center (Flutter)

A handheld arcade emulator UI built in Flutter. All games are rendered via
`CustomPainter` on a Canvas; there is no game engine dependency.

## Active branch
`claude/add-hidden-retro-game-MhVIB`

## Architecture
- **Entry / shell**: `lib/app/game/arcade_center_screen.dart`
  - Hosts the game selector UI (currently a carousel — **pending redesign**)
  - Registered games: `kArcadeGames` list of `ArcadeGameDef`
  - Shared point/score system via `HighScoreService`
- **Input**: `lib/app/game/arcade_input_controller.dart` — virtual D-pad + ABXY/Select/Start buttons
- **Games** (all in `lib/app/game/`):

| File | Title (Spanish) | Notes |
|---|---|---|
| `snake_game_screen.dart` | La Sierpe | Snake |
| `maze_chase_screen.dart` | Tragalaberinto | Pac-Man style maze |
| `flappy_bird_screen.dart` | Alas Locas | Flappy Bird |
| `traffic_hopper_screen.dart` | Paso a Paso | Frogger — frog character with froggy pixel art, logs with bark wrinkles |
| `space_shooter_screen.dart` | Astrocaza | Space shooter — enemy ships fire single shots OR 3-burst |
| `raycaster_screen.dart` | Inframundo 2D | Doom-style raycaster FPS |
| `tetris_game_screen.dart` | Tetromuro | Tetris |
| `logic_grid_screen.dart` | Busca-Trampas | Minesweeper |
| `match3_screen.dart` | Dulce Racha | Match-3 |
| `mario_game_screen.dart` | (hidden bonus game) | Platformer unlocked via secret input |

## Pending / next session tasks

### UI Redesign (HIGH PRIORITY)
- Replace the carousel selector with a **Neon Arcade Cabinet** style:
  - 2×2 grid of game cards, each neon-bordered and color-coded per game
  - Glowing marquee header "ARCADE CENTER"
  - Pink/cyan/yellow neon palette
  - User approved this style (shown ASCII mockup, chose "Neon Arcade Cabinet")

### New game
- User wants to add a new game (topic TBD — start fresh in new session)

## Inframundo 2D (raycaster_screen.dart) — current state
- **Enemies**: Skeleton, Demon (red, ripped muscular body), Cacodemon (floating sphere)
- **Weapons**: Pistol (rotate -0.65 rad, anchor 0.82w/0.95h) + Shotgun (rotate -0.55 rad, anchor 0.68w/0.95h)
- **HUD**: Health bar, kill counter, wave counter, ammo counts, radar (bottom-left)
  - Radar icons: skull (skeleton), red diamond+horns (demon), blue circle+horn (cacodemon)
- **Floor**: Dark stone with distance lines + blood pool splotches (no lava animation)
- **Demon body**: Column-based pixel art with high-contrast pec/ab/arm muscles

## Busca-Trampas (logic_grid_screen.dart) — current state
- Minesweeper with difficulty selector cards
- Mine graphic layout uses deterministic absolute positioning (no % overlap)
- 12 mines per board, +1 pt per completed board

## Known issues / in-flight
- Gun angles for Inframundo still being dialed in — user may want further tweaks
  after seeing in-game (last change: -0.65 pistol / -0.55 shotgun)
