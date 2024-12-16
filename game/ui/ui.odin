package ui

import rl "vendor:raylib"
import "../hex"
import "../utils"
import "core:fmt"

WINDOW :: [2]i32 {640, 480}

camera := rl.Camera2D {
	offset = rl.Vector2 {f32(WINDOW.x) / 2, f32(WINDOW.y) / 2},
	target = rl.Vector2 {0, 0},
	rotation = 0.0,
	zoom = 20.0,
}
pointer: rl.Vector2
pointedCell: hex.Axial

updateIO :: proc() {
	pointer = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

	if rl.IsKeyDown(rl.KeyboardKey.RIGHT) do camera.zoom += 0.1
	else if rl.IsKeyDown(rl.KeyboardKey.LEFT) do camera.zoom -= 0.1
	if camera.zoom < .1 do camera.zoom = .1
	
	pointedCell = hex.worldToAxial(pointer)
}

draw :: proc(world: proc(), hud: proc()) {
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
}

drawOutline :: proc(outline: []hex.Line, color: rl.Color = rl.BLACK) {
	for line in outline {
		vx := line
		rl.DrawTriangleFan(&vx[0], 4, color)
	}
}

drawPath :: proc(path: hex.Path, thickness := f32(.4), color: rl.Color = rl.BLACK) {
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

	for node, index in path {
		vx := hex.vertesex(node, thickness)
		rl.DrawTriangleFan(&vx[0], 6, color)

		if index != len(path) - 1 {
			f := hex.axialToWorld(node)
			t := hex.axialToWorld(path[index + 1])
			drawLine(f, t, thickness, color)
		}
	}
}