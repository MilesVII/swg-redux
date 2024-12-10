package hex

import "core:fmt"

Area :: [dynamic]CellPosition
Path :: []Axial

WalkableCell :: struct {
	areaId: int
}

markWalkableAreas :: proc(grid: Grid(GridCell)) {
	gridSize := len(grid.cells)
	gridMap := make([]WalkableCell, gridSize)
	defer delete(gridMap)
	for &gridCell in gridMap do gridCell.areaId = -1

	areas : [dynamic]Area
	pool : [dynamic]CellPosition

	for &cell, index in grid.cells {
		cell.value.mainArea = false

		if cell.value.walkable && gridMap[index].areaId == -1 {
			areaId := len(areas)
			newArea : Area

			gridMap[index].areaId = areaId
			append(&pool, cell.position)

			for len(pool) > 0 {
				origin := pop(&pool)
				append(&newArea, origin)

				for nb in AXIAL_NBS {
					tested := nb + origin.axial
					if !isWithinGrid(tested, grid.radius) do continue

					testedIndex := axialToIndex(tested, grid.radius)
					testedCell := grid.cells[testedIndex]
					assert(testedCell.position.axial == tested)

					if testedCell.value.walkable && gridMap[testedIndex].areaId == -1 {
						gridMap[testedIndex].areaId = areaId
						append(&pool, testedCell.position)
					}
				}
			}
			append(&areas, newArea)
			fmt.println(len(newArea))

			areaId += 1
		}
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
			grid.cells[position.index].value.mainArea = true
		}
	}
}

PathNode :: struct {
	previous: Axial,
	distance: int
}

findPath :: proc(grid: Grid(GridCell), from: Axial, to: Axial) -> (Path, bool) {
	gridMap := make(map[Axial]PathNode)
	defer delete(gridMap)

	if from == to do return nil, false
	if (!cellIsWalkable(from, grid) || !cellIsWalkable(to, grid)) do return nil, false

	shockwave : [dynamic]Axial
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
			d := distance(cell, to)
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
		result : [dynamic]Axial
		append(&result, to)
		head := gridMap[to].previous

		for head != from {
			append(&result, head)
			head = gridMap[head].previous
		}

		return result[:], true
	}

	return nil, false
}

findWalkableOutline :: proc (grid: Grid(GridCell), from: Axial, limit: int) -> []Axial {
	gridMap := make(map[Axial]PathNode)
	defer delete(gridMap)
	shockwave : [dynamic]Axial

	gridMap[from] = {
		previous = from,
		distance = 0
	}
	append(&shockwave, from)

	for len(shockwave) > 0 {
		current := pop(&shockwave)
		distance := gridMap[current].distance

		for nb in AXIAL_NBS {
			tested := current + nb

			if distance + 1 >= limit do continue
			if tested in gridMap do continue
			if !cellIsWalkable(tested, grid) do continue

			gridMap[tested] = PathNode {
				previous = current,
				distance = distance + 1
			}
			append(&shockwave, tested)
		}
	}

	for cell in gridMap do append(&shockwave, cell)

	return shockwave[:]
}

cellIsWalkable :: proc(position: Axial, grid: Grid(GridCell)) -> bool {
	if !isWithinGrid(position, grid.radius) do return false
	index := axialToIndex(position, grid.radius)
	return grid.cells[index].value.walkable
}
