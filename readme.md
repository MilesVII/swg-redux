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

Servers and lobbies can be built without the client, which leaves out raylib, X11 and OpenGL:
```
odin build . -define:HEADLESS=true
```

Specify operating mode if needed:
```
swg-redux --mode client --name username --renderer 3d
swg-redux --mode server --port 27014
swg-redux --mode lobby
```
All parameters are optional

### Lobby mode
Clients can connect to lobbies instead of connecting to a server directly right from the start. Lobbies offer an option to connect to started games and can accept new game requests from clients with matching auth token

Refer to `config.toml.example` for config details

## Rules and Controls
`MCV` can `dig` gold from adjacent tiles, `move`, and `build` new units, each costing 1 gold. sees far, no shoot.
`GUN` is a static emplacement. can `indirekt fire` far, attacking three random tiles within radius. no move, can't see.
`TONK` can `move`, and can `direkt fire`, attacking selected tile within range. can withstand an extra hit, medium move, medium see.

> [!IMPORTANT]
> Player names identify you on a server, pick an unique one. The client asks for a name on start unless it's set with `--name` or in config.toml

- `P` toggles post effects shader
- `ctrl`+`P` reloads post effects shader from file, useful for adjusting or customizing
- `[` / `]` lower and raise post effects intensity
- `F1` opens settings, including post effects distortion, decoloration and CRT pixel size
- Settings are saved per player name to `settings.toml` and restored on start, `--renderer` overrides the saved renderer
- `F2` switches between 2D and 3D renderers, the default is set with `renderer` in config.toml
- `F12` saves a screenshot
- Window is resizable

### In menu
- Arrows / `WASD` and `Enter` to navigate menu, adjust parameters and select items

### In game
- `Z/X/C/V` to pick order types
- `Enter` to submit orders
- `Esc` to abort current order placement
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