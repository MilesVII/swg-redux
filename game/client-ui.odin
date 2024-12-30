package game

import rl "vendor:raylib"

import "core:math"
import "core:fmt"

import "ui"
import "utils"
import "hex"

@(private)
selectedUnit : ^GameUnit = nil
@(private)
selectedBuildingUnit : GameUnitType

BUTTON_ATK := ui.Button {
	action = proc() {
		clientState.uiState = .ORDER_ATK
	},
	caption = &ui.UI_TEXT_ATK,
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

BUTTON_ROW_BLD := [?]ui.Button {
	{
		action = proc() {
			selectedBuildingUnit = .TONK
		},
		caption = &ui.UI_TEXT_TNK
	},
	{
		action = proc() {
			selectedBuildingUnit = .GUN
		},
		caption = &ui.UI_TEXT_GUN
	},
	{
		action = proc() {
			selectedBuildingUnit = .MCV
		},
		caption = &ui.UI_TEXT_MCV
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
				gridRadius := clientState.game.grid.radius
				pointedIndex := hex.axialToIndex(ui.pointedCell, gridRadius)
				buildingAllowed :=
					hex.distance(selectedUnit.position, ui.pointedCell) == 1 && 
					hex.isWithinGrid(ui.pointedCell, gridRadius) && 
					clientState.game.grid.cells[pointedIndex].value.walkable

				utils.setCursorHover(true)
				rl.BeginMode2D(ui.camera)
				ui.drawCellBorder(
					ui.pointedCell,
					.2,
					rl.YELLOW
				)
				rl.EndMode2D()
				
				if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
					order := Order {
						target = ui.pointedCell,
						targetUnitType = selectedBuildingUnit,
						type = .BUILD
					}
					clientState.orders[selectedUnit.id] = order
					clientState.uiState = .FREE
					selectedUnit = nil
				}
			}
			if clientState.uiState == .ORDER_MOV {
				allowedCells := hex.findWalkableOutline(
					clientState.game.grid,
					selectedUnit.position,
					MOVING[selectedUnit.type]
				)
				movingAllowed := utils.includes(allowedCells, &ui.pointedCell)
				
				if movingAllowed {
					utils.setCursorHover(true)
					rl.BeginMode2D(ui.camera)
					ui.drawHexLine(
						selectedUnit.position,
						ui.pointedCell,
						.12, rl.BLUE
					)
					ui.drawCellBorder(
						ui.pointedCell,
						.2,
						rl.BLUE
					)
					rl.EndMode2D()

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

		rl.BeginMode2D(ui.camera)
		drawOrders(clientState.orders)
		rl.EndMode2D()
		drawTurnControl()
	} else do selectedUnit = nil
}

drawOrders :: proc(orders: map[int]Order) {
	for unitIndex, order in orders {
		unit := clientState.game.players[clientState.currentPlayer].units[unitIndex]
		switch order.type {
			case .BUILD:
				ui.drawCellBorder(
					order.target,
					.2, rl.ORANGE
				)
			case .DIG:
				ui.drawCellBorder(
					order.target,
					.2, rl.DARKGRAY
				)
			case .DIREKT:
				ui.drawHexLine(
					unit.position,
					order.target,
					.12, rl.RED
				)
				ui.drawCellBorder(
					order.target,
					.2, rl.RED
				)
			case .INDIREKT:
				ui.drawHexLine(
					unit.position,
					order.target,
					.12, rl.RED
				)
				area := hex.nbs(order.target)
				lines := hex.outline(area[:], .2)
				ui.drawOutline(lines, rl.RED)
			case .MOVE:
				ui.drawHexLine(
					unit.position,
					order.target,
					.12, rl.BLUE
				)
				ui.drawCellBorder(
					order.target,
					.2, rl.BLUE
				)
		}
	}
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


@(private="file")
drawBuildUnitsControl :: proc() {
	buttonSize := f32(32.0)
	origin := rl.Vector2 {
		f32(ui.WINDOW[0]) * .5,
		f32(ui.WINDOW[1]) - buttonSize * 1.5
	}

	for &button, index in BUTTON_ROW_BLD {
		button.disabled = index == int(selectedBuildingUnit)
	}

	ui.buttonRow(
		origin,
		buttonSize,
		{
			rl.WHITE,
			rl.BLACK
		},
		BUTTON_ROW_BLD[:],
		rl.RED
	)
}

drawTurnControl :: proc() {
	buttonSize := f32(32.0)
	orgn := rl.Vector2 {
		f32(ui.WINDOW[0]) - buttonSize * 2.5,
		buttonSize * 1.5
	}

	ui.button(
		orgn,
		buttonSize,
		ui.UI_TEXT_SUB,
		{
			rl.WHITE,
			rl.BLACK
		},
		clientSayOrders,
		.ENTER
	)
	// ui.button(
	// 	orgn + (hex.BASIS_Y * 2 * buttonSize),
	// 	buttonSize,
	// 	ui.UI_TEXT_ATK,
	// 	{
	// 		rl.WHITE,
	// 		rl.BLACK
	// 	},
	// 	proc(){},
	// 	.ENTER
	// )
}
