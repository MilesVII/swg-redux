package game

import rl "vendor:raylib"
import "hex"
import "core:fmt"
import "utils"

MAP_RADIUS :: 16
HEIGHTS :: 11

grid := hex.grid(MAP_RADIUS, hex.GridCell)

colors : [HEIGHTS]rl.Color = {
	rl.BLUE,
	rl.BLUE,
	rl.BLUE,
	rl.GREEN,
	rl.GREEN,
	rl.GREEN,
	rl.GREEN,
	rl.GREEN,
	rl.YELLOW,
	{154, 66, 66, 255},
	{154, 66, 66, 255}
}

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

init :: proc() {
	for &cell in grid.cells {
		hi := hex.height(cell.position.world, HEIGHTS)
		cell.value.color = colors[hi]
		cell.value.walkable = hi < 8 && hi > 2
	}

	hex.markWalkableAreas(grid)
}

update :: proc() {

}

draw :: proc() {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.RAYWHITE)
	
	rl.BeginMode2D(camera)

	pointedCell := hex.worldToAxial(pointer)

	for cell in grid.cells {
		if cell.visible {
			vertesex := cell.vertesex;
			rl.DrawTriangleFan(&vertesex[0], 6, cell.value.color)
		}
	}
	
	// walkables := hex.findWalkableOutline(grid, pointedCell, 3)
	walkables, ok := hex.findPath(grid, {0, 0}, pointedCell)
	if ok {
		outline := hex.outline(walkables, .5)
		drawOutline(outline)
	}

	rl.EndMode2D()

	rl.DrawText(fmt.ctprint(pointedCell), 0, 0, 8, rl.RED)
	rl.DrawText(fmt.ctprint(1.0 / rl.GetFrameTime()), 0, 8, 8, rl.RED)
}

drawOutline :: proc(outline: []hex.Line) {
	for line in outline {
		vx := line
		rl.DrawTriangleFan(&vx[0], 4, rl.BLACK)
	}
}