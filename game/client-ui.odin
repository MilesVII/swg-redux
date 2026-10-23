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
			// all of the unit's orders
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
	},
	.REC = {
		BUTTON_CLR,
		BUTTON_MOV
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
	},
	{
		action = proc() {
			postponeGenericAction(proc() {
				selectedBuildingUnit = .REC
			})
		},
		caption = &ui.UI_TEXT_REC
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
// dashed border of the cells within `radius` of a unit: its vision or its attack reach
OverlayRing :: struct {
	center: hex.Axial,
	radius: int,
	color: rl.Color
}
OverlayCommand :: union {
	OverlayCell,
	OverlayArea,
	OverlayPath,
	OverlayShot,
	OverlayGhost,
	OverlayRing
}

VISION_RING_COLOR :: rl.Color { 90, 170, 255, 255 }
ATTACK_RING_COLOR :: rl.Color { 255, 70, 50, 255 }
// where along each border edge its two dashes run, leaving gaps at the corners and in the middle
RING_DASHES :: [2][2]f32 { { .06, .44 }, { .56, .94 } }

// vision and attack rings of a unit of `type` standing at `at`
@(private="file")
planUnitRanges :: proc(at: hex.Axial, type: GameUnitType, vision := true, attack := true) {
	if vision && VISION[type] > 0 do overlay(OverlayRing { at, VISION[type], VISION_RING_COLOR })
	if attack && ARANGE[type] > 0 do overlay(OverlayRing { at, ARANGE[type], ATTACK_RING_COLOR })
}

// ranges of whatever unit is under the cursor, enemies and remembered guns included
@(private="file")
planHoveredUnitRanges :: proc() {
	for player in clientState.game.players {
		for unit in player.units {
			if unit.position == ui.pointedCell do planUnitRanges(unit.position, unit.type)
		}
	}
}

@(private)
overlays: [dynamic]OverlayCommand
@(private="file")
rightPressPosition: rl.Vector2
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

	// hovering shows ranges whenever there's a map, placing an order shows the one range that matters
	if showsGame() && !inputBlocked && (clientState.uiState == .DISABLED || clientState.uiState == .FREE) do planHoveredUnitRanges()

	if !canPlanOrders() {
		selectedUnitId = NO_SELECTION
		return
	}
	// the unit being ordered was destroyed meanwhile
	if getSelectedUnit() == nil && clientState.uiState != .FREE do clientState.uiState = .FREE

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

	// a right click aborts like the ABORT button, a right drag is left to the camera
	if rl.IsMouseButtonPressed(.RIGHT) do rightPressPosition = rl.GetMousePosition()
	if rl.IsMouseButtonReleased(.RIGHT) && getSelectedUnit() != nil {
		if rl.Vector2Distance(rl.GetMousePosition(), rightPressPosition) < 6 do postponeGenericAction(abortOrderPlacement)
	}
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
				!pointedCell.scrap &&
				noOrdersAt(pointed, clientState.orders) &&
				noUnitsAt(pointed, clientState.game.players[:])

			if buildingAllowed {
				utils.setCursorHover(true)
				overlay(OverlayCell { pointed, .2, rl.YELLOW })
				overlay(OverlayGhost { pointed, selectedBuildingUnit, myColor() })
				planUnitRanges(pointed, selectedBuildingUnit)

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
				// what the unit would see from there
				planUnitRanges(pointed, selectedUnit.type, attack = false)
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
				(pointedCell.gold > 0 || pointedCell.scrap) &&
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
			planUnitRanges(selectedUnit.position, selectedUnit.type, vision = false)
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
		teams := clientState.game.teamSize > 1
		if clientState.winnerTeam == teamOf(&clientState.game, clientState.myPix) {
			return teams ? "GAME OVER, YOUR TEAM WON" : "GAME OVER, YOU WON"
		}
		return fmt.ctprintf(teams ? "GAME OVER, TEAM %s WON" : "GAME OVER, PLAYER %s WON", clientState.winnerName)
	}
	getStatusString :: proc() -> (cstring, rl.Color) {
		switch clientState.status {
			case .NAMING:       return "", rl.WHITE
			case .CONNECTING_L: return "CONNECTING TO LOBBY", rl.WHITE
			case .LOBBY:        return "", rl.WHITE
			case .CONNECTING:   return "CONNECTING TO GAME SERVER", rl.WHITE
			case .NOT_FULL:     return "WAITING FOR PLAYERS TO JOIN", rl.WHITE
			case .TEAMS:        return "", rl.WHITE
			case .RESOLVING:    return "EXECUTING ORDERS", rl.WHITE
			case .PLAYING:      return "YOUR TURN", rl.RED
			case .WAITING:      return nameStatus(), rl.WHITE
			case .LOST:         return fmt.ctprintf("YOU ARE OUT, %s", nameStatus()), rl.RED
			case .FINISH:       return finishStatus(), rl.WHITE
			case .DISCONNECTED: return clientState.dialTicket != 0 ? "RECONNECTING" : "DISCONNECTED", rl.RED
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
	drawTurnTimer(rl.MeasureTextEx(vcrFont, status, FONT_SIZE, FONT_SPACING).x)
	framerate := math.round(1.0 / rl.GetFrameTime())
	rl.DrawTextEx(
		vcrFont,
		fmt.ctprint(framerate),
		UI_CORNER_PAD + { 0, UI_SPACING + FONT_SIZE },
		FONT_SIZE, FONT_SPACING, rl.RED
	)
	hintRow := f32(2)
	if len(clientState.notice) > 0 {
		rl.DrawTextEx(
			vcrFont,
			strings.clone_to_cstring(clientState.notice, context.temp_allocator),
			UI_CORNER_PAD + { 0, (UI_SPACING + FONT_SIZE) * 2 },
			FONT_SIZE, FONT_SPACING, rl.YELLOW
		)
		hintRow += 1
	}
	if clientState.status == .FINISH && canLeaveToLobby() {
		rl.DrawTextEx(
			vcrFont,
			"ESC TO RETURN TO LOBBY",
			UI_CORNER_PAD + { 0, (UI_SPACING + FONT_SIZE) * hintRow },
			FONT_SIZE, FONT_SPACING, rl.WHITE
		)
	}

	if clientState.status == .NAMING do drawNamePrompt()
	if clientState.status == .LOBBY {
		drawMenu()
	}

	drawFragList()
	drawSettingsPanel()

	if clientState.leavePrompt {
		drawLeavePrompt()
		return
	}
	if clientState.status == .TEAMS do drawTeamPicker()
	else do resetTeamPicker()
	if !canPlanOrders() do return

	if getSelectedUnit() != nil {
		#partial switch clientState.uiState {
			case .FREE:      drawOrdersControl()
			case .ORDER_BLD: drawBuildUnitsControl()
		}
	}

	drawTurnControl()
}

// a second build or dig of an MCV joins the first one, anything else replaces the unit's orders
createOrder :: proc(unitId: int, order: Order) {
	rl.PlaySound(placeSound)
	clientState.uiState = .FREE

	unit, found := findUnitById(clientState.game.players[clientState.myPix].units[:], unitId)
	list := clientState.orders[unitId]
	if found && canQueueOrder(unit.type, list, order) {
		list.items[list.count] = order
		list.count += 1
	} else {
		list = oneOrder(order)
	}
	clientState.orders[unitId] = list

	// stay selected while another order of the kind can still be added and paid for
	if !found || !canQueueOrder(unit.type, list, order) || !affordsAnother(unit, list, order.type) {
		selectedUnitId = NO_SELECTION
	}
}

// gold left for one more queued build, or room for one more dig
@(private="file")
affordsAnother :: proc(unit: ^GameUnit, list: OrderList, kind: OrderType) -> bool {
	queued := countOrders(list, kind)
	#partial switch kind {
		case .BUILD: return unit.gold - queued > 0
		case .DIG:   return unit.gold + queued < 3
	}
	return false
}

