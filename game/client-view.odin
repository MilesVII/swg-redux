package game

import rl "vendor:raylib"

import "core:fmt"

import "ui"
import "hex"
import "utils"

// everything renderer-specific in the client goes through one of these
ClientView :: struct {
	name: cstring,
	init: proc(),
	deinit: proc(),
	// camera controls and picking, must update ui.pointedCell
	update: proc(cameraLocked: bool, inputBlocked: bool),
	// draws the world into the current render target; the HUD is drawn on top afterwards
	scene: proc(),
	// center the camera on a cell
	focus: proc(at: hex.Axial),
	// screen position of a cell, used by screen space effects
	toScreen: proc(at: hex.Axial) -> rl.Vector2,
	// explosion timeline hooks, see updateExplosions
	onExplosionStart: proc(bonk: Explosion),
	onExplosionImpact: proc(bonk: Explosion),
	// extra rows for the settings panel
	settings: proc(layout: ^SettingsLayout),
	// screen space parts of the world, drawn under the rest of the HUD
	hud: proc(),
}

CLIENT_VIEWS := [?]^ClientView { &VIEW_2D, &VIEW_3D }

@(private)
activeView: ^ClientView = &VIEW_2D

// --- settings panel, toggled with F1 ---

@(private)
settingsOpen := false

SettingsLayout :: struct {
	x: f32,
	y: f32,
	width: f32
}

SliderFormat :: enum { PERCENT, DEGREES, PLAIN }

@(private="file")
SETTINGS_WIDTH :: f32(450)
@(private="file")
SETTINGS_ROW :: FONT_SIZE + UI_SPACING * 1.5
@(private="file")
SETTINGS_TOP :: f32(150)
@(private="file")
HINT_COLOR :: rl.Color { 150, 150, 150, 255 }

@(private="file")
settingsRect: rl.Rectangle
// slider being dragged, keeps the drag alive when the cursor leaves the panel
@(private="file")
activeSlider: rawptr
// widest slider caption since the panel was opened, so all sliders start at the same x
@(private="file")
labelColumn: f32

// settings aren't saved mid-drag
settingsSliderDragging :: proc() -> bool {
	return activeSlider != nil
}

// true when the panel should swallow mouse input this frame
@(private)
settingsPanelHovered :: proc() -> bool {
	if !settingsOpen do return false
	return activeSlider != nil || rl.CheckCollisionPointRec(rl.GetMousePosition(), settingsRect)
}

@(private)
drawSettingsPanel :: proc() {
	if !settingsOpen {
		activeSlider = nil
		labelColumn = 0
		return
	}
	if !rl.IsMouseButtonDown(.LEFT) do activeSlider = nil

	windowSize := ui.windowSizeF()
	// sized by the previous frame, rows don't change often
	height := settingsRect.height
	origin := rl.Vector2 {
		windowSize.x - SETTINGS_WIDTH - UI_SPACING,
		max(min(SETTINGS_TOP, windowSize.y - height - UI_SPACING), UI_SPACING)
	}

	rl.DrawRectangleRec({ origin.x, origin.y, SETTINGS_WIDTH, height }, { 0, 0, 0, 200 })
	rl.DrawRectangleLinesEx({ origin.x, origin.y, SETTINGS_WIDTH, height }, 1, rl.WHITE)

	layout := SettingsLayout { origin.x + UI_SPACING * 2, origin.y + UI_SPACING, SETTINGS_WIDTH - UI_SPACING * 4 }
	if settingsButton(&layout, "SETTINGS [F1]", rl.YELLOW) do settingsOpen = false
	if settingsButton(&layout, fmt.ctprintf("POSTFX %s [P]", postfxEnabled ? "ON" : "OFF")) do postfxEnabled = !postfxEnabled
	settingsSlider(&layout, "POSTFX [ ]", &postfxShader.state.intensity, 0, 1, .PERCENT)
	settingsSlider(&layout, "DISTORTION", &postfxShader.state.distortion, 0, 1, .PERCENT)
	settingsSlider(&layout, "DECOLORATION", &postfxShader.state.decoloration, 0, 1, .PERCENT)
	settingsSlider(&layout, "CRT PIXEL", &postfxShader.state.pixelScale, .5, 4, .PLAIN)
	if settingsButton(&layout, fmt.ctprintf("RENDERER %s [F2]", activeView.name)) do switchView()
	if activeView.settings != nil do activeView.settings(&layout)

	settingsRect = { origin.x, origin.y, SETTINGS_WIDTH, layout.y - origin.y + UI_SPACING }
}

