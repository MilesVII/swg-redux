package game

import rl "vendor:raylib"
import "hex"
import "core:fmt"
import "utils"

MAP_RADIUS :: 16
HEIGHTS :: 11

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

GameGrid :: hex.Grid(hex.GridCell)

GameState :: struct {
	grid: GameGrid
}

createGame :: proc() -> GameState {
	state := GameState {
		grid = hex.grid(MAP_RADIUS, hex.GridCell)
	}

	for &cell in state.grid.cells {
		hi := hex.height(cell.position.world, HEIGHTS)
		cell.value.color = colors[hi]
		cell.value.walkable = hi < 8 && hi > 2
	}
	hex.markWalkableAreas(state.grid)

	return state
}
