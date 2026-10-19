package game

import "core:fmt"
import "core:os"
import "core:strings"

import "../lib/toml"

// per player settings, kept next to config.toml
SETTINGS_FILE :: "settings.toml"

ClientSettings :: struct {
	renderer3D: bool,
	postfx: bool,
	postfxIntensity: f32,
	postfxDistortion: f32,
	postfxDecoloration: f32,
	postfxPixelScale: f32,
	fov: f32,
	tilt: f32,
	dither: f32
}

@(private="file")
store: struct {
	// every player in the file, so saving one keeps the others
	players: map[string]ClientSettings,
	name: string,
	saved: ClientSettings,
	loaded: bool
}

// reads the file and applies the player's settings
// `rendererFromCommandLine` wins over the saved renderer, the saved one over config.toml
loadClientSettings :: proc(name: string, rendererFromCommandLine: bool) {
	store.name = strings.clone(name)
	readSettingsFile()

	current := currentClientSettings()
	saved, found := store.players[store.name]
	if found {
		if rendererFromCommandLine do saved.renderer3D = current.renderer3D
		applyClientSettings(saved)
	}
	store.saved = currentClientSettings()
	store.loaded = true
}

// writes the file when something changed; skipped while a slider is dragged
saveClientSettingsIfChanged :: proc(force := false) {
	if !store.loaded do return
	if !force && settingsSliderDragging() do return
	current := currentClientSettings()
	if current == store.saved do return

	store.saved = current
	store.players[store.name] = current
	writeSettingsFile()
}

@(private="file")
currentClientSettings :: proc() -> ClientSettings {
	s := ClientSettings {
		renderer3D = activeView == &VIEW_3D,
		postfx = postfxEnabled,
		postfxIntensity = postfxShader.state.intensity,
		postfxDistortion = postfxShader.state.distortion,
		postfxDecoloration = postfxShader.state.decoloration,
		postfxPixelScale = postfxShader.state.pixelScale,
	}
	exportSettings3D(&s)
	return s
}

@(private="file")
applyClientSettings :: proc(s: ClientSettings) {
	activeView = s.renderer3D ? &VIEW_3D : &VIEW_2D
	postfxEnabled = s.postfx
	postfxShader.state.intensity = clamp(s.postfxIntensity, 0, 1)
	postfxShader.state.distortion = clamp(s.postfxDistortion, 0, 1)
	postfxShader.state.decoloration = clamp(s.postfxDecoloration, 0, 1)
	postfxShader.state.pixelScale = clamp(s.postfxPixelScale, .5, 4)
	importSettings3D(s)
}

@(private="file")
readSettingsFile :: proc() {
	if !os.exists(SETTINGS_FILE) do return
	root, err := toml.parse_file(SETTINGS_FILE, context.temp_allocator)
	if err.type != .None {
		fmt.println("can't read", SETTINGS_FILE, err)
		return
	}
	users, hasUsers := toml.get(^toml.Table, root, "users")
	if !hasUsers do return

	// starts from the current values so missing keys keep their defaults
	defaults := currentClientSettings()
	for name, value in users^ {
		table, isTable := value.(^toml.Table)
		if !isTable do continue

		number :: proc(table: ^toml.Table, key: string, fallback: f32) -> f32 {
			if f, ok := toml.get(f64, table, key); ok do return f32(f)
			if i, ok := toml.get(i64, table, key); ok do return f32(i)
			return fallback
		}
		flag :: proc(table: ^toml.Table, key: string, fallback: bool) -> bool {
			return toml.get(bool, table, key) or_else fallback
		}

		s := defaults
		if renderer, ok := toml.get(string, table, "renderer"); ok do s.renderer3D = renderer == "3d"
		s.postfx = flag(table, "postfx", s.postfx)
		s.postfxIntensity = number(table, "postfx_intensity", s.postfxIntensity)
		s.postfxDistortion = number(table, "postfx_distortion", s.postfxDistortion)
		s.postfxDecoloration = number(table, "postfx_decoloration", s.postfxDecoloration)
		s.postfxPixelScale = number(table, "postfx_pixel_scale", s.postfxPixelScale)
		s.fov = number(table, "fov", s.fov)
		s.tilt = number(table, "tilt", s.tilt)
		s.dither = number(table, "dither", s.dither)
		store.players[unquoteKey(name)] = s
	}
}

// the toml library keeps the quotes of quoted keys
@(private="file")
unquoteKey :: proc(key: string) -> string {
	if len(key) < 2 || key[0] != '"' || key[len(key) - 1] != '"' do return strings.clone(key)
	inner := key[1:len(key) - 1]
	b := strings.builder_make()
	for i := 0; i < len(inner); i += 1 {
		if inner[i] == '\\' && i + 1 < len(inner) do i += 1
		strings.write_byte(&b, inner[i])
	}
	return strings.to_string(b)
}

@(private="file")
writeSettingsFile :: proc() {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "# written by the client, one table per player name\n")
	for name, s in store.players {
		escaped, _ := strings.replace_all(name, "\\", "\\\\", context.temp_allocator)
		escaped, _ = strings.replace_all(escaped, "\"", "\\\"", context.temp_allocator)
		fmt.sbprintf(&b, "\n[users.\"%s\"]\n", escaped)
		fmt.sbprintf(&b, "renderer = \"%s\"\n", s.renderer3D ? "3d" : "2d")
		fmt.sbprintf(&b, "postfx = %v\n", s.postfx)
		fmt.sbprintf(&b, "postfx_intensity = %.3f\n", s.postfxIntensity)
		fmt.sbprintf(&b, "postfx_distortion = %.3f\n", s.postfxDistortion)
		fmt.sbprintf(&b, "postfx_decoloration = %.3f\n", s.postfxDecoloration)
		fmt.sbprintf(&b, "postfx_pixel_scale = %.3f\n", s.postfxPixelScale)
		fmt.sbprintf(&b, "fov = %.3f\n", s.fov)
		fmt.sbprintf(&b, "tilt = %.3f\n", s.tilt)
		fmt.sbprintf(&b, "dither = %.3f\n", s.dither)
	}
	if err := os.write_entire_file(SETTINGS_FILE, strings.to_string(b)); err != nil {
		fmt.println("can't write", SETTINGS_FILE, err)
	}
}
