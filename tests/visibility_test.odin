package rules_test

import "core:testing"
import rl "vendor:raylib"

import "../game/hex"

// flat open map with mountains on the given cells
mountainMap :: proc(mountains: ..hex.Axial) -> hex.Grid(hex.GridCell) {
	grid := hex.grid(RADIUS, hex.GridCell)
	for &cell in grid.cells {
		cell.value = { color = rl.GREEN, walkable = true, seethrough = true, mainArea = true, fog = .OBSERVED }
	}
	for at in mountains do grid.cells[hex.axialToIndex(at, RADIUS)].value.seethrough = false
	return grid
}

@(test)
mountain_in_front_of_the_target_blocks :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// straight lines of every length the units use, the mountain right before the target
	for steps in 2..=5 {
		target := hex.Axial { steps, 0 }
		grid := mountainMap({ steps - 1, 0 })
		testing.expectf(t, !hex.isVisible(grid, { 0, 0 }, target), "blocked at distance %d", steps)
		testing.expectf(t, !hex.isVisible(grid, target, { 0, 0 }), "blocked from the other side at distance %d", steps)
	}
}

@(test)
mountain_anywhere_on_the_line_blocks :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for blocker in 1..=4 {
		grid := mountainMap({ 0, blocker })
		testing.expectf(t, !hex.isVisible(grid, { 0, 0 }, { 0, 5 }), "blocked by the mountain %d tiles out", blocker)
	}
}

@(test)
open_lines_are_visible :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// a mountain next to the line, not on it
	grid := mountainMap({ 1, 1 })
	testing.expect(t, hex.isVisible(grid, { 0, 0 }, { 4, 0 }), "clear straight line")
	testing.expect(t, hex.isVisible(grid, { 0, 0 }, { 2, -4 }), "clear diagonal line")
	testing.expect(t, hex.isVisible(grid, { 0, 0 }, { 1, 0 }), "neighbors always see each other")
}

@(test)
lines_between_two_cells_need_both_clear :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// from (0,0) to (1,1) the line passes exactly between (1,0) and (0,1)
	testing.expect(t, hex.isVisible(mountainMap(), { 0, 0 }, { 1, 1 }), "clear when both are open")
	testing.expect(t, !hex.isVisible(mountainMap({ 1, 0 }), { 0, 0 }, { 1, 1 }), "blocked by the first")
	testing.expect(t, !hex.isVisible(mountainMap({ 0, 1 }), { 0, 0 }, { 1, 1 }), "blocked by the second")
	testing.expect(t, !hex.isVisible(mountainMap({ 0, 1 }), { 1, 1 }, { 0, 0 }), "blocked the other way too")
}

@(test)
visibility_is_symmetric :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	grid := mountainMap({ 1, 1 }, { -2, 3 }, { 2, -1 }, { 0, 2 })
	for q in -3..=3 do for r in -3..=3 {
		to := hex.Axial { q, r }
		if !hex.isWithinGrid(to, RADIUS) do continue
		testing.expectf(t, hex.isVisible(grid, { 0, 0 }, to) == hex.isVisible(grid, to, { 0, 0 }), "symmetric for %v", to)
	}
}
