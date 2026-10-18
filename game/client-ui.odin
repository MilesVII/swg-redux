package game

import rl "vendor:raylib"

import "core:math"
import "core:fmt"
import "core:strings"

import "ui"
import "utils"
import "hex"

NO_SELECTION :: -1

// id of one of your units; look it up every time, the state it points into gets replaced
@(private)
selectedUnitId := NO_SELECTION

@(private)
getSelectedUnit :: proc() -> ^GameUnit {
	if selectedUnitId == NO_SELECTION do return nil
	if clientState.myPix < 0 || clientState.myPix >= len(clientState.game.players) do return nil
	unit, found := findUnitById(clientState.game.players[clientState.myPix].units[:], selectedUnitId)
	return found ? unit : nil
}
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
			delete_key(&clientState.orders, selectedUnitId)
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

// renderer-neutral marks on the map, rebuilt every frame by clientPlanFrame
// and drawn by whichever view is active
OverlayCell :: struct {
	at: hex.Axial,
	thickness: f32,
	color: rl.Color
}
// outline around a set of cells
OverlayArea :: struct {
	cells: []hex.Axial,
	color: rl.Color
}
OverlayPath :: struct {
	path: hex.Path,
	color: rl.Color
}
OverlayShot :: struct {
	from: hex.Axial,
	to: hex.Axial,
	color: rl.Color,
	indirekt: bool
}
// a unit that will be built there
OverlayGhost :: struct {
	at: hex.Axial,
	type: GameUnitType,
	color: rl.Color
}
OverlayCommand :: union {
	OverlayCell,
	OverlayArea,
	OverlayPath,
	OverlayShot,
	OverlayGhost
}

@(private)
overlays: [dynamic]OverlayCommand
// cell under the cursor, if orders can be placed
@(private)
hoverCell: Maybe(hex.Axial)

@(private="file")
overlay :: proc(command: OverlayCommand) {
	append(&overlays, command)
}

// selection, order previews and their clicks; runs before drawing
// `inputBlocked` is set when the cursor is over a panel
@(private)
clientPlanFrame :: proc(inputBlocked: bool) {
	overlays = make([dynamic]OverlayCommand, context.temp_allocator)
	hoverCell = nil
	if clientState.uiState != .DISABLED && !inputBlocked do hoverCell = ui.pointedCell

	if clientState.status != .PLAYING {
		selectedUnitId = NO_SELECTION
		return
	}

	if clientState.uiState == .FREE && !inputBlocked && clientState.myPix < len(clientState.game.players) {
		for unit in clientState.game.players[clientState.myPix].units {
			if unit.position != ui.pointedCell do continue
			utils.setCursorHover(true)
			if selectedUnitId != unit.id && rl.IsMouseButtonPressed(.LEFT) {
				postponeClick(SelectAction(unit.id))
			}
		}
	}

	planOrders(clientState.orders)
	if getSelectedUnit() != nil do planOrderPreview(inputBlocked)
}

@(private="file")
planOrderPreview :: proc(inputBlocked: bool) {
	selectedUnit := getSelectedUnit()
	pointed := ui.pointedCell
	clicked := !inputBlocked && rl.IsMouseButtonPressed(.LEFT)
	gridRadius := clientState.game.grid.radius
	onGrid := hex.isWithinGrid(pointed, gridRadius)
	pointedCell: hex.GridCell
	if onGrid do pointedCell = clientState.game.grid.cells[hex.axialToIndex(pointed, gridRadius)].value

	switch clientState.uiState {
		case .DISABLED:
		case .FREE:
		case .ORDER_BLD:
			buildingAllowed :=
				hex.distance(selectedUnit.position, pointed) == 1 &&
				onGrid &&
				pointedCell.walkable &&
				noOrdersAt(pointed, clientState.orders) &&
				noUnitsAt(pointed, clientState.game.players[:])

			if buildingAllowed {
				utils.setCursorHover(true)
				overlay(OverlayCell { pointed, .2, rl.YELLOW })
				overlay(OverlayGhost { pointed, selectedBuildingUnit, myColor() })

				if clicked {
					postponeClick(OrderAction {
						unitId = selectedUnit.id,
						order = {
							target = pointed,
							targetUnitType = selectedBuildingUnit,
							type = .BUILD
						}
					})
				}
			}
		case .ORDER_MOV:
			allowedCells := hex.findWalkableOutline(
				clientState.game.grid,
				selectedUnit.position,
				MOVING[selectedUnit.type],
				context.temp_allocator
			)
			overlay(OverlayArea { allowedCells, rl.WHITE })
			movingAllowed :=
				pointed != selectedUnit.position &&
				utils.includes(allowedCells, &pointed) &&
				noOrdersAt(pointed, clientState.orders) &&
				noUnitsAt(pointed, clientState.game.players[:])

			if movingAllowed {
				utils.setCursorHover(true)
				path, _ := hex.findPath(clientState.game.grid, selectedUnit.position, pointed, context.temp_allocator)
				overlay(OverlayPath { path, rl.BLUE })
				overlay(OverlayCell { pointed, .2, rl.BLUE })

				if clicked {
					postponeClick(OrderAction {
						unitId = selectedUnit.id,
						order = {
							target = pointed,
							type = .MOVE
						}
					})
				}
			}
		case .ORDER_DIG:
			diggingAllowed :=
				hex.distance(selectedUnit.position, pointed) == 1 &&
				onGrid &&
				pointedCell.gold > 0 &&
				noOrdersAt(pointed, clientState.orders)

			if diggingAllowed {
				utils.setCursorHover(true)
				overlay(OverlayCell { pointed, .2, rl.GOLD })

				if clicked {
					postponeClick(OrderAction {
						unitId = selectedUnit.id,
						order = {
							target = pointed,
							type = .DIG
						}
					})
				}
			}
		case .ORDER_ATK:
			attackAllowed :=
				hex.distance(selectedUnit.position, pointed) <= ARANGE[selectedUnit.type]

			if selectedUnit.type == .TONK {
				attackAllowed &&=
					hex.isVisible(clientState.game.grid, selectedUnit.position, pointed)
			}

			if attackAllowed {
				indirekt := selectedUnit.type != .TONK
				planShot(selectedUnit.position, pointed, indirekt)

				if clicked {
					postponeClick(OrderAction {
						unitId = selectedUnit.id,
						order = {
							target = pointed,
							type = indirekt ? .INDIREKT : .DIREKT
						}
					})
				}
			}
	}
}

