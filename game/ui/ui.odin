package ui

import rl "vendor:raylib"

import "core:fmt"
import "core:strings"
import "core:math"

import "../hex"
import "../utils"
import "../shaded"

windowSize := [2]i32 { 640, 480 }

camera := rl.Camera2D {
	offset = rl.Vector2 {f32(windowSize.x) / 2, f32(windowSize.y) / 2},
	target = rl.Vector2 {0, 0},
	rotation = 0.0,
	zoom = 30.0,
}
pointer: rl.Vector2
pointedCell: hex.Axial

UI_TEXT_MOV: rl.Texture2D
UI_TEXT_ATK: rl.Texture2D
UI_TEXT_DIG: rl.Texture2D
UI_TEXT_BLD: rl.Texture2D
UI_TEXT_CLR: rl.Texture2D

UI_TEXT_TNK: rl.Texture2D
UI_TEXT_GUN: rl.Texture2D
UI_TEXT_MCV: rl.Texture2D

UI_TEXT_SUB: rl.Texture2D
UI_TEXT_ABT: rl.Texture2D

DOTTED_FLICKER_S :: 1.0
DOTTED_WIDTH :: 8.0

@(private)
rt: rl.RenderTexture2D
@(private)
rtLoaded := false

initTextTextures :: proc() {
	font := rl.GetFontDefault() // rl.LoadFont("./assets/JetBrainsMono-Regular.ttf")

	fontSize :: 10
	spacing :: 1
	imageMov := rl.ImageTextEx(font, "MOVE", fontSize, spacing, rl.BLACK)
	imageAtk := rl.ImageTextEx(font, "ATACK", fontSize, spacing, rl.BLACK)
	imageDig := rl.ImageTextEx(font, "DIG", fontSize, spacing, rl.BLACK)
	imageBld := rl.ImageTextEx(font, "BUILD", fontSize, spacing, rl.BLACK)
	imageClr := rl.ImageTextEx(font, "CLEAR", fontSize, spacing, rl.BLACK)

	imageTnk := rl.ImageTextEx(font, "TONK", fontSize, spacing, rl.BLACK)
	imageGun := rl.ImageTextEx(font, "GUN", fontSize, spacing, rl.BLACK)
	imageMcv := rl.ImageTextEx(font, "MCV", fontSize, spacing, rl.BLACK)

	imageSub := rl.ImageTextEx(font, "SUBMIT", fontSize, spacing, rl.BLACK)
	imageAbt := rl.ImageTextEx(font, "ABORT", fontSize, spacing, rl.BLACK)

	UI_TEXT_MOV = rl.LoadTextureFromImage(imageMov)
	UI_TEXT_ATK = rl.LoadTextureFromImage(imageAtk)
	UI_TEXT_DIG = rl.LoadTextureFromImage(imageDig)
	UI_TEXT_BLD = rl.LoadTextureFromImage(imageBld)
	UI_TEXT_CLR = rl.LoadTextureFromImage(imageClr)

	UI_TEXT_TNK = rl.LoadTextureFromImage(imageTnk)
	UI_TEXT_GUN = rl.LoadTextureFromImage(imageGun)
	UI_TEXT_MCV = rl.LoadTextureFromImage(imageMcv)

	UI_TEXT_SUB = rl.LoadTextureFromImage(imageSub)
	UI_TEXT_ABT = rl.LoadTextureFromImage(imageAbt)

	rl.UnloadImage(imageMov)
	rl.UnloadImage(imageAtk)
	rl.UnloadImage(imageDig)
	rl.UnloadImage(imageBld)
	rl.UnloadImage(imageClr)

	rl.UnloadImage(imageTnk)
	rl.UnloadImage(imageGun)
	rl.UnloadImage(imageMcv)

	rl.UnloadImage(imageSub)
	rl.UnloadImage(imageAbt)
}

onResize :: proc() {
	windowSize.x = rl.GetScreenWidth()
	windowSize.y = rl.GetScreenHeight()
	if rtLoaded do rl.UnloadRenderTexture(rt)
	rt = rl.LoadRenderTexture(windowSize.x, windowSize.y)
	rtLoaded = true
}

updateIO :: proc() {
	utils.feedClick()

	if rl.IsWindowResized() do onResize()
	dt := rl.GetFrameTime()
	pointer = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

	if rl.IsKeyDown(.E) do camera.zoom += 0.2
	if rl.IsKeyDown(.Q) do camera.zoom -= 0.2
	camera.zoom += rl.GetMouseWheelMove()
	camera.zoom = rl.Clamp(camera.zoom, 5, 100)

	cameraDelta := rl.Vector2 {0, 0}
	if rl.IsMouseButtonDown(.LEFT) {
		mouseDelta := rl.GetMouseDelta()
		cameraDelta += mouseDelta
	}

	keyboardDelta := rl.Vector2 {0, 0}
	if rl.IsKeyDown(.W) do keyboardDelta += {0, -1} // raysan you baka
	if rl.IsKeyDown(.A) do keyboardDelta += {-1, 0}
	if rl.IsKeyDown(.S) do keyboardDelta += {0, 1} // y is up ffs
	if rl.IsKeyDown(.D) do keyboardDelta += {1, 0}
	keyboardDelta = rl.Vector2Normalize(keyboardDelta) * camera.zoom * -1 * .12

	camera.offset += cameraDelta + keyboardDelta

	pointedCell = hex.worldToAxial(pointer)
}

