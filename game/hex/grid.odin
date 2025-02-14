package hex

import rl "vendor:raylib"
import "core:math"
import "../utils"

import "core:fmt"

Axial :: [2]int

//   2
// 3/ \1
//  | |
// 4\ /0
//   5

BASIS_X :: rl.Vector2{1.0, 0}
BASIS_Y :: rl.Vector2{0.5, 0.86602540378}

RADIUS :: 0.57735026919 // 1.0 / math.sqrt(f32(3))

AXIAL_NBS := [?]Axial {
	Axial{1, 0},
	Axial{1, -1},
	Axial{0, -1},
	Axial{-1, 0},
	Axial{-1, 1},
	Axial{0, 1}
}

CellPosition :: struct {
	axial: Axial,
	axialMemory: Axial,
	world: rl.Vector2,
	index: int
}

Cell :: struct($Value: typeid) {
	position: CellPosition,
	vertesex: [6]rl.Vector2,
	visible: bool,
	value: Value
}

Grid :: struct($Value: typeid) {
	radius: int,
	cells: []Cell(Value),
}

Fog :: enum { OBSERVED, TERRAIN, FOG }

GridCell :: struct {
	color: rl.Color,
	walkable: bool,
	seethrough: bool,
	mainArea: bool,
	fog: Fog,
	gold: int
}

grid :: proc(radius: int, $Value: typeid) -> Grid(Value) {
	side := getGridSide(radius)
	size := side * side

	cells := make([]Cell(Value), size)

	for y in 0..<side {
	for x in 0..<side {
		axial := Axial {
			x - radius,
			y - radius
		}

		index := y * side + x
		cells[index] = {
			position = {
				axial = axial,
				axialMemory = {x, y},
				world = axialToWorld(axial),
				index = index
			},
			vertesex = vertesex(axial),
			visible = isWithinGrid(axial, radius)
		}
	}}

	return Grid(Value) {
		radius = radius,
		cells = cells
	}
}

getGridSide :: proc(radius: int) -> int {
	return radius * 2 + 1
}

vertesexRaw :: proc(position: rl.Vector2, rayLength: f32) -> [6]rl.Vector2 {
	ray := rl.Vector2 {0, rayLength }

	sixty : f32 = -utils.TAU / 6.0
	ray = rl.Vector2Rotate(ray, sixty)

	return [6]rl.Vector2 {
		position + ray,
		position + rl.Vector2Rotate(ray, sixty),
		position + rl.Vector2Rotate(ray, sixty * 2),
		position + rl.Vector2Rotate(ray, sixty * 3),
		position + rl.Vector2Rotate(ray, sixty * 4),
		position + rl.Vector2Rotate(ray, sixty * 5),
	}
}

vertesex :: proc(position: Axial, scale : f32 = 1) -> [6]rl.Vector2 {
	displacement := BASIS_X * f32(position.x) + BASIS_Y * f32(position.y)
	
	return vertesexRaw(displacement, RADIUS * scale)
}

distance :: proc(a: Axial, b: Axial) -> int {
	v := a - b
	return (abs(v.x) + abs(v.x + v.y) + abs(v.y)) / 2
}

axialToWorld :: proc (v: Axial) -> rl.Vector2 {
	return BASIS_X * f32(v.x) + BASIS_Y * f32(v.y)
}

// https://www.redblobgames.com/grids/hexagons/more-pixel-to-hex.html#justin-pombrio
worldToAxial :: proc (v: rl.Vector2) -> Axial {
	sqrt3 := math.sqrt(f32(3))
	size := 1.0 / sqrt3

	f: [2]f32 = {
		(sqrt3 / 3.0 * v.x - 1.0 / 3 * v.y),
		2.0 / 3.0 * v.y
	} / size

	fZ := -f.x - f.y
	a := math.ceil(f.x - f.y)
	b := math.ceil(f.y - fZ)
	c := math.ceil(fZ - f.x)

	return Axial {
		int(math.round((a - c) / 3)),
		int(math.round((b - a) / 3))
	}
}

axialToIndex :: proc(v: Axial, radius: int) -> int {
	t := v + Axial { radius, radius }
	return t.y * getGridSide(radius) + t.x
}

isWithinGrid :: proc(cell: Axial, gridRadius: int) -> bool {
	return distance(cell, {0, 0}) <= gridRadius
}

nbs :: proc(cell: Axial) -> [7]Axial {
	return {
		cell,
		cell + AXIAL_NBS[0],
		cell + AXIAL_NBS[1],
		cell + AXIAL_NBS[2],
		cell + AXIAL_NBS[3],
		cell + AXIAL_NBS[4],
		cell + AXIAL_NBS[5]
	}
}
