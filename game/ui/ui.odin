package ui

import rl "vendor:raylib"
import "../hex"
import "../utils"
import "core:fmt"
import "core:strings"
import "core:math"

WINDOW :: [2]i32 {640, 480}

camera := rl.Camera2D {
	offset = rl.Vector2 {f32(WINDOW.x) / 2, f32(WINDOW.y) / 2},
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

	UI_TEXT_MOV = rl.LoadTextureFromImage(imageMov)
	UI_TEXT_ATK = rl.LoadTextureFromImage(imageAtk)
	UI_TEXT_DIG = rl.LoadTextureFromImage(imageDig)
	UI_TEXT_BLD = rl.LoadTextureFromImage(imageBld)
	UI_TEXT_CLR = rl.LoadTextureFromImage(imageClr)

	UI_TEXT_TNK = rl.LoadTextureFromImage(imageTnk)
	UI_TEXT_GUN = rl.LoadTextureFromImage(imageGun)
	UI_TEXT_MCV = rl.LoadTextureFromImage(imageMcv)

	rl.UnloadImage(imageMov)
	rl.UnloadImage(imageAtk)
	rl.UnloadImage(imageDig)
	rl.UnloadImage(imageBld)
	rl.UnloadImage(imageClr)

	rl.UnloadImage(imageTnk)
	rl.UnloadImage(imageGun)
	rl.UnloadImage(imageMcv)
}

updateIO :: proc() {
	dt := rl.GetFrameTime()
	pointer = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

	if rl.IsKeyDown(rl.KeyboardKey.RIGHT) do camera.zoom += 0.1
	else if rl.IsKeyDown(rl.KeyboardKey.LEFT) do camera.zoom -= 0.1
	if camera.zoom < .1 do camera.zoom = .1

	if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
		mouseDelta := rl.GetMouseDelta()
		camera.offset += mouseDelta
	}
	
	pointedCell = hex.worldToAxial(pointer)
}

draw :: proc(world: proc(), hud: proc()) {
	utils.cursorHoverBegin()
	defer utils.cursorHoverEnd()
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.RAYWHITE)

	rl.BeginMode2D(camera)

	world()

	rl.EndMode2D()

	hud()
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
			vertesex := cell.vertesex;
			rl.DrawTriangleFan(&vertesex[0], 6, color)
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

drawLine :: proc(from: rl.Vector2, to: rl.Vector2, thickness: f32, color: rl.Color = rl.BLACK) {
	ray := to - from
	offv := rl.Vector2Normalize(ray) * thickness * .5
	ninety : f32 = -utils.TAU * .25

	vx := [4]rl.Vector2 {
		from + rl.Vector2Rotate(offv, ninety * 3),
		from + ray + rl.Vector2Rotate(offv, ninety * 3),
		from + ray + rl.Vector2Rotate(offv, ninety),
		from + rl.Vector2Rotate(offv, ninety),
	}
	
	rl.DrawTriangleFan(&vx[0], 4, color)
}

drawPath :: proc(path: hex.Path, thickness := f32(.4), color: rl.Color = rl.BLACK) {

	for node, index in path {
		// vx := hex.vertesex(node, thickness)
		// rl.DrawTriangleFan(&vx[0], 6, color)
		rl.DrawCircleV(hex.axialToWorld(node), thickness, color)

		if index != len(path) - 1 {
			f := hex.axialToWorld(node)
			t := hex.axialToWorld(path[index + 1])
			drawLine(f, t, thickness, color)
		}
	}
}

drawTriangle :: proc(position: hex.Axial, up: bool, color: rl.Color, scale := f32(.7)) {
	hexVertesex := hex.vertesex(position, scale)
	vx := up ? swizzle(hexVertesex, 0, 2, 4) : swizzle(hexVertesex, 1, 3, 5)
	rl.DrawTriangle(vx[0], vx[1], vx[2], color)
}

button :: proc(
	position: rl.Vector2,
	radius: f32,
	caption: rl.Texture2D,
	colors: [2]rl.Color,
	action: proc(),
	disabled := false,
	disabledColor := rl.LIGHTGRAY
) -> bool {
	vxOuter := hex.vertesexRaw(position, radius)
	vxInner := hex.vertesexRaw(position, radius * .8)
	hovered := rl.Vector2Length(rl.GetMousePosition() - position) < radius
	borderColor := disabled ? disabledColor : colors[hovered ? 0 : 1]
	bgColor := colors[0]

	rl.DrawTriangleFan(&vxOuter[0], 6, borderColor)
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

	if hovered && !disabled {
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) do action()

		return true
	}

	return false
}

Button :: struct {
	caption: ^rl.Texture2D,
	action: proc(),
	disabled: bool
}

buttonRow :: proc(
	origin: rl.Vector2,
	radius: f32,
	colors: [2]rl.Color,
	buttons: []Button,
	disabledColor := rl.LIGHTGRAY
) {
	buttonCount := len(buttons)

	xStep := radius * 2.5
	width := xStep * f32(buttonCount - 1)
	xStart := origin.x - width * .5

	y := f32(WINDOW[1]) - radius * 1.5

	for butt, i in buttons {
		hovered := button(
			{ xStart + xStep * f32(i), y },
			radius,
			butt.caption^,
			colors,
			butt.action,
			butt.disabled,
			disabledColor
		)
		utils.setCursorHover(hovered)
	}
}
