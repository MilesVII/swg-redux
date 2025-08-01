# Kriegsspiel
A turn-based wargame featuring fog of war, bestagons and indirekt fire

## Build instructions
Requires [odin](https://odin-lang.org/docs/install/) to be installed
```
git clone https://github.com/MilesVII/swg-redux
cd swg-redux
odin build .
cp config.toml.example config.toml
```

Specify operating mode if needed:
```
swg-redux --mode client --name username
swg-redux --mode server --port 27014
swg-redux --mode lobby
```
All parameters are optional

### Lobby mode
Clients can connect to lobbies instead of connecting to a server directly right from the start. Lobbies offer an option to connect to started games and can accept new game requests from clients with matching auth token

Refer to `config.toml.example` for config details

## Controls
> [!IMPORTANT]
> Set up an unique user name in config.toml before connecting to a server

- `P` toggles post effects shader
- `ctrl`+`P` reloads post effects shader from file, useful for adjusting or customizing
- Window is resizable

### In menu
- Arrows / `WASD` and `Enter` to navigate menu, adjust parameters and select items

### In game
- `WASD` or click and drag to pan camera
- `Q/E` or mousewheel to zoom
- `Z/X/C/V` to pick order types
- `Enter` to submit orders
- `Esc` to abort current order placement

## Credits
- [toml_parser](https://github.com/Up05/toml_parser)
- Post effects shader by [@BitOfGold](https://www.shadertoy.com/view/3tVBWR)
- VCR OSD Mono by [Riciery Leal aka mrmanet](https://www.dafont.com/vcr-osd-mono.font)

Sounds from [(freesound.org)](https://freesound.org/), original posts can be found by id
- 425728__moogy73__click01.wav
- 538155__fupicat__switch.wav (unused)
- 658594__javieralejp2__clic-alerta.wav
- 683048__squirrel_404__click-tick.wav
- 770201__yuugfr1a__modern-ui-click.wav
- 770203__yuugfr1a__modern-ui-hover.wav

fuck chess