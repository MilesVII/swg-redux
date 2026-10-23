# Kriegsspiel
A turn-based wargame featuring fog of war, bestagons and indirekt fire

## Build instructions
Requires [odin](https://odin-lang.org/docs/install/) `dev-2026-10` or newer to be installed
```
git clone https://github.com/MilesVII/swg-redux
cd swg-redux
odin build .
cp config.toml.example config.toml
```

On Linux, odin links with `clang`, and the client needs X11 development files: `sudo apt install clang libx11-dev`

On Windows, `odin build . -subsystem:windows` builds without a console window. Servers and lobbies from such a build print to the terminal they were started from, or open a console when started by double click.

Servers and lobbies can be built without the client, which leaves out raylib, X11 and OpenGL:
```
odin build . -define:HEADLESS=true
```

Game rules are covered by tests: `odin test tests`

Specify operating mode if needed:
```
swg-redux --mode client --name username --renderer 3d
swg-redux --mode server --port 27014 --players 4 --team-size 2
swg-redux --mode lobby
```
All parameters are optional

### Lobby mode
Clients can connect to lobbies instead of connecting to a server directly right from the start. Lobbies offer an option to connect to started games and can accept new game requests from clients with matching auth token

Game servers shut down once a finished game has no players left, or after an hour without any player connected

Refer to `config.toml.example` for config details

## Rules and Controls
`MCV` can `dig` gold from adjacent tiles, `move`, and `build` new units, each costing 1 gold. can dig two tiles or build two units per turn, orders are added one after another. sees near, slow move, no shoot.
`REC` can `move` fast and sees very far. no shoot.
`GUN` is a static emplacement. can `indirekt fire` far, attacking three random tiles within radius, destroyed after making eight shots. no move, can't see.
`TONK` can `move`, and can `direkt fire`, attacking selected tile within range. can withstand an extra hit, medium move, medium see.

An `MCV` destroyed while carrying gold leaves `scrap` that blocks its tile. Digging it gives one gold, any hit destroys it.
Enemy guns stay on the map once spotted, until their tile is seen empty.
Tiles hit by indirekt fire flash a red sector on the side the shells came from.
Orders can be prepared while other players make theirs, they are submitted on your turn.
Games can have a turn timer, set when requesting a game in a lobby or with `turn_time` in config.toml. When it runs out, the orders prepared so far are submitted.
Games are free for all or team games: two teams of two, two teams of three or three teams of two, picked when requesting a game in a lobby or with `team_size` in config.toml. Teams spawn together, share what they see and remember, take turns alternately, and the last team standing wins. Players pick their team after joining, with arrows, and the game starts once everyone pressed `Enter` to confirm.

> [!IMPORTANT]
> Player names identify you on a server, pick an unique one. The client asks for a name on start unless it's set with `--name` or in config.toml

- `P` toggles post effects shader
- `ctrl`+`P` reloads post effects shader from file, useful for adjusting or customizing
- `[` / `]` lower and raise post effects intensity
- `F1` opens settings, including post effects distortion, decoloration and CRT pixel size
- Settings are saved per player name to `settings.toml` and restored on start, `--renderer` overrides the saved renderer
- Game servers record every game under `replays/`. When a game ends the client asks whether to save the replay, into its own `replays/` folder, and then whether to watch it. Saved replays are also listed under `WATCH A REPLAY` in the lobby menu
- In a replay, `Left`/`Right` step through the turns, `Space` toggles automatic playback, `Tab` switches between the players' views and the whole map, `Esc` leaves
- `F2` switches between 2D and 3D renderers, the default is set with `renderer` in config.toml
- `F12` saves a screenshot
- Window is resizable
- A lost connection is retried every three seconds, rejoining the game where it was

### In menu
- Arrows / `WASD` and `Enter` to navigate menu, adjust parameters and select items

### In game
- `Z/X/C/V` to pick order types
- `Enter` to submit orders
- Hovering a unit shows its vision range in blue and attack range in red, so does placing an attack or picking a build site; a move preview shows the vision from the destination
- `Esc` or right click to abort current order placement
- `Esc` with nothing selected leaves the game for the lobby, when the client was started with one
- `F1` to open settings menu

#### 2D camera
- `WASD` or click and drag to pan camera
- `Q/E` or mousewheel to zoom

#### 3D camera
- `WASD` or click and drag to pan camera
- `Q/E` or right click and drag to orbit
- `R/F` to tilt, right click and drag works too
- Mousewheel or `-/=` to zoom
- `Home` resets the view
- The dark tile beyond the map's north-eastern corner is a compass, its red sectors point north, which is up in the 2D view
- Field of view, tilt and dithering size can be adjusted in settings

### Unit models
The 3D renderer loads `assets/3d/<unit>.obj` for a solid unit, or `assets/3d/<unit>-hull.obj` with an optional `<unit>-turret.obj`, where `<unit>` is `mcv`, `tonk` or `gun`, and falls back to placeholder boxes. Models are Z-up and X-forward with the base on the origin, turrets turn around the vertical axis through the origin. Faces without normals are flat shaded. One meter is 0.4 of the distance between neighboring hex centers, a hull reaching further than 1.25 meters from its center is shrunk to fit its hex. Models are tinted with the player color

## Credits
- [toml_parser](https://github.com/Up05/toml_parser)
- Post effects shader by [@BitOfGold](https://www.shadertoy.com/view/3tVBWR)
- VCR OSD Mono by [Riciery Leal aka mrmanet](https://www.dafont.com/vcr-osd-mono.font)
- 3D renderer and rehaul by Claude

Sounds from [(freesound.org)](https://freesound.org/), original posts can be found by id
- 425728__moogy73__click01.wav
- 538155__fupicat__switch.wav (unused)
- 658594__javieralejp2__clic-alerta.wav
- 683048__squirrel_404__click-tick.wav
- 770201__yuugfr1a__modern-ui-click.wav
- 770203__yuugfr1a__modern-ui-hover.wav

fuck chess