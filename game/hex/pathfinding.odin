package hex

import "core:fmt"

Area :: [dynamic]CellPosition

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

isWithinGrid :: proc(cell: Axial, gridRadius: int) -> bool {
	return abs(cell.x) <= gridRadius && abs(cell.y) <= gridRadius
}