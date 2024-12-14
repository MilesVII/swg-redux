package game

import rl "vendor:raylib"

import "core:fmt"

import "hex"
import "ui"

@(private="file")
debugGrid : GameGrid
@(private="file")
vision: [dynamic]hex.Axial

debug :: proc() {
	rl.InitWindow(ui.WINDOW.x, ui.WINDOW.y, "SWGRedux Debug")
	defer rl.CloseWindow()

	rl.SetTargetFPS(240)

	state := createGame()
	reducedState := getStateForPlayer(state, 0)
	debugGrid = reducedState.grid

	for cell in debugGrid.cells {
		if !cell.visible do continue
		if cell.value.fog == .OBSERVED do append(&vision, cell.position.axial)
	}

	deleteState(reducedState)

	for !rl.WindowShouldClose() {
		ui.updateIO()
		ui.draw(debugDrawWorld, debugDrawHUD)
	}
}

@(private="file")
debugDrawWorld :: proc() {
	ui.drawGrid(debugGrid)
	
	ui.drawOutline(hex.outline(vision[:], .4), rl.RED)

	// walkables := hex.findWalkableOutline(grid, pointedCell, 3)
	walkables, ok := hex.findPath(debugGrid, {0, 0}, ui.pointedCell)
	if ok {
		outline := hex.outline(walkables, .5)
		ui.drawPath(walkables, .3)
	}
}

@(private="file")
debugDrawHUD :: proc() {
	rl.DrawText(fmt.ctprint(ui.pointedCell), 0, 0, 8, rl.RED)
	rl.DrawText(fmt.ctprint(1.0 / rl.GetFrameTime()), 0, 8, 8, rl.RED)
}