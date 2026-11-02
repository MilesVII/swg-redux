package rules_test

import "core:testing"

import "../game"
import "../game/hex"

// spawns and the gold each region holds, on a map that passed generation
goldByRegion :: proc(state: ^game.GameState) -> []int {
	spawns := make([]hex.Axial, len(state.players), context.temp_allocator)
	for player, i in state.players do spawns[i] = player.units[0].position
	regions := game.goldRegions(state.grid, spawns, context.temp_allocator)
	counts := make([]int, len(state.players), context.temp_allocator)
	for cell, index in state.grid.cells do if cell.value.gold > 0 && regions[index] >= 0 do counts[regions[index]] += 1
	return counts
}

@(test)
gold_is_split_evenly_between_regions :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for players in ([]int { 2, 3, 6 }) {
		state, ok := createPlayableGame(players, 1)
		testing.expect(t, ok, "found a playable map")
		if !ok do continue
		quota := game.goldQuota(state.grid.radius, players)
		for count in goldByRegion(&state) {
			testing.expect(t, count >= game.goldFairMinimum(quota), "every region got its share")
			testing.expect(t, count <= quota, "no region got more than its quota")
		}
	}
}

@(test)
gold_lies_in_diggable_mountains :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state, ok := createPlayableGame(2, 1)
	testing.expect(t, ok, "found a playable map")
	if !ok do return
	for cell, index in state.grid.cells {
		if cell.value.gold == 0 do continue
		testing.expect(t, game.goldCandidate(state.grid, index), "gold sits in a mountain next to the main area")
		for player in state.players {
			testing.expect(t, hex.distance(cell.position.axial, player.units[0].position) > game.GOLD_SPAWN_CLEARANCE, "no gold right at a spawn")
		}
	}
}

@(test)
regions_follow_walking_distance :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeState(2)
	// a wall of mountains splits the map, with a gap on one side
	for &cell in state.grid.cells {
		if cell.position.axial.x == 0 && cell.position.axial.y != RADIUS {
			cell.value.walkable = false
			cell.value.color = game.MOUNTAIN_COLOR
		}
	}
	hex.markWalkableAreas(state.grid)
	spawns := []hex.Axial { { -3, 0 }, { 3, 0 } }
	regions := game.goldRegions(state.grid, spawns)

	// the tile just across the wall from the left spawn is a long walk from it
	testing.expect_value(t, regions[hex.axialToIndex({ 1, 0 }, RADIUS)], 1)
	testing.expect_value(t, regions[hex.axialToIndex({ -1, 0 }, RADIUS)], 0)
	// the wall itself joins the region of its nearest walkable side
	testing.expect_value(t, regions[hex.axialToIndex({ 0, -3 }, RADIUS)], 0)
}