// the ABORT button and right clicks: stop placing and drop the selection
abortOrderPlacement :: proc() {
	selectedUnitId = NO_SELECTION
	clientState.uiState = .FREE
}

@(private="file")
planOrders :: proc(orders: OrderSet) {
	for unitId, &list in orders {
		unit, ok := findUnitById(clientState.game.players[clientState.myPix].units[:], unitId)
		if !ok do continue

		for order in listedOrders(&list) do switch order.type {
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

	orders := clientState.orders[selectedUnit.id]
	row := BUTTON_ROWS[selectedUnit.type]
	row[0].disabled = orders.count == 0

	if selectedUnit.type == .MCV {
		// another dig or build joins the queued ones, gold has to cover all of them;
		// a different kind of order replaces the queue, so only the current gold counts
		digs := countOrders(orders, .DIG)
		builds := countOrders(orders, .BUILD)
		gold := selectedUnit.gold
		row[1].disabled = digs > 0 ? (digs >= MAX_UNIT_ORDERS || gold + digs >= 3) : gold >= 3 // DIG
		row[3].disabled = builds > 0 ? (builds >= MAX_UNIT_ORDERS || gold - builds <= 0) : gold <= 0 // BUILD
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

	// orders can be prepared any time, but only go out on your turn
	if clientState.status == .PLAYING && !clientState.ordersSent do ui.button(
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
				postponeGenericAction(abortOrderPlacement)
			},
			.ESCAPE
		)
	}
}

// time left of the current turn, after the status line
@(private="file")
drawTurnTimer :: proc(statusWidth: f32) {
	if clientState.turnDeadline <= 0 do return
	if clientState.status != .PLAYING && clientState.status != .WAITING && clientState.status != .RESOLVING do return

	left := max(int(clientState.turnDeadline - rl.GetTime() + .999), 0)
	urgent := left <= 10
	// blinks in the last seconds
	if urgent && clientState.status == .PLAYING && utils.flicker > .5 do return
	rl.DrawTextEx(
		vcrFont,
		fmt.ctprintf("%d:%02d", left / 60, left % 60),
		UI_CORNER_PAD + { statusWidth + UI_SPACING * 2, 0 },
		FONT_SIZE, FONT_SPACING, urgent ? rl.RED : rl.WHITE
	)
}

noOrdersAt :: proc(at: hex.Axial, orders: OrderSet) -> bool {
	for _, &list in orders {
		for order in listedOrders(&list) {
			if order.type == .DIREKT || order.type == .INDIREKT do continue
			if order.target == at do return false
		}
	}

	return true
}