@(private="file")
planShot :: proc(from: hex.Axial, to: hex.Axial, indirekt: bool) {
	overlay(OverlayShot { from, to, rl.RED, indirekt })
	if indirekt {
		area := hex.nbs(to)
		cells := make([]hex.Axial, len(area), context.temp_allocator)
		copy(cells, area[:])
		overlay(OverlayArea { cells, rl.RED })
	} else {
		overlay(OverlayCell { to, .2, rl.RED })
	}
}

@(private)
myColor :: proc() -> rl.Color {
	if clientState.myPix < 0 || clientState.myPix >= len(clientState.game.players) do return rl.WHITE
	return clientState.game.players[clientState.myPix].color
}

@(private)
clientDrawHUD :: proc() {
	nameStatus :: proc() -> (cstring) {
		badge := clientState.activePlayerName
		if badge == NAME_PLACEHOLDER {
			return "WAITING FOR OTHER PLAYERS"
		} else {
			return fmt.ctprintf("PLAYER %s IS MAKING ORDERS", badge)
		}
	}
	finishStatus :: proc() -> cstring {
		if len(clientState.winnerName) == 0 do return "GAME OVER, NOBODY SURVIVED"
		myBadge := utils.badgeToString(utils.stringToBadge(clientState.name), context.temp_allocator)
		if clientState.winnerName == myBadge do return "GAME OVER, YOU WON"
		return fmt.ctprintf("GAME OVER, PLAYER %s WON", clientState.winnerName)
	}
	getStatusString :: proc() -> (cstring, rl.Color) {
		switch clientState.status {
			case .CONNECTING_L: return "CONNECTING TO LOBBY", rl.WHITE
			case .LOBBY:        return "", rl.WHITE
			case .CONNECTING:   return "CONNECTING TO GAME SERVER", rl.WHITE
			case .NOT_FULL:     return "WAITING FOR PLAYERS TO JOIN", rl.WHITE
			case .RESOLVING:    return "EXECUTING ORDERS", rl.WHITE
			case .PLAYING:      return "YOUR TURN", rl.RED
			case .WAITING:      return nameStatus(), rl.WHITE
			case .FINISH:       return finishStatus(), rl.WHITE
			case .DISCONNECTED: return "DISCONNECTED", rl.RED
		}
		return "", rl.WHITE
	}

	if activeView.hud != nil do activeView.hud()

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
	if len(clientState.notice) > 0 {
		rl.DrawTextEx(
			vcrFont,
			strings.clone_to_cstring(clientState.notice, context.temp_allocator),
			UI_CORNER_PAD + { 0, (UI_SPACING + FONT_SIZE) * 2 },
			FONT_SIZE, FONT_SPACING, rl.YELLOW
		)
	}

	if clientState.status == .LOBBY {
		drawMenu()
	}

	drawFragList()
	drawSettingsPanel()

	if clientState.status != .PLAYING do return

	if getSelectedUnit() != nil {
		#partial switch clientState.uiState {
			case .FREE:      drawOrdersControl()
			case .ORDER_BLD: drawBuildUnitsControl()
		}
	}

	drawTurnControl()
}

createOrder :: proc(unitId: int, order: Order) {
	rl.PlaySound(placeSound)
	clientState.orders[unitId] = order
	clientState.uiState = .FREE
	selectedUnitId = NO_SELECTION
}

@(private="file")
planOrders :: proc(orders: OrderSet) {
	for unitId, order in orders {
		if selectedUnitId == unitId && clientState.uiState != .FREE do continue
		unit, ok := findUnitById(clientState.game.players[clientState.myPix].units[:], unitId)
		if !ok do continue

		switch order.type {
			case .BUILD:
				overlay(OverlayCell { order.target, .2, rl.DARKGRAY })
				overlay(OverlayGhost { order.target, order.targetUnitType, myColor() })
			case .DIG:
				overlay(OverlayCell { order.target, .2, rl.GOLD })
			case .DIREKT:
				planShot(unit.position, order.target, false)
			case .INDIREKT:
				planShot(unit.position, order.target, true)
			case .MOVE:
				path, _ := hex.findPath(clientState.game.grid, unit.position, order.target, context.temp_allocator)
				overlay(OverlayPath { path, rl.BLUE })
				overlay(OverlayCell { order.target, .2, rl.BLUE })
		}
	}
}

@(private="file")
drawOrdersControl :: proc() {
	selectedUnit := getSelectedUnit()
	if selectedUnit == nil do return

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
		alpha := clamp(f32(5 - i) / 5, 0, 1) * alphaTTSFactor
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
	if getSelectedUnit() != nil {
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
					selectedUnitId = NO_SELECTION
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
