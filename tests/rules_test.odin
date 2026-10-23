package rules_test

// game rules on small hand made maps: odin test tests

import "core:testing"
import rl "vendor:raylib"

import "../game"
import "../game/hex"

RADIUS :: 4

// open flat land everywhere, `players` players without units
makeState :: proc(players: int) -> game.GameState {
	state := game.GameState {
		grid = hex.grid(RADIUS, hex.GridCell),
		players = make([]game.PlayerState, players)
	}
	for &cell in state.grid.cells {
		cell.value = { color = rl.GREEN, walkable = true, seethrough = true, mainArea = true, fog = .FOG }
	}
	for &player in state.players {
		player.knownTerrain = make([]bool, len(state.grid.cells))
		player.unitIdCounter = 100
	}
	return state
}

addUnit :: proc(state: ^game.GameState, pix: int, id: int, type: game.GameUnitType, at: hex.Axial, gold := 0) {
	append(&state.players[pix].units, game.GameUnit { id = id, type = type, position = at, gold = gold })
}

cellAt :: proc(state: ^game.GameState, at: hex.Axial) -> ^hex.GridCell {
	return &state.grid.cells[hex.axialToIndex(at, state.grid.radius)].value
}

queue :: proc(orders: ..game.Order) -> game.OrderList {
	list: game.OrderList
	for order, i in orders do list.items[i] = order
	list.count = len(orders)
	return list
}

@(test)
mcv_builds_twice :: proc(t: ^testing.T) {
	// fixtures are thrown away with the test
	context.allocator = context.temp_allocator
	state := makeState(1)
	addUnit(&state, 0, 1, .MCV, { 0, 0 }, 2)
	orders := make(game.OrderSet)
	orders[1] = queue(
		{ type = .BUILD, target = { 1, 0 }, targetUnitType = .TONK },
		{ type = .BUILD, target = { 0, 1 }, targetUnitType = .REC },
	)
	explosions: [dynamic]game.ExplosionBufferEntry

	game.executeOrders(&state, 0, orders, &explosions, 1)

	testing.expect_value(t, len(state.players[0].units), 3)
	mcv, _ := game.findUnitById(state.players[0].units[:], 1)
	testing.expect_value(t, mcv.gold, 0)
}

@(test)
mixed_queue_runs_first_order :: proc(t: ^testing.T) {
	// fixtures are thrown away with the test
	context.allocator = context.temp_allocator
	state := makeState(1)
	addUnit(&state, 0, 1, .MCV, { 0, 0 }, 2)
	orders := make(game.OrderSet)
	orders[1] = queue(
		{ type = .BUILD, target = { 1, 0 }, targetUnitType = .TONK },
		{ type = .MOVE, target = { -2, 0 } },
	)
	explosions: [dynamic]game.ExplosionBufferEntry

	game.executeOrders(&state, 0, orders, &explosions, 1)

	mcv, _ := game.findUnitById(state.players[0].units[:], 1)
	testing.expect_value(t, len(state.players[0].units), 2)
	testing.expect_value(t, mcv.position, hex.Axial { 0, 0 })
}

@(test)
mcv_with_gold_leaves_scrap :: proc(t: ^testing.T) {
	// fixtures are thrown away with the test
	context.allocator = context.temp_allocator
	state := makeState(2)
	addUnit(&state, 0, 1, .MCV, { 0, 0 }, 1)
	addUnit(&state, 1, 1, .MCV, { 2, 0 }, 0)
	explosions := []game.ExplosionBufferEntry {
		{ position = { 0, 0 }, pix = 1, side = -1 },
		{ position = { 2, 0 }, pix = 0, side = -1 },
	}

	game.bonkUnits(&state, explosions)

	testing.expect(t, explosions[0].lethal, "the MCV was destroyed")
	testing.expect(t, cellAt(&state, { 0, 0 }).scrap, "an MCV carrying gold leaves scrap")
	testing.expect(t, !cellAt(&state, { 2, 0 }).scrap, "an empty MCV leaves nothing")
}

@(test)
scrap_blocks_its_tile :: proc(t: ^testing.T) {
	// fixtures are thrown away with the test
	context.allocator = context.temp_allocator
	state := makeState(1)
	addUnit(&state, 0, 1, .MCV, { 0, 0 }, 1)
	addUnit(&state, 0, 2, .TONK, { -2, 0 }, 2)
	cellAt(&state, { 1, 0 }).scrap = true

	testing.expect(t, !hex.cellIsWalkable({ 1, 0 }, state.grid), "scrap isn't walkable")
	tonk, _ := game.findUnitById(state.players[0].units[:], 2)
	testing.expect(t, !game.orderAllowed(&state, tonk^, { type = .MOVE, target = { 1, 0 } }), "can't move onto scrap")
	mcv, _ := game.findUnitById(state.players[0].units[:], 1)
	testing.expect(t, !game.orderAllowed(&state, mcv^, { type = .BUILD, target = { 1, 0 }, targetUnitType = .GUN }), "can't build on scrap")
}

