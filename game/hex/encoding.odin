package hex

import "core:fmt"
import "core:encoding/json"

gridToJSON :: proc(grid: Grid(GridCell)) -> string {
	bytes, err := json.marshal(grid, {
		pretty = true
	})
	if err != nil do fmt.panicf("failed to marshal grid with \"%s\"", err)
	// fmt.println("marshed ", len(bytes), " bytes")
	return transmute(string)bytes
}

jsonToGrid :: proc(gridData: string) -> Grid(GridCell) {
	grid: Grid(GridCell)
	// fmt.println("unmarshing ", len(gridData), " bytes")
	err := json.unmarshal(transmute([]byte)gridData, &grid)
	if err != nil do fmt.panicf("failed to unmarshal grid with \"%s\"", err)
	return grid
}
