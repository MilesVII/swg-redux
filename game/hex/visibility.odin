package hex

isVisible :: proc(grid: Grid(GridCell), from: Axial, to: Axial) -> bool {
	if from == to do return true
	if !isWithinGrid(to, grid.radius) do return false

	sampleCount := distance(from, to) + 1
	origin := axialToWorld(from)
	worldRay := axialToWorld(to) - origin
	
	for i in 0..=(sampleCount - 2) {
		target := origin + worldRay * (f32(i) / f32(sampleCount))
		targetCell := worldToAxial(target)
		if !isWithinGrid(targetCell, grid.radius) do return false

		targetIndex := axialToIndex(targetCell, grid.radius)
		if !grid.cells[targetIndex].value.seethrough do return false
	}

	return true
}
