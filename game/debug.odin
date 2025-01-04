package game

import rl "vendor:raylib"

import "core:fmt"

import "hex"
import "ui"

@(private="file")
debugGrid : GameGrid

debug :: proc() {
	rl.InitWindow(ui.windowSize.x, ui.windowSize.y, "SWGRedux Debug")
	defer rl.CloseWindow()

	rl.SetTargetFPS(240)
	ui.initTextTextures()

	state := createGame()
	reducedState := getStateForPlayer(&state, 0)
	debugGrid = reducedState.grid

	for !rl.WindowShouldClose() {
		ui.updateIO()
		ui.draw(debugDrawWorld, debugDrawHUD)
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			state.players[0].units[0].position = ui.pointedCell
			deleteState(reducedState)
			reducedState = getStateForPlayer(&state, 0)
			debugGrid = reducedState.grid
		}
	}
}

@(private="file")
debugDrawWorld :: proc() {
	ui.drawGrid(debugGrid)

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
	rl.DrawText(fmt.ctprint(rl.GetFPS()), 0, 8, 8, rl.RED)
}