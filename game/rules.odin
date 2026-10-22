package game

import "core:slice"

import "hex"
import "utils"

// game rules on any state, so the server and tests share them

// orders run in unit id order so results don't depend on map iteration order
// units built during this turn can't act until the next one
executeOrders :: proc(state: ^GameState, playerIx: int, orders: OrderSet, explosions: ^[dynamic]ExplosionBufferEntry) {
	idLimit := state.players[playerIx].unitIdCounter

	unitIds := make([dynamic]int, 0, len(orders), context.temp_allocator)
	for unitId in orders do if unitId < idLimit do append(&unitIds, unitId)
	slice.sort(unitIds[:])

	for unitId in unitIds {
		list := orders[unitId]
		queued := listedOrders(&list)
		unit, found := findUnitById(state.players[playerIx].units[:], unitId)
		if !found do continue
		// only MCVs may queue, and only builds or only digs; anything else runs its first order
		if len(queued) > 1 && !multipleOrdersAllowed(unit.type, queued) do queued = queued[:1]
		for order in queued do executeOrder(state, playerIx, unitId, order, explosions)
	}
}

executeOrder :: proc(state: ^GameState, playerIx: int, unitId: int, order: Order, explosions: ^[dynamic]ExplosionBufferEntry) {
	unit, ok := findUnitById(state.players[playerIx].units[:], unitId)
	if !ok do return
	if !orderAllowed(state, unit^, order) {
		utils.log("rejected order ", order, " for unit ", unitId)
		return
	}

	switch order.type {
		case .BUILD:
			unit.gold -= 1

			newUnit := GameUnit {
				position = order.target,
				type = order.targetUnitType,
				id = state.players[playerIx].unitIdCounter,
				gold = order.targetUnitType == .TONK ? 2 : 0
			}
			// invalidates `unit`
			append(&state.players[playerIx].units, newUnit)
			state.players[playerIx].unitIdCounter += 1
		case .DIG:
			cell := &state.grid.cells[hex.axialToIndex(order.target, state.grid.radius)].value
			// scrap is worth one gold and goes away with it
			if cell.scrap do cell.scrap = false
			else do cell.gold -= 1
			unit.gold += 1
		case .DIREKT:
			append(explosions, ExplosionBufferEntry {
				position = order.target,
				pix = playerIx,
				side = -1
			})
		case .INDIREKT:
			utils.shuffle(BONK_OFFSETS[:])

			for i in 0..<INDIREKT_BARRAGE_SIZE {
				at := order.target + BONK_OFFSETS[i]
				append(explosions, ExplosionBufferEntry {
					position = at,
					pix = playerIx,
					// the tile side the shell came from, all the target gets to know about the gun
					side = hex.sideTowards(at, unit.position)
				})
			}
		case .MOVE:
			unit.position = order.target
	}
}

// the orders of a list that still hold on this state, in order; queued builds and digs
// also have to fit the unit's gold one after another
validOrders :: proc(state: ^GameState, playerIx: int, unitId: int, list: OrderList) -> (kept: OrderList, dropped: int) {
	list := list
	unit, found := findUnitById(state.players[playerIx].units[:], unitId)
	if !found do return {}, list.count
	// gold as it would be once the kept orders ran
	projected := unit^
	for order in listedOrders(&list) {
		if !orderAllowed(state, projected, order) || kept.count >= MAX_UNIT_ORDERS {
			dropped += 1
			continue
		}
		kept.items[kept.count] = order
		kept.count += 1
		#partial switch order.type {
			case .BUILD: projected.gold -= 1
			case .DIG: projected.gold += 1
		}
	}
	return kept, dropped
}

// mirrors the checks the client does before placing an order
orderAllowed :: proc(state: ^GameState, unit: GameUnit, order: Order) -> bool {
	grid := state.grid
	target := order.target
	onGrid := hex.isWithinGrid(target, grid.radius)
	distance := hex.distance(unit.position, target)

	switch order.type {
		case .BUILD:
			validType := order.targetUnitType >= min(GameUnitType) && order.targetUnitType <= max(GameUnitType)
			return validType &&
				unit.type == .MCV &&
				unit.gold > 0 &&
				distance == 1 &&
				// walkable and free of scrap
				hex.cellIsWalkable(target, grid) &&
				noUnitsAt(target, state.players)
		case .DIG:
			if unit.type != .MCV || unit.gold >= 3 || distance != 1 || !onGrid do return false
			cell := grid.cells[hex.axialToIndex(target, grid.radius)].value
			return cell.gold > 0 || cell.scrap
		case .DIREKT:
			return unit.type == .TONK &&
				distance <= ARANGE[.TONK] &&
				hex.isVisible(grid, unit.position, target)
		case .INDIREKT:
			return unit.type == .GUN &&
				distance <= ARANGE[.GUN]
		case .MOVE:
			if MOVING[unit.type] == 0 || target == unit.position do return false
			if !noUnitsAt(target, state.players) do return false
			allowedCells := hex.findWalkableOutline(grid, unit.position, MOVING[unit.type], context.temp_allocator)
			return utils.includes(allowedCells, &target)
	}
	return false
}

// applies hits: scrap is destroyed, TONKs lose a hit point, anything else is destroyed;
// MCVs carrying gold leave scrap behind
bonkUnits :: proc(state: ^GameState, explosions: []ExplosionBufferEntry) {
	for &bonk in explosions {
		if !hex.isWithinGrid(bonk.position, state.grid.radius) do continue
		cell := &state.grid.cells[hex.axialToIndex(bonk.position, state.grid.radius)].value

		// scrap blocks its tile, so there's no unit under it
		if cell.scrap {
			cell.scrap = false
			continue
		}

		uix, pix, found := findUnitAt(state, bonk.position)
		if !found do continue
		unit := &state.players[pix].units[uix]

		if unit.type == .TONK && unit.gold > 1 do unit.gold -= 1
		else {
			leavesScrap := unit.type == .MCV && unit.gold >= 1
			unordered_remove(&state.players[pix].units, uix)
			bonk.lethal = true
			if leavesScrap do cell.scrap = true
		}
	}
}

// the last team standing wins, a team stands while any member has an MCV
gameOver :: proc(state: ^GameState) -> bool {
	return len(teamsStanding(state, context.temp_allocator)) <= 1
}

teamsStanding :: proc(state: ^GameState, allocator := context.allocator) -> []int {
	standing := make([dynamic]int, allocator)
	for _, pix in state.players {
		if !activeUnitsLeft(state, pix) do continue
		team := teamOf(state, pix)
		if !slice.contains(standing[:], team) do append(&standing, team)
	}
	return standing[:]
}

activeUnitsLeft :: proc(state: ^GameState, playerIx: int) -> bool {
	for unit in state.players[playerIx].units {
		if unit.type == .MCV do return true
	}
	return false
}