draw :: proc(world: proc(), hud: proc(), pfx: proc(tex: rl.RenderTexture2D)) {
	utils.cursorHoverBegin()
	defer utils.cursorHoverEnd()

	rl.BeginTextureMode(rt)
		rl.ClearBackground(rl.RAYWHITE)

		rl.BeginMode2D(camera)
		world()
		rl.EndMode2D()

		hud()
	rl.EndTextureMode()

	pfx(rt)

	rl.BeginDrawing()
		rl.DrawTextureRec(
			rt.texture,
			{ 0, 0, f32(rt.texture.width), f32(-rt.texture.height) },
			{ 0, 0 }, rl.WHITE
		)
	rl.EndDrawing()
}

drawGrid :: proc(grid: hex.Grid(hex.GridCell)) {
	for cell in grid.cells {
		if cell.visible {

			color := cell.value.color
			if cell.value.fog == .TERRAIN {
				color = color - color / 3
				color.a = 255
			}

			if cell.value.fog == .TERRAIN do color.w = 120
			vertesex := cell.vertesex
			rl.DrawTriangleFan(&vertesex[0], 6, color)

			if cell.value.gold > 0 {
				gvx := hex.vertesex(cell.position.axial, .5)
				rl.DrawTriangleFan(&gvx[0], 6, rl.GOLD)
			}
		}
	}
	drawCellBorder(pointedCell, .2, rl.WHITE)
}

drawOutline :: proc(outline: []hex.Line, color: rl.Color = rl.BLACK) {
	for line in outline {
		vx := line
		rl.DrawTriangleFan(&vx[0], 4, color)
	}
}

drawCellBorder :: proc(position: hex.Axial, thickness: f32, color: rl.Color) {
	v0 := hex.vertesex(position, 1.0 - thickness)
	v1 := hex.vertesex(position, 1.0)

	vx := [14] rl.Vector2 {
		v0[0], v1[0],
		v0[1], v1[1],
		v0[2], v1[2],
		v0[3], v1[3],
		v0[4], v1[4],
		v0[5], v1[5],
		v0[0], v1[0],
	}

	rl.DrawTriangleStrip(&vx[0], 14, color)
}

drawHexLine :: proc(from: hex.Axial, to: hex.Axial, thickness: f32, color: rl.Color = rl.BLACK) {
	f := hex.axialToWorld(from)
	t := hex.axialToWorld(to)
	ray := rl.Vector2Normalize(t - f) * .5
	f += ray
	t += ray * -1
	drawLine(f, t, thickness, color)
}

drawLine :: proc(from: rl.Vector2, to: rl.Vector2, thickness: f32, color: rl.Color = rl.BLACK, striped: ^shaded.StripedShader = nil) {
	ray := to - from
	offv := rl.Vector2Normalize(ray) * thickness * .5
	ninety : f32 = -utils.TAU * .25

	vx := [4]rl.Vector2 {
		from + rl.Vector2Rotate(offv, ninety * 3),
		from + ray + rl.Vector2Rotate(offv, ninety * 3),
		from + ray + rl.Vector2Rotate(offv, ninety),
		from + rl.Vector2Rotate(offv, ninety),
	}
	
	if (striped != nil) {
		striped.state.period = DOTTED_FLICKER_S
		striped.state.width = DOTTED_WIDTH * camera.zoom * .1
		striped.state.direction = rl.Vector2Normalize(to - from) * { 1, -1 } // thanks for uniform y direction raysan
		shaded.updateStripedShader(striped^)
	}

	rl.DrawTriangleFan(&vx[0], 4, color)
}

drawPath :: proc(path: hex.Path, thickness := f32(.4), color: rl.Color = rl.BLACK, striped: ^shaded.StripedShader = nil) {
	for node, index in path {
		if index != len(path) - 1 {
			f, t: rl.Vector2
			isFirst := index == 0
			isLast := index == len(path) - 2

			switch {
				case isFirst:
					f = hex.axialToWorld(node)
					t = hex.axialToWorld(path[index + 1])
					half := (t - f) * .5
					f += half
				case isLast:
					f = hex.axialToWorld(node)
					t = hex.axialToWorld(path[index + 1])
					half := (f - t) * .5
					t += half
				case:
					f = hex.axialToWorld(node)
					t = hex.axialToWorld(path[index + 1])
			}

			      if striped != nil do rl.BeginShaderMode(striped.shader)
			defer if striped != nil do rl.EndShaderMode()

			rl.DrawCircleV(f, thickness * .5, color)
			if isLast do rl.DrawCircleV(t, thickness * .5, color)

			drawLine(f, t, thickness, color, striped)
		}
	}
}

