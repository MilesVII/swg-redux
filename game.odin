package main

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
	
	rl.EndMode2D()

	rl.DrawText(fmt.ctprint(pointedCell), 0, 0, 8, rl.RED)
	rl.DrawText(fmt.ctprint(1.0 / rl.GetFrameTime()), 0, 8, 8, rl.RED)
}
