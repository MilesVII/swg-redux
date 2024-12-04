package main

import rl "vendor:raylib"
import "hex"
import "core:fmt"
import "utils"
import nbn "nbnet"

WINDOW :: [2]i32 {640, 480}

camera := rl.Camera2D {
	offset = rl.Vector2 {f32(WINDOW.x) / 2, f32(WINDOW.y) / 2},
	target = rl.Vector2 {0, 0},
	rotation = 0.0,
	zoom = 20.0,
}
pointer : rl.Vector2


main :: proc() {
	rl.InitWindow(WINDOW.x, WINDOW.y, "SWGRedux")
	defer rl.CloseWindow()

	init()

	// rl.SetConfigFlags(rl.ConfigFlags{rl.ConfigFlag.MSAA_4X_HINT})
	rl.SetTargetFPS(240)

	for !rl.WindowShouldClose() { // Detect window close button or ESC key
		updateIO()
		update()
		draw()
	}
}


updateIO :: proc() {
	pointer = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

	if rl.IsKeyDown(rl.KeyboardKey.RIGHT) do camera.zoom += 0.1
	else if rl.IsKeyDown(rl.KeyboardKey.LEFT) do camera.zoom -= 0.1
	if camera.zoom < .1 do camera.zoom = .1
}
