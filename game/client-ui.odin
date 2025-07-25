package game

import rl "vendor:raylib"

import "core:math"
import "core:fmt"
import "core:strings"

import "ui"
import "utils"
import "hex"
import "shaded"

@(private)
selectedUnit : ^GameUnit = nil
@(private)
selectedBuildingUnit : GameUnitType

FONT_SPACING :: f32(.2)
FONT_SIZE :: f32(16)
UI_SPACING :: 6
UI_CORNER_PAD :: [2]f32 { UI_SPACING, UI_SPACING }

BUTTON_ATK := ui.Button {
	action = proc() {
		postponeGenericAction(proc() {
			clientState.uiState = .ORDER_ATK
		})
	},
	caption = &ui.UI_TEXT_ATK,
}
BUTTON_DIG := ui.Button {
	action = proc() {
		postponeGenericAction(proc() {
			clientState.uiState = .ORDER_DIG
		})
	},
	caption = &ui.UI_TEXT_DIG
}
BUTTON_MOV := ui.Button {
	action = proc() {
		postponeGenericAction(proc(){
			clientState.uiState = .ORDER_MOV
		})
	},
	caption = &ui.UI_TEXT_MOV
}
BUTTON_BLD := ui.Button {
	action = proc() {
		postponeGenericAction(proc() {
			clientState.uiState = .ORDER_BLD
		})
	},
	caption = &ui.UI_TEXT_BLD
}
BUTTON_CLR := ui.Button {
	action = proc() {
		postponeGenericAction(proc() {
			delete_key(&clientState.orders, selectedUnit.id)
			clientState.uiState = .FREE
		})
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
			postponeGenericAction(proc() {
				selectedBuildingUnit = .TONK
			})
		},
		caption = &ui.UI_TEXT_TNK
	},
	{
		action = proc() {
			postponeGenericAction(proc() {
				selectedBuildingUnit = .GUN
			})
		},
		caption = &ui.UI_TEXT_GUN
	},
	{
		action = proc() {
			postponeGenericAction(proc() {
				selectedBuildingUnit = .MCV
			})
		},
		caption = &ui.UI_TEXT_MCV
	}
}

@(private)
clientDrawBackground :: proc() {
	rl.ClearBackground(rl.RAYWHITE)
	shaded.updateBackgroundShader(&backgroundShader, ui.camera.offset, ui.camera.zoom)
	rl.BeginShaderMode(backgroundShader.shader)

	from := rl.GetScreenToWorld2D([2]f32 {0, 0}, ui.camera)
	to := rl.GetScreenToWorld2D(ui.windowSizeF(), ui.camera)

	rl.DrawRectanglePro(
		rl.Rectangle {
			x = from.x,
			y = from.y,
			width = to.x - from.x,
			height = to.y - from.y
		},
		rl.Vector2 {0, 0},
		0,
		rl.WHITE
	)
	rl.EndShaderMode()
}

