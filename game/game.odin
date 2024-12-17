package game

import rl "vendor:raylib"
import "core:slice"
// import "core:fmt"
import "hex"
import "ui"
import "utils"

MAP_RADIUS :: 16
HEIGHTS :: 11
PLAYER_COUNT :: 2

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
	{154, 66, 66, 255},
	{154, 66, 66, 255}
}

GameGrid :: hex.Grid(hex.GridCell)

GameUnitType :: enum { TONK, GUN, MCV }
VISION := [GameUnitType] int { .TONK = 3, .GUN = 1, .MCV = 5}
MOVING := [GameUnitType] int { .TONK = 2, .GUN = 0, .MCV = 3}

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
	players: [PLAYER_COUNT]PlayerState,
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

createGame :: proc() -> GameState {
	state := GameState {
		grid = hex.grid(MAP_RADIUS, hex.GridCell)
	}

	for &cell in state.grid.cells {
		hi := hex.height(cell.position.world, HEIGHTS)

		cell.value = {
			color = colors[hi],
			walkable = hi < 8 && hi > 2,
			seethrough = hi < 8,
			fog = .FOG
		}
	}
	hex.markWalkableAreas(state.grid)

	assert(PLAYER_COUNT <= 6, "can't find more than six spawn points")
	spawnPoints := findSpawnPoints(state.grid)
	assert(len(spawnPoints) >= PLAYER_COUNT, "can't find enough spawn points for this seed, please restart")

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
			if fallbackFogValue == .FOG {
				cell.value = {
					color = rl.GRAY,
					walkable = false,
					seethrough = false,
					mainArea = false,
					fog = .FOG
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

	return reducedState
}

deleteState :: proc(state: GameState) {
	for p in state.players {
		delete(p.units)
		delete(p.knownTerrain)
	}
	delete(state.grid.cells)
}

cloneState :: proc(state: GameState) -> GameState {
	newState := state
	for &p, i in newState.players {
		p.units = slice.clone_to_dynamic(p.units[:])
		p.knownTerrain = slice.clone_to_dynamic(p.knownTerrain[:])
	}
	newState.grid.cells = slice.clone(state.grid.cells)

	return newState
}

drawUnit :: proc(position: hex.Axial, unit: GameUnitType, color: rl.Color) -> bool {
	hovered := ui.pointedCell == position
	vx := hex.vertesex(position, hovered ? 1 : .8)
	rl.DrawTriangleFan(&vx[0], 6, rl.BLACK)

	switch unit {
		case .GUN:
			ui.drawTriangle(position, true, color, .7)
		case .TONK:
			ui.drawTriangle(position, false, color, .7)
		case .MCV:
			ui.drawTriangle(position, true, color, .7)
			ui.drawTriangle(position, false, color, .7)
	}

	return hovered
}
