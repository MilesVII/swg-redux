package rules_test

import "core:testing"

import "../game"
import "../game/hex"

@(test)
guns_run_out_of_shells :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeState(1)
	addUnit(&state, 0, 1, .GUN, { 0, 0 }, 1)
	orders := make(game.OrderSet)
	orders[1] = queue({ type = .INDIREKT, target = { 3, 0 } })
	explosions: [dynamic]game.ExplosionBufferEntry

	game.executeOrders(&state, 0, orders, &explosions, 7)

	testing.expect_value(t, len(explosions), game.INDIREKT_BARRAGE_SIZE)
	testing.expect_value(t, len(state.players[0].units), 0)
}

@(test)
built_guns_carry_shells :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeState(1)
	addUnit(&state, 0, 1, .MCV, { 0, 0 }, 1)
	orders := make(game.OrderSet)
	orders[1] = queue({ type = .BUILD, target = { 1, 0 }, targetUnitType = .GUN })
	explosions: [dynamic]game.ExplosionBufferEntry
	game.executeOrders(&state, 0, orders, &explosions, 7)

	gun, found := game.findUnitById(state.players[0].units[:], 100)
	testing.expect(t, found, "the gun was built")
	if found do testing.expect_value(t, gun.gold, game.GUN_SHELLS)
	empty := game.GameUnit { id = 5, type = .GUN, position = { 0, 0 }, gold = 0 }
	testing.expect(t, !game.orderAllowed(&state, empty, { type = .INDIREKT, target = { 3, 0 } }), "an empty gun can't fire")
}

@(test)
same_seed_same_scatter :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	orders := make(game.OrderSet)
	orders[1] = queue({ type = .INDIREKT, target = { 3, 0 } })

	run :: proc(seed: u64, orders: game.OrderSet) -> [dynamic]game.ExplosionBufferEntry {
		state := makeState(1)
		addUnit(&state, 0, 1, .GUN, { 0, 0 }, 8)
		explosions: [dynamic]game.ExplosionBufferEntry
		game.executeOrders(&state, 0, orders, &explosions, seed)
		return explosions
	}
	a := run(42, orders)
	b := run(42, orders)
	testing.expect_value(t, len(a), len(b))
	for bonk, i in a do testing.expect_value(t, bonk.position, b[i].position)
}

@(test)
replay_rebuilds_the_same_game :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	live, ok := createPlayableGame(2, 1)
	testing.expect(t, ok, "found a playable map")
	if !ok do return
	seed := game.replaySeedOf(live)

	// a few turns: the first player builds and moves, the second shells the first
	turns := make([dynamic]game.ReplayTurn)
	explosions: [dynamic]game.ExplosionBufferEntry
	for i in 0..<6 {
		player := i % 2
		orders := make(game.OrderSet)
		units := live.players[player].units
		for unit in units {
			switch unit.type {
				case .MCV:
					for nb in hex.AXIAL_NBS {
						c := unit.position + nb
						if hex.cellIsWalkable(c, live.grid) && game.noUnitsAt(c, live.players) {
							orders[unit.id] = queue({ type = .BUILD, target = c, targetUnitType = .GUN })
							break
						}
					}
				case .GUN:
					target := live.players[1 - player].units[0].position
					orders[unit.id] = queue({ type = .INDIREKT, target = target })
				case .TONK, .REC:
			}
		}
		turn := game.ReplayTurn { player = player, seed = u64(1000 + i), orders = orders }
		append(&turns, turn)
		clear(&explosions)
		game.applyReplayTurn(&live, turn, &explosions)
	}

	replay := game.Replay {
		version = game.REPLAY_VERSION,
		radius = live.grid.radius,
		playerCount = 2,
		teamSize = 1,
		seed = seed,
		names = { "alpha", "beta" },
		turns = turns[:]
	}
	rebuilt, rebuiltOk := game.rebuildReplayGame(replay, len(turns))
	testing.expect(t, rebuiltOk, "the replay rebuilds")
	if !rebuiltOk do return

	for player, pix in live.players {
		testing.expect_value(t, len(rebuilt.players[pix].units), len(player.units))
		for unit, i in player.units {
			if i >= len(rebuilt.players[pix].units) do break
			other := rebuilt.players[pix].units[i]
			testing.expect_value(t, other.id, unit.id)
			testing.expect_value(t, other.position, unit.position)
			testing.expect_value(t, other.gold, unit.gold)
		}
	}
	for cell, i in live.grid.cells {
		if cell.value.scrap != rebuilt.grid.cells[i].value.scrap || cell.value.gold != rebuilt.grid.cells[i].value.gold {
			testing.expect(t, false, "the map differs after the replay")
			break
		}
	}
}
