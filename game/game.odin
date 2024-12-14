package game

import rl "vendor:raylib"
import "core:slice"
import "core:fmt"
import "hex"
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

GameUnit :: struct {
	position: hex.Axial,
	type: GameUnitType,
	gold: int,
	hidden: bool
}

PlayerState :: struct {
	color: rl.Color,
	units: []GameUnit,
	knownTerrain: map[hex.Axial]bool
}

GameState :: struct {
	players: []PlayerState,
	grid: GameGrid
}

createGame :: proc() -> GameState {
	state := GameState {
		players = make([]PlayerState, PLAYER_COUNT),
		grid = hex.grid(MAP_RADIUS, hex.GridCell)
	}

	for &cell in state.grid.cells {
		hi := hex.height(cell.position.world, HEIGHTS)

		cell.value = {
			color = colors[hi],
			walkable = hi < 8 && hi > 2,
			seethrough = hi < 8
		}
	}
	hex.markWalkableAreas(state.grid)

	// INIT PLAYERS TOO
	for &player in state.players {
		player = PlayerState {
			color = rl.RED,
			units = []GameUnit {},
			knownTerrain = make(map[hex.Axial]bool)
		}
	}

	state.players[0].units = []GameUnit {
		GameUnit {
			position = {0, 0},
			type = .MCV,
			gold = 0
		}
	}

	return state
}

getStateForPlayer :: proc(state: GameState, playerIndex: int) -> GameState {
	player := state.players[playerIndex]
	// prevents memory corruption after passing to function for some reason
	fmt.println(state.players[0].units[0].type)
	reducedState := state
	reducedState.grid.cells = slice.clone(state.grid.cells)
	for &cell, cellIndex in reducedState.grid.cells {
		if !cell.visible do continue

		fallbackFogValue := cell.position.axial in player.knownTerrain ? hex.Fog.TERRAIN : hex.Fog.FOG

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
			player.knownTerrain[cell.position.axial] = true
		} else {
			cell.value.fog = fallbackFogValue
		}
	}

	for &p, index in reducedState.players {
		if index == playerIndex do continue

		for &unit in p.units {
			cellIndex := hex.axialToIndex(unit.position, state.grid.radius)
			unit.hidden = reducedState.grid.cells[cellIndex].value.fog == hex.Fog.OBSERVED
		}


		p.units = slice.filter(
			player.units,
			proc (unit: GameUnit) -> bool {return !unit.hidden}
		)
	}

	return reducedState
}
