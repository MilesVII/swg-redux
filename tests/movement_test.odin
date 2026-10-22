package rules_test

import "core:testing"
import "core:slice"

import "../game/hex"

@(test)
move_range_counts_path_steps :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// a wall across the middle with gaps only at the map's edge
	grid := mountainMap({ 0, -2 }, { 0, -1 }, { 0, 0 }, { 0, 1 }, { 0, 2 })
	for at in ([]hex.Axial { { 0, -2 }, { 0, -1 }, { 0, 0 }, { 0, 1 }, { 0, 2 } }) {
		grid.cells[hex.axialToIndex(at, RADIUS)].value.walkable = false
	}
	from := hex.Axial { -2, 0 }
	reach := hex.findWalkableOutline(grid, from, 4)

	testing.expect(t, slice.contains(reach, hex.Axial { -1, -2 }), "two steps along open ground is in range")
	testing.expect(t, slice.contains(reach, hex.Axial { -2, 3 }), "three steps along open ground is in range")
	testing.expect(t, !slice.contains(reach, hex.Axial { -2, 4 }), "four steps is out of range")
	// three tiles away in a straight line, but seven steps around the wall
	testing.expect(t, !slice.contains(reach, hex.Axial { 1, 0 }), "a tile behind the wall is out of range")
	testing.expect(t, !slice.contains(reach, hex.Axial { 0, 0 }), "the wall itself is out of range")
}
