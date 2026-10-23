package rules_test

import "core:testing"

import "../game"
import "../game/hex"

// random maps can be too cramped for six spawns, so a few seeds are tried
createPlayableGame :: proc(players: int, teamSize: int) -> (game.GameState, bool) {
	for seed in 1..=30 {
		state, err := game.createGame(players, 8, i64(seed), teamSize)
		if err == .OK do return state, true
		game.deleteState(state)
	}
	return {}, false
}

// four players in two teams of two: 0 and 1 against 2 and 3
makeTeamState :: proc() -> game.GameState {
	state := makeState(4)
	state.teamSize = 2
	return state
}

@(test)
team_stands_while_any_member_has_an_mcv :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeTeamState()
	addUnit(&state, 0, 1, .TONK, { 0, 0 }, 2)
	addUnit(&state, 1, 1, .MCV, { 1, 0 })
	addUnit(&state, 2, 1, .MCV, { -2, 0 })
	addUnit(&state, 3, 1, .GUN, { -3, 0 })

	testing.expect(t, !game.gameOver(&state), "two teams with an MCV each keep playing")

	clear(&state.players[1].units)
	testing.expect(t, game.gameOver(&state), "a team without MCVs has lost")
	standing := game.teamsStanding(&state)
	testing.expect_value(t, len(standing), 1)
	if len(standing) == 1 do testing.expect_value(t, standing[0], 1)
}

@(test)
free_for_all_still_counts_players :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeState(3)
	addUnit(&state, 0, 1, .MCV, { 0, 0 })
	addUnit(&state, 1, 1, .MCV, { 2, 0 })
	addUnit(&state, 2, 1, .TONK, { -2, 0 }, 2)
	testing.expect(t, !game.gameOver(&state), "two players with MCVs keep playing")
	clear(&state.players[1].units)
	testing.expect(t, game.gameOver(&state), "one player left wins")
}

@(test)
teammates_share_vision :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeTeamState()
	// player 0 sits far from everything, player 1 next to an enemy
	addUnit(&state, 0, 1, .MCV, { -4, 0 })
	addUnit(&state, 1, 1, .MCV, { 2, 0 })
	addUnit(&state, 2, 1, .TONK, { 3, 0 }, 2)

	seen := game.getStateForPlayer(&state, 0)
	testing.expect_value(t, len(seen.players[1].units), 1)
	if len(seen.players[1].units) == 1 do testing.expect(t, !seen.players[1].units[0].hidden, "a teammate is never hidden")
	testing.expect_value(t, len(seen.players[2].units), 1)
	if len(seen.players[2].units) == 1 do testing.expect(t, !seen.players[2].units[0].hidden, "the enemy next to the teammate is in sight")
	cell := seen.grid.cells[hex.axialToIndex({ 3, 0 }, RADIUS)].value
	testing.expect(t, cell.fog == .OBSERVED, "terrain around the teammate is observed")
	game.deleteState(seen)
}

@(test)
enemies_dont_share_vision :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeTeamState()
	addUnit(&state, 0, 1, .MCV, { -4, 0 })
	addUnit(&state, 2, 1, .MCV, { 2, 0 })
	addUnit(&state, 3, 1, .TONK, { 3, 0 }, 2)

	seen := game.getStateForPlayer(&state, 0)
	testing.expect_value(t, len(seen.players[2].units), 0)
	testing.expect_value(t, len(seen.players[3].units), 0)
	game.deleteState(seen)
}

@(test)
teammate_shells_dont_point_at_their_gun :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeTeamState()
	addUnit(&state, 0, 1, .MCV, { 0, 0 })
	explosions := []game.ExplosionBufferEntry {
		{ position = { 1, 0 }, pix = 1, side = 3 },
		{ position = { 0, 1 }, pix = 2, side = 3 },
	}
	seen := game.getStateForPlayer(&state, 0)
	visible := game.reduceExplosionsToVisible(&seen, 0, explosions)
	testing.expect_value(t, len(visible), 2)
	for bonk in visible {
		if bonk.position == ({ 1, 0 }) do testing.expect_value(t, bonk.side, -1)
		if bonk.position == ({ 0, 1 }) do testing.expect_value(t, bonk.side, 3)
	}
	game.deleteState(seen)
}

@(test)
teams_spawn_together :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	setups := [][2]int { { 4, 2 }, { 6, 2 }, { 6, 3 } }
	for setup in setups {
		players, teamSize := setup[0], setup[1]
		state, ok := createPlayableGame(players, teamSize)
		testing.expect(t, ok, "found a map with room for six spawns")
		if !ok do continue

		// every corner is taken with six players, so enemy teams end up next to each other too;
		// what matters is that nobody's nearest neighbor is an enemy
		for a in 0..<players {
			nearestTeammate, nearestEnemy := max(int), max(int)
			for b in 0..<players {
				if a == b do continue
				d := hex.distance(state.players[a].units[0].position, state.players[b].units[0].position)
				if game.sameTeam(&state, a, b) do nearestTeammate = min(nearestTeammate, d)
				else do nearestEnemy = min(nearestEnemy, d)
			}
			// spawns drift inward from the corners by a tile or two, so this is only a coarse check
			testing.expectf(t, nearestTeammate <= nearestEnemy + 2, "%d players in teams of %d: player %d has a teammate %d away but an enemy %d away", players, teamSize, a, nearestTeammate, nearestEnemy)
		}
	}
}

@(test)
free_for_all_spawns_spread_out :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state, ok := createPlayableGame(2, 1)
	testing.expect(t, ok, "found a map with room for six spawns")
	if !ok do return
	d := hex.distance(state.players[0].units[0].position, state.players[1].units[0].position)
	// opposite corners, with spawns drifting inward by a tile or two; adjacent corners are about 7 apart
	testing.expectf(t, d >= 9, "two players sit %d apart", d)
}

// the corner layout itself: each team gets consecutive corners, teams never share one
@(test)
team_corners_are_consecutive :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	setups := [][2]int { { 4, 2 }, { 6, 2 }, { 6, 3 } }
	for setup in setups {
		players, teamSize := setup[0], setup[1]
		slots := game.spawnSlots(players, teamSize)
		taken: [6]bool
		for slot in slots {
			testing.expect(t, !taken[slot], "corners aren't shared")
			taken[slot] = true
		}
		for team in 0..<players / teamSize {
			for member in 1..<teamSize {
				a := slots[team * teamSize + member - 1]
				b := slots[team * teamSize + member]
				testing.expectf(t, (a + 1) % 6 == b, "%d players in teams of %d: team %d sits on consecutive corners", players, teamSize, team)
			}
		}
	}
	// free for all keeps players apart: two players on opposite corners
	pair := game.spawnSlots(2, 1)
	testing.expect_value(t, (pair[0] + 3) % 6, pair[1])
}