@(private)
clientDrawHUD :: proc() {
	getStatusString :: proc() -> (cstring, rl.Color) {
		switch clientState.status {
			case .CONNECTING_L: return "CONNECTING TO LOBBY", rl.WHITE;
			case .LOBBY:        return "", rl.WHITE;
			case .CONNECTING:   return "CONNECTING TO GAME SERVER", rl.WHITE;
			case .NOT_FULL:     return "WAITING FOR PLAYERS TO JOIN", rl.WHITE;
			case .PLAYING:      return "YOUR TURN", rl.RED;
			case .WAITING:      return "WAITING FOR OTHER PLAYERS", rl.WHITE;
			case .FINISH:       return "GAME OVER", rl.WHITE;
		}
		return "", rl.WHITE
	}

	status, statusColor := getStatusString()
	rl.DrawTextEx(
		vcrFont,
		status,
		UI_CORNER_PAD,
		FONT_SIZE, FONT_SPACING, statusColor
	)
	framerate := math.round(1.0 / rl.GetFrameTime())
	rl.DrawTextEx(
		vcrFont,
		fmt.ctprint(framerate),
		UI_CORNER_PAD + { 0, UI_SPACING + FONT_SIZE },
		FONT_SIZE, FONT_SPACING, rl.RED
	)

	if clientState.status == .LOBBY {
		drawMenu()
	}

	drawFragList()

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
				noOrdersAt(ui.pointedCell, clientState.orders) &&
				noUnitsAt(ui.pointedCell, clientState.game.players[:])

			if buildingAllowed {
				utils.setCursorHover(true)
				rl.BeginMode2D(ui.camera)
				ui.drawCellBorder(
					ui.pointedCell,
					.2,
					rl.YELLOW
				)
				rl.EndMode2D()
				
				if rl.IsMouseButtonPressed(.LEFT) {
					postponeClick(OrderAction {
						unitId = selectedUnit.id,
						order = {
							target = ui.pointedCell,
							targetUnitType = selectedBuildingUnit,
							type = .BUILD
						}
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
			ui.drawOutline(hex.outline(allowedCells), rl.WHITE)
			movingAllowed :=
				ui.pointedCell != selectedUnit.position &&
				utils.includes(allowedCells, &ui.pointedCell) &&
				noOrdersAt(ui.pointedCell, clientState.orders) &&
				noUnitsAt(ui.pointedCell, clientState.game.players[:])
			
			if movingAllowed {
				utils.setCursorHover(true)
				path, _found := hex.findPath(clientState.game.grid, selectedUnit.position, ui.pointedCell)
				if len(path) > 2 do ui.drawPath(path, .12, rl.BLUE, &stripeShader)
				ui.drawCellBorder(
					ui.pointedCell,
					.2,
					rl.BLUE
				)

				if rl.IsMouseButtonPressed(.LEFT) {
					postponeClick(OrderAction {
						unitId = selectedUnit.id,
						order = {
							target = ui.pointedCell,
							type = .MOVE
						}
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

				if rl.IsMouseButtonPressed(.LEFT) {
					postponeClick(OrderAction {
						unitId = selectedUnit.id,
						order = {
							target = ui.pointedCell,
							type = .DIG
						}
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
				indirekt := selectedUnit.type != .TONK

				rl.BeginMode2D(ui.camera)
				ui.drawHexLine(
					selectedUnit.position,
					ui.pointedCell,
					.12, rl.RED,
					indirekt ? 1.5 : 0.5
				)

				if indirekt {
					area := hex.nbs(ui.pointedCell)
					lines := hex.outline(area[:], .2)
					ui.drawOutline(lines, rl.RED)
				} else {
					ui.drawCellBorder(
						ui.pointedCell,
						.2, rl.RED
					)
				}
				rl.EndMode2D()

				if rl.IsMouseButtonPressed(.LEFT) {
					postponeClick(OrderAction {
						unitId = selectedUnit.id,
						order = {
							target = ui.pointedCell,
							type = selectedUnit.type == .TONK ? .DIREKT : .INDIREKT
						}
					})
				}
			}
	}
}

createOrder :: proc(unitId: int, order: Order) {
	rl.PlaySound(placeSound)
	clientState.orders[unitId] = order
	clientState.uiState = .FREE
	selectedUnit = nil
}

drawOrders :: proc(orders: OrderSet) {
	for unitId, order in orders {
		if selectedUnit != nil && selectedUnit.id == unitId && clientState.uiState != .FREE do continue
		unit, ok := findUnitById(clientState.game.players[clientState.myPix].units[:], unitId)
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
					.12, rl.RED, 1.5
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
	windowSize := ui.windowSizeF()
	origin := rl.Vector2 {
		windowSize.x * .5,
		windowSize.y - buttonSize * 1.5
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
			rl.BLACK,
			rl.WHITE
		},
		row
	)
}


@(private="file")
drawBuildUnitsControl :: proc() {
	buttonSize := f32(32.0)
	windowSize := ui.windowSizeF()
	origin := rl.Vector2 {
		windowSize.x * .5,
		windowSize.y - buttonSize * 1.5
	}

	for &button, index in BUTTON_ROW_BLD {
		button.disabled = index == int(selectedBuildingUnit)
	}

	ui.buttonRow(
		origin,
		buttonSize,
		{
			rl.BLACK,
			rl.WHITE
		},
		BUTTON_ROW_BLD[:],
		rl.RED
	)
}

fragCaptionCache: map[int]cstring
getFragLine :: proc(xfactor: int) -> cstring{
	cached, found := fragCaptionCache[xfactor]
	if (found) do return cached

	caption := strings.clone_to_cstring(xfactor == 1 ? "TARGET DESTROYED" : fmt.aprintf("x%d TARGET DESTROYED", xfactor))
	fragCaptionCache[xfactor] = caption
	return caption
}
drawFragList :: proc() {
	if clientState.fragCounterTTS > 0 {
		clientState.fragCounterTTS -= rl.GetFrameTime()
		if clientState.fragCounterTTS <= 0 {
			clientState.fragCounterTTS = 0
			clientState.fragCounter = 0
		}
	}
	if clientState.fragCounter == 0 do return

	for i in 0..<clientState.fragCounter {
		if i > 5 do break

		xfactor := clientState.fragCounter - i

		alphaTTSFactor := clientState.fragCounterTTS > 0 ? clientState.fragCounterTTS / FRAG_COUNTER_DISAPPEAR_S : f32(1)
		alpha := clamp(f32(5 - i) / 5, 0, 1) * alphaTTSFactor;
		color := rl.Color { 0, 0, 0, u8(math.round(255 * alpha)) }

		padding := UI_CORNER_PAD + { 0, 0 + FONT_SIZE * (f32(i) + 1) }
		rl.DrawTextEx(
			vcrFont,
			getFragLine(xfactor),
			{ padding.x, f32(ui.windowSize.y) - padding.y},
			FONT_SIZE, FONT_SPACING, color
		)
	}
}

drawTurnControl :: proc() {
	buttonSize := f32(32.0)
	orgn := rl.Vector2 {
		ui.windowSizeF().x - buttonSize * 2.5,
		buttonSize * 1.5
	}

	ui.button(
		orgn,
		buttonSize,
		ui.UI_TEXT_SUB,
		{
			rl.BLACK,
			rl.WHITE
		},
		proc() {
			postponeGenericAction(clientSayOrders)
		},
		.ENTER,
		progressShader=&progressShader
	)
	if selectedUnit != nil {
		ui.button(
			orgn + (hex.BASIS_Y * 2 * buttonSize),
			buttonSize,
			ui.UI_TEXT_ABT,
			{
				rl.BLACK,
				rl.WHITE
			},
			proc() {
				postponeGenericAction(proc() {
					selectedUnit = nil
					clientState.uiState = .FREE
				})
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