drawTriangle :: proc(position: hex.Axial, up: bool, color: rl.Color, scale := f32(.7)) {
	hexVertesex := hex.vertesex(position, scale)
	vx := up ? swizzle(hexVertesex, 0, 2, 4) : swizzle(hexVertesex, 1, 3, 5)
	rl.DrawTriangle(vx[0], vx[1], vx[2], color)
}

drawGoldMarks :: proc(position: hex.Axial, gold: int) {
	invertedBasis := hex.BASIS_Y
	invertedBasis.y *= -1
	origin0 := hex.axialToWorld(position) + invertedBasis * .5
	origins := [?]rl.Vector2 {
		origin0,
		origin0 + rl.Vector2Rotate(rl.Vector2Normalize(invertedBasis) * .2, utils.TAU * .25),
		origin0 + rl.Vector2Rotate(rl.Vector2Normalize(invertedBasis) * .2, utils.TAU * .75)
	}
	end0 := rl.Vector2Normalize(invertedBasis) * .1
	end1 := rl.Vector2Normalize(invertedBasis) * -.1

	for i in 0..<gold {
		origin := origins[i]
		drawLine(origin + end0, origin + end1, .1, rl.GOLD)
	}
}

drawExplosion :: proc(at: hex.Axial, progress: f32) -> f32 {
	vx := hex.vertesex(at, 1.3)
	color := rl.RED
	color.a = u8(progress * 255)
	rl.DrawTriangleFan(&vx[0], 6, color)

	return rl.GetFrameTime()
}

button :: proc(
	position: rl.Vector2,
	radius: f32,
	caption: rl.Texture2D,
	colors: [2]rl.Color,
	action: proc(),
	hotkey: rl.KeyboardKey = .KEY_NULL,
	disabled := false,
	disabledColor := rl.LIGHTGRAY,
	progressShader: ^shaded.ProgressShader = nil
) -> bool {
	vxOuter := hex.vertesexRaw(position, radius)
	vxInner := hex.vertesexRaw(position, radius * .8)
	hovered := rl.Vector2Length(rl.GetMousePosition() - position) < radius
	borderColor := disabled ? disabledColor : colors[hovered ? 0 : 1]
	bgColor := colors[0]

	if (!disabled) {
		if (progressShader == nil) {
			if rl.IsKeyPressed(hotkey) do action()
			else if hovered && utils.isClicked() do action()
		} else {
			progress := rl.GetFrameTime() / shaded.PROGRESS_FILL_TIME_S
			kDown := rl.IsKeyDown(hotkey)
			mDown := rl.IsMouseButtonDown(.LEFT)
			if !mDown && !kDown do progressShader.state.value = 0

			if kDown && progressShader.state.value < 1.0 {
				progressShader.state.value += progress
				if progressShader.state.value >= 1.0 do action()
			}
			if hovered && mDown && progressShader.state.value < 1.0 {
				progressShader.state.value += progress
				if progressShader.state.value >= 1.0 do action()
			}
		}
	}

	if progressShader == nil {
		rl.DrawTriangleFan(&vxOuter[0], 6, borderColor)
	} else {
		progressShader.state.center = position
		progressShader.state.backColor = borderColor
		progressShader.state.foreColor = rl.RED
		shaded.updateProgressShader(progressShader^)
		rl.BeginShaderMode(progressShader.shader)
		rl.DrawTriangleFan(&vxOuter[0], 6, rl.WHITE)
		rl.EndShaderMode()
	}
	rl.DrawTriangleFan(&vxInner[0], 6, bgColor)
	
	textureSize := [2]f32 {
		f32(caption.width),
		f32(caption.height)
	}

	corner := position - textureSize / 2
	rl.DrawTexture(
		caption,
		i32(corner.x),
		i32(corner.y),
		rl.WHITE
	)

	return hovered && !disabled
}

Button :: struct {
	caption: ^rl.Texture2D,
	action: proc(),
	disabled: bool,
	hotkey: rl.KeyboardKey
}

BUTTON_ROW_HOTKEYS := []rl.KeyboardKey {
	.Z, .X, .C, .V, .B
}

buttonRow :: proc(
	origin: rl.Vector2,
	radius: f32,
	colors: [2]rl.Color,
	buttons: []Button,
	disabledColor := rl.LIGHTGRAY
) {
	buttonCount := len(buttons)

	xStep := radius * 2
	width := xStep * f32(buttonCount - 1)
	xStart := origin.x - width * .5

	y := f32(windowSize.y) - radius * 1.5

	for butt, i in buttons {
		hovered := button(
			{ xStart + xStep * f32(i), y },
			radius,
			butt.caption^,
			colors,
			butt.action,
			BUTTON_ROW_HOTKEYS[i],
			butt.disabled,
			disabledColor
		)
		utils.setCursorHover(hovered)
	}
}
