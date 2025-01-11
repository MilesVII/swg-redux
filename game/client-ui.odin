package game

import rl "vendor:raylib"

import "core:math"
import "core:fmt"

import "ui"
import "utils"
import "hex"
import "shaded"

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
	switch clientState.status {
		case .CONNECTING: rl.DrawText("Connecting to server", 4, 4, 10, rl.BLACK)
		case .LOBBY:      rl.DrawText("Waiting for players to join", 4, 4, 10, rl.BLACK)
		case .PLAYING:    rl.DrawText("Your turn", 4, 4, 10, rl.RED)
		case .WAITING:    rl.DrawText("Waiting for other players", 4, 4, 10, rl.BLACK)
		case .FINISH:     rl.DrawText("Game over", 4, 4, 10, rl.BLACK)
	}
	framerate := math.round(1.0 / rl.GetFrameTime())
	rl.DrawText(fmt.ctprint(framerate), 4, 16, 10, rl.RED)

	if clientState.status != .PLAYING {
		selectedUnit = nil
		return
	}

	rl.BeginMode2D(ui.camera)
	drawOrders(clientState.orders)
	rl.EndMode2D()

	if selectedUnit != nil do drawOrdersPreview()

	drawTurnControl()
}

drawOrdersPreview :: proc() {
	switch clientState.uiState {
		case .DISABLED:
		case .FREE:
			drawOrdersControl()
		case .ORDER_BLD:
			drawBuildUnitsControl()

			gridRadius := clientState.game.grid.radius
			pointedIndex := hex.axialToIndex(ui.pointedCell, gridRadius)
			buildingAllowed :=
				hex.distance(selectedUnit.position, ui.pointedCell) == 1 && 
				hex.isWithinGrid(ui.pointedCell, gridRadius) && 
				clientState.game.grid.cells[pointedIndex].value.walkable &&
				noOrdersAt(ui.pointedCell, clientState.orders)

			if buildingAllowed {
				utils.setCursorHover(true)
				rl.BeginMode2D(ui.camera)
				ui.drawCellBorder(
					ui.pointedCell,
					.2,
					rl.YELLOW
				)
				rl.EndMode2D()
				
				if utils.isClicked() {
					createOrder(selectedUnit.id, Order {
						target = ui.pointedCell,
						targetUnitType = selectedBuildingUnit,
						type = .BUILD
					})
				}
			}
		case .ORDER_MOV:
			rl.BeginMode2D(ui.camera)
			allowedCells := hex.findWalkableOutline(
				clientState.game.grid,
				selectedUnit.position,
				MOVING[selectedUnit.type]
			)
			ui.drawOutline(hex.outline(allowedCells), rl.BLACK)
			movingAllowed :=
				ui.pointedCell != selectedUnit.position &&
				utils.includes(allowedCells, &ui.pointedCell) &&
				noOrdersAt(ui.pointedCell, clientState.orders)
			
			if movingAllowed {
				utils.setCursorHover(true)
				path, _found := hex.findPath(clientState.game.grid, selectedUnit.position, ui.pointedCell)
				if len(path) > 2 do ui.drawPath(path, .12, rl.BLUE, &stripeShader)
				ui.drawCellBorder(
					ui.pointedCell,
					.2,
					rl.BLUE
				)

				if utils.isClicked() {
					createOrder(selectedUnit.id, Order {
						target = ui.pointedCell,
						type = .MOVE
					})
				}
			}
			rl.EndMode2D()
		case .ORDER_DIG:
			gridRadius := clientState.game.grid.radius
			pointedIndex := hex.axialToIndex(ui.pointedCell, gridRadius)
			diggingAllowed :=
				hex.distance(selectedUnit.position, ui.pointedCell) == 1 && 
				hex.isWithinGrid(ui.pointedCell, gridRadius) && 
				clientState.game.grid.cells[pointedIndex].value.gold > 0 &&
				noOrdersAt(ui.pointedCell, clientState.orders)

			if diggingAllowed {
				utils.setCursorHover(true)
				rl.BeginMode2D(ui.camera)
				ui.drawCellBorder(
					ui.pointedCell,
					.2,
					rl.GOLD
				)
				rl.EndMode2D()
				
				if utils.isClicked() {
					createOrder(selectedUnit.id, Order {
						target = ui.pointedCell,
						type = .DIG
					})
				}
			}
		case .ORDER_ATK:
			attackAllowed :=
				hex.distance(selectedUnit.position, ui.pointedCell) <= ARANGE[selectedUnit.type]

			if selectedUnit.type == .TONK {
				attackAllowed &&=
					hex.isVisible(clientState.game.grid, selectedUnit.position, ui.pointedCell)
			}

			if attackAllowed {
				rl.BeginMode2D(ui.camera)
				ui.drawHexLine(
					selectedUnit.position,
					ui.pointedCell,
					.12, rl.RED
				)

				if selectedUnit.type == .TONK {
					ui.drawCellBorder(
						ui.pointedCell,
						.2, rl.RED
					)
				} else {
					area := hex.nbs(ui.pointedCell)
					lines := hex.outline(area[:], .2)
					ui.drawOutline(lines, rl.RED)
				}
				rl.EndMode2D()

				if utils.isClicked() {
					createOrder(selectedUnit.id, Order {
						target = ui.pointedCell,
						type = selectedUnit.type == .TONK ? .DIREKT : .INDIREKT
					})
				}
			}
	}
}

createOrder :: proc(unitId: int, order: Order) {
	fmt.println(unitId)
	clientState.orders[unitId] = order
	clientState.uiState = .FREE
	selectedUnit = nil
}

drawOrders :: proc(orders: OrderSet) {
	for unitId, order in orders {
		if selectedUnit != nil && selectedUnit.id == unitId && clientState.uiState != .FREE do continue
		unit, ok := findUnitById(clientState.game.players[clientState.currentPlayer].units[:], unitId)
		if !ok do continue
		
		switch order.type {
			case .BUILD:
				ui.drawCellBorder(
					order.target,
					.2, rl.DARKGRAY
				)
			case .DIG:
				ui.drawCellBorder(
					order.target,
					.2, rl.GOLD
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
				path, _found := hex.findPath(clientState.game.grid, unit.position, order.target)
				if len(path) > 2 do ui.drawPath(path, .12, rl.BLUE, &stripeShader)
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
		f32(ui.windowSize.x) * .5,
		f32(ui.windowSize.y) - buttonSize * 1.5
	}

	orderExists := selectedUnit.id in clientState.orders
	row := BUTTON_ROWS[selectedUnit.type]
	row[0].disabled = !orderExists

	if selectedUnit.type == .MCV {
		row[1].disabled = selectedUnit.gold >= 3 // DIG
		row[3].disabled = selectedUnit.gold <= 0 // BUILD
	}
	

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
		f32(ui.windowSize.x) * .5,
		f32(ui.windowSize.y) - buttonSize * 1.5
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
		f32(ui.windowSize.x) - buttonSize * 2.5,
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
	if selectedUnit != nil {
		ui.button(
			orgn + (hex.BASIS_Y * 2 * buttonSize),
			buttonSize,
			ui.UI_TEXT_ABT,
			{
				rl.WHITE,
				rl.BLACK
			},
			proc() {
				selectedUnit = nil
				clientState.uiState = .FREE
			},
			.ESCAPE
		)
	}
}

noOrdersAt :: proc(at: hex.Axial, orders: OrderSet) -> bool {
	for _, order in orders {
		if order.type == .DIREKT || order.type == .INDIREKT do continue

		if order.target == at do return false
	}

	return true
}
