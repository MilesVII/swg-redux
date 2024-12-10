package hex

import rl "vendor:raylib" 

Line :: [4]rl.Vector2

outline :: proc (cells: []Axial, thickness := f32(.2)) -> []Line {
	lines : [dynamic]Line

	gridMap := make(map[Axial]bool)
	defer delete(gridMap)
	for cell in cells do gridMap[cell] = true

	for cell, cellIndex in cells {
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