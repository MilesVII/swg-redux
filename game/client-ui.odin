package game

import rl "vendor:raylib"

import "core:math"
import "core:fmt"

import "ui"
import "utils"
import "hex"

@(private)
selectedUnit : ^GameUnit = nil

BUTTON_ATK := ui.Button {
	action = proc() {
		clientState.uiState = .ORDER_ATK
	},
	caption = &ui.UI_TEXT_ATK
}
BUTTON_DIG := ui.Button {
	action = proc() {
		clientState.uiState = .ORDER_DIG
	},
	caption = &ui.UI_TEXT_DIG
}
BUTTON_MOV := ui.Button {
	action = proc() {
		clientState.uiState = .ORDER_MOV
	},
	caption = &ui.UI_TEXT_MOV
}
BUTTON_BLD := ui.Button {
	action = proc() {
		clientState.uiState = .ORDER_BLD
	},
	caption = &ui.UI_TEXT_BLD
}
BUTTON_CLR := ui.Button {
	action = proc() {
		delete_key(&clientState.orders, selectedUnit.id)
		clientState.uiState = .FREE
	},
	caption = &ui.UI_TEXT_CLR
}

BUTTON_ROWS := [GameUnitType][]ui.Button {
	.TONK = {
		BUTTON_CLR,
		BUTTON_ATK,
		BUTTON_MOV
	},
	.GUN = {
		BUTTON_CLR,
		BUTTON_ATK
	},
	.MCV = {
		BUTTON_CLR,
		BUTTON_DIG,
		BUTTON_MOV,
		BUTTON_BLD
	}
}

@(private)
clientDrawHUD :: proc() {
	// fmt.ctprint(ui.pointedCell)
	switch clientState.status {
		case .CONNECTING: rl.DrawText("Connecting to server", 4, 4, 10, rl.BLACK)
		case .LOBBY:      rl.DrawText("Waiting for players to join", 4, 4, 10, rl.BLACK)
		case .PLAYING:    rl.DrawText("Your turn", 4, 4, 10, rl.RED)
		case .WAITING:    rl.DrawText("Waiting for other players", 4, 4, 10, rl.BLACK)
		case .FINISH:     rl.DrawText("Game over", 4, 4, 10, rl.BLACK)
	}
	framerate := math.round(1.0 / rl.GetFrameTime())
	rl.DrawText(fmt.ctprint(framerate), 4, 16, 10, rl.RED)

	if clientState.status == .PLAYING {
		if selectedUnit != nil {
			if clientState.uiState == .FREE {
				drawOrdersControl()
			}

			if clientState.uiState == .ORDER_BLD {
				// buildingAllowed := hex.distance(selectedUnit.position, ui.pointedCell) == 1
				
				// buildingAllowed = buildingAllowed && clientState.game.grid.cells
				// ui.drawLine(selectedUnit.position, ui.pointedCell, .3, rl.ORANGE)
			}
			if clientState.uiState == .ORDER_MOV {
				allowedCells := hex.findWalkableOutline(
					clientState.game.grid,
					selectedUnit.position,
					MOVING[selectedUnit.type]
				)
				movingAllowed := utils.includes(allowedCells, &ui.pointedCell)
				
				if movingAllowed {
					ui.drawLine(
						hex.axialToWorld(selectedUnit.position),
						hex.axialToWorld(ui.pointedCell),
						1, rl.BLUE
					)
					if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
						order := Order {
							target = ui.pointedCell,
							type = .MOVE
						}
						clientState.orders[selectedUnit.id] = order
						clientState.uiState = .FREE
						selectedUnit = nil
					}
				}
			}
		}
	} else do selectedUnit = nil
}

@(private="file")
drawOrdersControl :: proc() {
	buttonSize := f32(32.0)
	origin := rl.Vector2 {
		f32(ui.WINDOW[0]) * .5,
		f32(ui.WINDOW[1]) - buttonSize * 1.5
	}

	orderExists := selectedUnit.id in clientState.orders
	row := BUTTON_ROWS[selectedUnit.type]
	row[0].disabled = !orderExists

	ui.buttonRow(
		origin,
		buttonSize,
		{
			rl.WHITE,
			rl.BLACK
		},
		row
	)
}