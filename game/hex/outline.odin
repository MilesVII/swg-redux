package hex

import rl "vendor:raylib" 

Line :: [4]rl.Vector2

// a cell border between a cell inside a region and one outside it
BoundaryEdge :: struct {
	a, b: rl.Vector2,
	inside, outside: Axial
}

// the border of all cells within `radius` of `center`, as segments along cell edges
rangeBoundary :: proc(center: Axial, radius: int, allocator := context.allocator) -> []BoundaryEdge {
	edges := make([dynamic]BoundaryEdge, allocator)
	for q in -radius..=radius {
		for r in max(-radius, -q - radius)..=min(radius, -q + radius) {
			cell := center + Axial { q, r }
			vx := vertesex(cell)
			for nhb, index in AXIAL_NBS {
				outside := cell + nhb
				if distance(outside, center) <= radius do continue
				next := index == 5 ? 0 : index + 1
				append(&edges, BoundaryEdge { vx[index], vx[next], cell, outside })
			}
		}
	}
	return edges[:]
}

outline :: proc (cells: []Axial, thickness := f32(.2), allocator := context.allocator) -> []Line {
	lines := make([dynamic]Line, allocator)

	gridMap := make(map[Axial]bool)
	defer delete(gridMap)
	for cell in cells do gridMap[cell] = true

	for cell in cells {
		vx := vertesex(cell)
		vxOuter := vertesex(cell, 1 + thickness)

		for nhb, index in AXIAL_NBS {
			target := cell + nhb
			_, nhbFound := gridMap[target]

			if !nhbFound {
				newIndesex := [2]int {index, index + 1}
				if index == 5 do newIndesex[1] = 0

				line := Line {
					vx[newIndesex[0]],
					vxOuter[newIndesex[0]],
					vxOuter[newIndesex[1]],
					vx[newIndesex[1]],
				}

				append(&lines, line)
			}
		}
	}

	return lines[:]
}