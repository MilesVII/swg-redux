package hex

import rl "vendor:raylib"

// line of sight: every cell between `from` and `to` has to be see-through;
// where the line runs exactly between two cells, both have to be
isVisible :: proc(grid: Grid(GridCell), from: Axial, to: Axial) -> bool {
	if from == to do return true
	if !isWithinGrid(to, grid.radius) do return false

	for cell in lineOfSightCells(from, to, context.temp_allocator) {
		if !isWithinGrid(cell, grid.radius) do return false
		if !grid.cells[axialToIndex(cell, grid.radius)].value.seethrough do return false
	}
	return true
}

// cells the straight line between two cell centers passes through, excluding both ends;
// a point equidistant from two cell centers counts for both cells
lineOfSightCells :: proc(from: Axial, to: Axial, allocator := context.allocator) -> []Axial {
	cells := make([dynamic]Axial, allocator)
	steps := distance(from, to)
	if steps < 2 do return cells[:]

	origin := axialToWorld(from)
	ray := axialToWorld(to) - origin
	// sampling at the cell centers of the hex line: ties are only ever exact, so a small tolerance is enough
	TIE :: f32(1e-3)

	for i in 1..<steps {
		point := origin + ray * (f32(i) / f32(steps))
		nearest := worldToAxial(point)
		nearestDistance := rl.Vector2Distance(axialToWorld(nearest), point)
		append(&cells, nearest)
		for nb in AXIAL_NBS {
			other := nearest + nb
			if rl.Vector2Distance(axialToWorld(other), point) <= nearestDistance + TIE do append(&cells, other)
		}
	}
	return cells[:]
}
