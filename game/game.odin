package game

import rl "vendor:raylib"
import "core:slice"
import "core:math"
import "hex"
import "ui"
import "utils"

HEIGHTS :: 11

MOUNTAIN_COLOR := rl.Color{154, 66, 66, 255}

colors : [HEIGHTS]rl.Color = {
	rl.BLUE,
	rl.BLUE,
	rl.BLUE,
	rl.GREEN,
	rl.GREEN,
	rl.GREEN,
	rl.GREEN,
	rl.GREEN,
	rl.YELLOW,
	MOUNTAIN_COLOR,
	MOUNTAIN_COLOR
}

GameGrid :: hex.Grid(hex.GridCell)

GameUnitType :: enum { TONK, GUN, MCV }
VISION := [GameUnitType] int { .TONK = 3, .GUN = 2, .MCV = 6 }
MOVING := [GameUnitType] int { .TONK = 3, .GUN = 0, .MCV = 4 }
ARANGE := [GameUnitType] int { .TONK = 5, .GUN = 10, .MCV = 0 }
INDIREKT_BARRAGE_SIZE := 3

GameUnit :: struct {
	id: int,
	position: hex.Axial,
	type: GameUnitType,
	gold: int,
	hidden: bool
}

PlayerState :: struct {
	color: rl.Color,
	units: [dynamic]GameUnit,
	knownTerrain: [dynamic]hex.Axial,
	unitIdCounter: int
}

GameState :: struct {
	players: []PlayerState,
	grid: GameGrid
}

PLAYER_COLORS := [?]rl.Color {
	{218, 64, 0, 255},
	{0, 218, 138, 255},
	{167, 218, 0, 255},
	{0, 200, 218, 255},
	{200, 0, 200, 255},
	{20, 0, 220, 255}
}

BONK_OFFSETS := [?]hex.Axial {
	{0, 0},
	hex.AXIAL_NBS[0], hex.AXIAL_NBS[1],
	hex.AXIAL_NBS[2], hex.AXIAL_NBS[3],
	hex.AXIAL_NBS[4], hex.AXIAL_NBS[5]
}

findSpawnPoints :: proc(grid: GameGrid) -> [dynamic]hex.Axial {
	radius := grid.radius - 1
	startingPoint := [6]hex.Axial {
		{ -radius, 0 },
		{ radius, 0 },
		{ 0, -radius },
		{ 0, radius },
		{ radius, -radius },
		{ -radius, radius }
	}
	steps := [6]hex.Axial {
		{ 1, 0 },
		{ -1, 0 },
		{ 0, 1 },
		{ 0, -1 },
		{ -1, 1 },
		{ 1, -1 }
	}

	spawns: [dynamic]hex.Axial

	outer: for i in 0..<6 {
		for startingPoint[i] != {0, 0} {
			cellIx := hex.axialToIndex(startingPoint[i], grid.radius)
			if grid.cells[cellIx].value.mainArea {
				append(&spawns, startingPoint[i])
				continue outer
			} else {
				startingPoint[i] += steps[i]
			}
		}
	}

	return spawns
}

createGame :: proc(playerCount: int, mapRadius: int, seed := i64(0)) -> GameState {
	state := GameState {
		grid = hex.grid(mapRadius, hex.GridCell),
		players = make([]PlayerState, playerCount)
	}

	for &cell in state.grid.cells {
		hi := hex.height(cell.position.world, HEIGHTS, seed)
		color := colors[hi]
		goldCell := color == rl.YELLOW

		cell.value = {
			color = goldCell ? MOUNTAIN_COLOR : color,
			walkable = hi < 8 && hi > 2,
			seethrough = hi < 8,
			fog = .FOG,
			gold = goldCell ? 1 : 0
		}
	}
	hex.markWalkableAreas(state.grid)

	assert(playerCount <= 6, "can't find more than six spawn points")
	spawnPoints := findSpawnPoints(state.grid)
	assert(len(spawnPoints) >= playerCount, "can't find enough spawn points for this seed, please restart")

	for &player, i in state.players {
		units := []GameUnit {
			GameUnit {
				id = 0,
				position = spawnPoints[i],
				type = .MCV,
				gold = 2,
				hidden = false
			}
		}
		player = PlayerState {
			color = PLAYER_COLORS[i],
			units = slice.clone_to_dynamic(units),
			knownTerrain = make([dynamic]hex.Axial),
			unitIdCounter = 1
		}
	}

	return state
}

