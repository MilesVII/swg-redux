package hex

Area :: [dynamic]Axial
Path :: []Axial

markWalkableAreas :: proc(grid: Grid(GridCell)) {
	gridMap := make(map[Axial]int)
	defer delete(gridMap)

	areas : [dynamic]Area
	shockwave : [dynamic]Axial
	defer {
		for area in areas do delete(area)
		delete(areas)
		delete(shockwave)
	}

	for &cell in grid.cells {
		cell.value.mainArea = false
		_, areaMarked := gridMap[cell.position.axial]

		if !cell.value.walkable || areaMarked do continue
		
		areaId := len(areas)
		newArea : Area

		gridMap[cell.position.axial] = areaId
		append(&shockwave, cell.position.axial)

		for len(shockwave) > 0 {
			origin := pop(&shockwave)
			append(&newArea, origin)

			for nb in AXIAL_NBS {
				tested := nb + origin
				if !cellIsWalkable(tested, grid) do continue

				_, testedMarked := gridMap[tested]

				if !testedMarked {
					gridMap[tested] = areaId
					append(&shockwave, tested)
				}
			}
		}
		append(&areas, newArea)
	}

	biggestAreaIx := -1
	for area, index in areas {
		if (biggestAreaIx < 0 || len(area) > len(areas[biggestAreaIx])) {
			biggestAreaIx = index
			continue
		}
	}

	if (biggestAreaIx >= 0) {
		for position in areas[biggestAreaIx] {
			grid.cells[axialToIndex(position, grid.radius)].value.mainArea = true
		}
	}
}

PathNode :: struct {
	previous: Axial,
	distance: int
}

findPath :: proc(grid: Grid(GridCell), from: Axial, to: Axial, allocator := context.allocator) -> (Path, bool) {
	gridMap := make(map[Axial]PathNode)
	defer delete(gridMap)

	if from == to do return nil, false
	if (!cellIsWalkable(to, grid)) do return nil, false

	shockwave : [dynamic]Axial
	defer delete(shockwave)
	gridMap[from] = {
		previous = from,
		distance = 0
	}
	append(&shockwave, from)
	success := false

	traverse: for len(shockwave) > 0 {
		minIndex := 0
		minHeur := 1000000
		for cell, index in shockwave {
			d := gridMap[cell].distance
			if d < minHeur {
				minIndex = index
				minHeur = d
			}
		}

		current := shockwave[minIndex]
		unordered_remove(&shockwave, minIndex)
		distance := gridMap[current].distance
		
		for nb in AXIAL_NBS {
			tested := current + nb

			if (tested in gridMap) do continue
			if !cellIsWalkable(tested, grid) do continue

			gridMap[tested] = PathNode {
				previous = current,
				distance = distance + 1
			}
			if tested == to {
				success = true
				break traverse
			}
			append(&shockwave, tested)
		}
	}

	if success {
		result := make([dynamic]Axial, allocator)
		append(&result, to)
		head := gridMap[to].previous

		for head != from {
			append(&result, head)
			head = gridMap[head].previous
		}
		append(&result, from)

		return result[:], true
	}

	return nil, false
}

// cells a unit can walk to in fewer than `limit` steps along walkable cells, including where it stands;
// a breadth first search, so winding paths around obstacles count their real length
findWalkableOutline :: proc (grid: Grid(GridCell), from: Axial, limit: int, allocator := context.allocator) -> []Axial {
	steps := make(map[Axial]int)
	defer delete(steps)
	queue := make([dynamic]Axial, context.temp_allocator)

	steps[from] = 0
	append(&queue, from)

	for head := 0; head < len(queue); head += 1 {
		current := queue[head]
		next := steps[current] + 1
		if next >= limit do continue

		for nb in AXIAL_NBS {
			tested := current + nb
			if tested in steps do continue
			if !cellIsWalkable(tested, grid) do continue

			steps[tested] = next
			append(&queue, tested)
		}
	}

	reachable := make([dynamic]Axial, 0, len(steps), allocator)
	for cell in steps do append(&reachable, cell)
	return reachable[:]
}

cellIsWalkable :: proc(position: Axial, grid: Grid(GridCell)) -> bool {
	if !isWithinGrid(position, grid.radius) do return false
	index := axialToIndex(position, grid.radius)
	value := grid.cells[index].value
	return value.walkable && !value.scrap
}