@(private="file")
rowText :: proc(layout: ^SettingsLayout, text: cstring, color: rl.Color) {
	rl.DrawTextEx(
		vcrFont, text,
		{ layout.x, layout.y + (SETTINGS_ROW - FONT_SIZE) * .5 },
		FONT_SIZE, FONT_SPACING, color
	)
}

@(private="file")
rowRect :: proc(layout: ^SettingsLayout) -> rl.Rectangle {
	return { layout.x - UI_SPACING, layout.y, layout.width + UI_SPACING * 2, SETTINGS_ROW }
}

// a hint that can't be clicked
settingsLabel :: proc(layout: ^SettingsLayout, text: cstring, color := HINT_COLOR) {
	rowText(layout, text, color)
	layout.y += SETTINGS_ROW
}

// a row that highlights under the cursor, returns true when clicked
settingsButton :: proc(layout: ^SettingsLayout, text: cstring, color := rl.WHITE) -> bool {
	row := rowRect(layout)
	hovered := activeSlider == nil && rl.CheckCollisionPointRec(rl.GetMousePosition(), row)
	if hovered {
		rl.DrawRectangleRec(row, { 255, 255, 255, 40 })
		utils.setCursorHover(true)
	}
	rowText(layout, text, hovered ? rl.YELLOW : color)
	layout.y += SETTINGS_ROW
	return hovered && rl.IsMouseButtonPressed(.LEFT)
}

// returns true while the value is being changed
settingsSlider :: proc(
	layout: ^SettingsLayout,
	label: cstring,
	value: ^f32,
	minValue: f32,
	maxValue: f32,
	format: SliderFormat
) -> bool {
	caption: cstring
	switch format {
		case .PERCENT: caption = fmt.ctprintf("%s %d%%", label, int(value^ * 100 + .5))
		case .DEGREES: caption = fmt.ctprintf("%s %.1f DEG", label, value^)
		case .PLAIN:   caption = fmt.ctprintf("%s %.1f", label, value^)
	}
	captionWidth := rl.MeasureTextEx(vcrFont, caption, FONT_SIZE, FONT_SPACING).x
	labelColumn = max(labelColumn, captionWidth + UI_SPACING * 3)

	row := rowRect(layout)
	mouse := rl.GetMousePosition()
	hovered := rl.CheckCollisionPointRec(mouse, row)
	if hovered && rl.IsMouseButtonPressed(.LEFT) do activeSlider = value
	changing := activeSlider == value
	if hovered || changing do rl.DrawRectangleRec(row, { 255, 255, 255, 25 })

	bar := rl.Rectangle {
		layout.x + labelColumn,
		layout.y + SETTINGS_ROW * .5 - 3,
		max(layout.width - labelColumn - UI_SPACING, 10),
		6
	}
	if changing {
		t := clamp((mouse.x - bar.x) / bar.width, 0, 1)
		value^ = minValue + t * (maxValue - minValue)
	}

	rowText(layout, caption, changing ? rl.YELLOW : rl.WHITE)
	t := clamp((value^ - minValue) / (maxValue - minValue), 0, 1)
	rl.DrawRectangleRec(bar, rl.DARKGRAY)
	rl.DrawRectangleRec({ bar.x, bar.y, bar.width * t, bar.height }, changing ? rl.YELLOW : rl.WHITE)
	rl.DrawCircleV({ bar.x + bar.width * t, bar.y + bar.height * .5 }, 6, changing ? rl.YELLOW : rl.WHITE)

	layout.y += SETTINGS_ROW
	return changing
}