getStateForPlayer :: proc(state: ^GameState, playerIndex: int) -> GameState {
	player := &state.players[playerIndex]
	reducedState := cloneState(state^)
	reducedState.grid.cells = slice.clone(state.grid.cells)
	for &cell, cellIndex in reducedState.grid.cells {
		if !cell.visible do continue

		known := utils.includes(&player.knownTerrain, &cell.position.axial)
		fallbackFogValue := known ? hex.Fog.TERRAIN : hex.Fog.FOG

		observedByUint := false
		for &unit in player.units {
			if
				hex.distance(unit.position, cell.position.axial) <= VISION[unit.type] &&
				hex.isVisible(state.grid, unit.position, cell.position.axial)
			{
				observedByUint = true
				break
			}
		}

		if observedByUint {
			cell.value.fog = .OBSERVED
			if !known do append(&player.knownTerrain, cell.position.axial)
		} else {
			cell.value.walkable = false
			if fallbackFogValue == .FOG {
				cell.value = {
					color = rl.GRAY,
					walkable = false,
					seethrough = false,
					mainArea = false,
					fog = .FOG,
					gold = 0
				}
			} else do cell.value.fog = fallbackFogValue
		}
	}

	for &p, index in reducedState.players {
		if index == playerIndex do continue

		for &unit in p.units {
			cellIndex := hex.axialToIndex(unit.position, state.grid.radius)
			unit.hidden = reducedState.grid.cells[cellIndex].value.fog != hex.Fog.OBSERVED
		}

		unitLen := len(p.units)
		for unitIndex := unitLen - 1; unitIndex >= 0; unitIndex -= 1 {
			if p.units[unitIndex].hidden do unordered_remove(&p.units, unitIndex)
		}
	}

	for &cell, cellIndex in reducedState.grid.cells {
		if cell.visible && cell.value.walkable {
			cell.value.walkable = noUnitsAt(cell.position.axial, reducedState.players[:])
		}
	}

	return reducedState
}

reduceExplosionsToVisible :: proc(reducedState: ^GameState, explosions: []hex.Axial) -> [dynamic]hex.Axial {
	redex: [dynamic]hex.Axial

	for bonk in explosions {
		cix := hex.axialToIndex(bonk, reducedState.grid.radius)
		
		if reducedState.grid.cells[cix].value.fog != .FOG {
			append(&redex, bonk)
		}
	}

	return redex
}

deleteState :: proc(state: GameState) {
	delete(state.players)
	for p in state.players {
		delete(p.units)
		delete(p.knownTerrain)
	}
	delete(state.grid.cells)
}

cloneState :: proc(state: GameState) -> GameState {
	newState := state
	newState.players = slice.clone(state.players)

	for &p, i in newState.players {
		p.units = slice.clone_to_dynamic(p.units[:])
		p.knownTerrain = slice.clone_to_dynamic(p.knownTerrain[:])
	}
	newState.grid.cells = slice.clone(state.grid.cells)

	return newState
}

drawUnit :: proc(position: hex.Axial, unit: GameUnitType, gold: int, color: rl.Color, highlight := false) -> bool {
	hovered := ui.pointedCell == position
	vx := hex.vertesex(position, hovered ? 1 : .8)
	rl.DrawTriangleFan(&vx[0], 6, rl.BLACK)

	switch unit {
		case .GUN:
			ui.drawTriangle(position, true, color, .7)
		case .TONK:
			ui.drawTriangle(position, false, color, .7)
			ui.drawGoldMarks(position, gold, rl.RED)
		case .MCV:
			ui.drawTriangle(position, true, color, .7)
			ui.drawTriangle(position, false, color, .7)
			ui.drawGoldMarks(position, gold)
	}

	if (highlight) {
		color := rl.YELLOW
		easedFlicker := (math.sin(utils.flicker * utils.TAU) + 1) * .5
		color.a = u8(easedFlicker * 255)
		ui.drawCellBorder(position, .2, color)
	}

	return hovered
}

noUnitsAt :: proc(at: hex.Axial, players: []PlayerState) -> bool {
	for player in players {
		for unit in player.units {
			if unit.position == at do return false
		}
	}

	return true
}

findUnitById :: proc(units: []GameUnit, id: int) -> (^GameUnit, bool) {
	for &unit, i in units {
		if unit.id == id do return &(units[i]), true
	}
	return nil, false
}

findUnitAt :: proc(state: ^GameState, at: hex.Axial) -> (uix: int, pix: int, found: bool) {
	for &player, pix in state.players {
		for &unit, uix in player.units {
			if unit.position == at {
				return uix, pix, true
			}
		}
	}

	return 0, 0, false
}