@(test)
digging_scrap_pays_one_gold :: proc(t: ^testing.T) {
	// fixtures are thrown away with the test
	context.allocator = context.temp_allocator
	state := makeState(1)
	addUnit(&state, 0, 1, .MCV, { 0, 0 }, 1)
	cellAt(&state, { 1, 0 }).scrap = true
	orders := make(game.OrderSet)
	orders[1] = queue({ type = .DIG, target = { 1, 0 } })
	explosions: [dynamic]game.ExplosionBufferEntry

	game.executeOrders(&state, 0, orders, &explosions, 1)

	mcv, _ := game.findUnitById(state.players[0].units[:], 1)
	testing.expect_value(t, mcv.gold, 2)
	testing.expect(t, !cellAt(&state, { 1, 0 }).scrap, "dug scrap is gone")
	testing.expect_value(t, cellAt(&state, { 1, 0 }).gold, 0)
}

@(test)
hits_destroy_scrap :: proc(t: ^testing.T) {
	// fixtures are thrown away with the test
	context.allocator = context.temp_allocator
	state := makeState(1)
	cellAt(&state, { 1, 0 }).scrap = true
	explosions := []game.ExplosionBufferEntry { { position = { 1, 0 }, pix = 0, side = -1 } }

	game.bonkUnits(&state, explosions)

	testing.expect(t, !cellAt(&state, { 1, 0 }).scrap, "a hit destroys scrap")
	testing.expect(t, !explosions[0].lethal, "scrap isn't a kill")
}

@(test)
shells_tell_the_side_they_came_from :: proc(t: ^testing.T) {
	// fixtures are thrown away with the test
	context.allocator = context.temp_allocator
	state := makeState(2)
	gunAt := hex.Axial { -3, 0 }
	addUnit(&state, 0, 1, .GUN, gunAt, game.GUN_SHELLS)
	orders := make(game.OrderSet)
	orders[1] = queue({ type = .INDIREKT, target = { 3, 0 } })
	explosions: [dynamic]game.ExplosionBufferEntry

	game.executeOrders(&state, 0, orders, &explosions, 1)

	testing.expect_value(t, len(explosions), game.INDIREKT_BARRAGE_SIZE)
	for bonk in explosions {
		testing.expect(t, bonk.side >= 0 && bonk.side < 6, "every shell has a side")
		toward := hex.axialToWorld(hex.AXIAL_NBS[bonk.side])
		direction := hex.axialToWorld(gunAt) - hex.axialToWorld(bonk.position)
		testing.expect(t, rl.Vector2DotProduct(toward, direction) > 0, "the side faces the gun")
	}
}

@(test)
seen_guns_are_remembered :: proc(t: ^testing.T) {
	// fixtures are thrown away with the test
	context.allocator = context.temp_allocator
	state := makeState(2)
	addUnit(&state, 0, 1, .MCV, { 0, 0 })
	addUnit(&state, 1, 7, .GUN, { 2, 0 })

	seen := game.getStateForPlayer(&state, 0)
	testing.expect_value(t, len(seen.players[1].units), 1)
	testing.expect(t, !seen.players[1].units[0].hidden, "a gun in sight isn't hidden")
	game.deleteState(seen)

	// out of sight: still there, hidden
	state.players[0].units[0].position = { -4, 0 }
	away := game.getStateForPlayer(&state, 0)
	testing.expect_value(t, len(away.players[1].units), 1)
	if len(away.players[1].units) == 1 do testing.expect(t, away.players[1].units[0].hidden, "a remembered gun is hidden")
	game.deleteState(away)

	// destroyed out of sight: still remembered where it was
	clear(&state.players[1].units)
	destroyed := game.getStateForPlayer(&state, 0)
	testing.expect_value(t, len(destroyed.players[1].units), 1)
	if len(destroyed.players[1].units) == 1 do testing.expect_value(t, destroyed.players[1].units[0].position, hex.Axial { 2, 0 })
	game.deleteState(destroyed)

	// its tile seen empty: forgotten
	state.players[0].units[0].position = { 0, 0 }
	back := game.getStateForPlayer(&state, 0)
	testing.expect_value(t, len(back.players[1].units), 0)
	testing.expect_value(t, len(state.players[0].knownGuns), 0)
	game.deleteState(back)
}

@(test)
other_units_are_not_remembered :: proc(t: ^testing.T) {
	// fixtures are thrown away with the test
	context.allocator = context.temp_allocator
	state := makeState(2)
	addUnit(&state, 0, 1, .MCV, { 0, 0 })
	addUnit(&state, 1, 7, .TONK, { 2, 0 }, 2)

	seen := game.getStateForPlayer(&state, 0)
	testing.expect_value(t, len(seen.players[1].units), 1)
	game.deleteState(seen)

	state.players[0].units[0].position = { -4, 0 }
	away := game.getStateForPlayer(&state, 0)
	testing.expect_value(t, len(away.players[1].units), 0)
	game.deleteState(away)
}
