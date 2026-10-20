package game

import rl "vendor:raylib"

import "core:slice"
import "core:math"
import "core:math/rand"

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

GameUnitType :: enum { TONK, GUN, MCV, REC }
VISION := [GameUnitType] int { .TONK = 5, .GUN = 2, .MCV = 4, .REC = 8 }
MOVING := [GameUnitType] int { .TONK = 4, .GUN = 0, .MCV = 4, .REC = 5 }
ARANGE := [GameUnitType] int { .TONK = 5, .GUN = 8, .MCV = 0, .REC = 0 }
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
	// per grid cell, whether the player has ever seen it; server only
	knownTerrain: []bool,
	// enemy guns the player has seen; server only
	knownGuns: [dynamic]RememberedGun,
	unitIdCounter: int
}

// guns don't move, so once seen they stay on the map until their tile is seen empty
RememberedGun :: struct {
	pix: int,
	id: int,
	position: hex.Axial
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

GameInitError :: enum { OK, NO_SPAWNS }
createGame :: proc(playerCount: int, mapRadius: int, seed := i64(0)) -> (GameState, GameInitError) {
	seed := seed == -1 ? rand.int63() : seed
	// fmt.println("using seed ", seed)

	state := GameState {
		grid = hex.grid(mapRadius, hex.GridCell),
		players = make([]PlayerState, playerCount)
	}

	for &cell in state.grid.cells {
		elevation := hex.elevation(cell.position.world, seed)
		hi := hex.heightLevel(elevation, HEIGHTS)
		color := colors[hi]
		goldCell := color == rl.YELLOW

		cell.value = {
			color = goldCell ? MOUNTAIN_COLOR : color,
			walkable = hi < 8 && hi > 2,
			seethrough = hi < 8,
			fog = .FOG,
			gold = goldCell ? 1 : 0,
			elevation = elevation
		}
	}
	hex.markWalkableAreas(state.grid)

	assert(playerCount <= 6, "can't find more than six spawn points")
	spawnPoints := findSpawnPoints(state.grid)
	defer delete(spawnPoints)
	if len(spawnPoints) < 6 { // stricter check to avoid cramped maps
		delete(state.players)
		delete(state.grid.cells)
		return state, .NO_SPAWNS
	}

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
			knownTerrain = make([]bool, len(state.grid.cells)),
			unitIdCounter = 1
		}
	}
	
	return state, .OK
}

getStateForPlayer :: proc(state: ^GameState, playerIndex: int) -> GameState {
	player := &state.players[playerIndex]
	reducedState := cloneState(state^)
	for &cell, cellIndex in reducedState.grid.cells {
		if !cell.visible do continue

		known := player.knownTerrain[cellIndex]
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
			player.knownTerrain[cellIndex] = true
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

	observed :: proc(state: GameState, at: hex.Axial) -> bool {
		return state.grid.cells[hex.axialToIndex(at, state.grid.radius)].value.fog == .OBSERVED
	}
	remembered :: proc(player: ^PlayerState, pix: int, id: int) -> int {
		for gun, i in player.knownGuns do if gun.pix == pix && gun.id == id do return i
		return -1
	}

	for &p, index in reducedState.players {
		if index == playerIndex do continue

		for &unit in p.units {
			unit.hidden = !observed(reducedState, unit.position)
			if unit.hidden || unit.type != .GUN do continue
			if remembered(player, index, unit.id) < 0 {
				append(&player.knownGuns, RememberedGun { index, unit.id, unit.position })
			}
		}

		// out of sight units disappear, except guns the player has seen
		unitLen := len(p.units)
		for unitIndex := unitLen - 1; unitIndex >= 0; unitIndex -= 1 {
			unit := p.units[unitIndex]
			if unit.hidden && !(unit.type == .GUN && remembered(player, index, unit.id) >= 0) {
				unordered_remove(&p.units, unitIndex)
			}
		}
	}

	// guns destroyed out of sight stay where they were seen until their tile is seen empty
	for i := len(player.knownGuns) - 1; i >= 0; i -= 1 {
		gun := player.knownGuns[i]
		_, exists := findUnitById(reducedState.players[gun.pix].units[:], gun.id)
		if exists do continue
		if observed(reducedState, gun.position) {
			unordered_remove(&player.knownGuns, i)
			continue
		}
		append(&reducedState.players[gun.pix].units, GameUnit {
			id = gun.id,
			position = gun.position,
			type = .GUN,
			hidden = true
		})
	}

	return reducedState
}

reduceExplosionsToVisible :: proc(reducedState: ^GameState, playerIx: int, explosions: []ExplosionBufferEntry) -> [dynamic]ExplosionBufferEntry {
	redex: [dynamic]ExplosionBufferEntry

	for bonk in explosions {
		bonk := bonk
		if (playerIx == bonk.pix) {
			bonk.pix = 1
			bonk.side = -1
			append(&redex, bonk)
			continue
		} else {
			bonk.pix = -1
		}
		onGrid := hex.isWithinGrid(bonk.position, reducedState.grid.radius)

		if onGrid {
			cix := hex.axialToIndex(bonk.position, reducedState.grid.radius)
			if reducedState.grid.cells[cix].value.fog != .FOG {
				append(&redex, bonk)
			}
		} else {
			// TODO: check manually if any unit sees the bonk
			// hex.isVisible(reducedState.grid, unit.position, cell.position.axial)

			// just render them for now
			append(&redex, bonk)
		}
	}

	return redex
}

deleteState :: proc(state: GameState) {
	for p in state.players {
		delete(p.units)
		delete(p.knownTerrain)
	}
	delete(state.players)
	delete(state.grid.cells)
}

cloneState :: proc(state: GameState) -> GameState {
	newState := state
	newState.players = slice.clone(state.players)

	for &p in newState.players {
		p.units = slice.clone_to_dynamic(p.units[:])
		p.knownTerrain = slice.clone(p.knownTerrain)
		// the original keeps the memory, see getStateForPlayer
		p.knownGuns = nil
	}
	newState.grid.cells = slice.clone(state.grid.cells)

	return newState
}

// `remembered` draws a faded unit that is out of sight, see RememberedGun
drawUnit :: proc(position: hex.Axial, unit: GameUnitType, gold: int, color: rl.Color, highlight := false, remembered := false) -> bool {
	hovered := ui.pointedCell == position
	vx := hex.vertesex(position, hovered ? 1 : .8)
	color := color
	background := rl.BLACK
	if remembered {
		color.a = 110
		background.a = 110
	}
	rl.DrawTriangleFan(&vx[0], 6, background)

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
		case .REC:
			ui.drawTriangle(position, true, color, .3)
			ui.drawTriangle(position, false, color, .3)
	}

	if (highlight) {
		highlightColor := rl.YELLOW
		easedFlicker := (math.sin(utils.flicker * utils.TAU) + 1) * .5
		highlightColor.a = u8(easedFlicker * 255)
		ui.drawCellBorder(position, .2, highlightColor)
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
	for &player, playerIx in state.players {
		for &unit, unitIx in player.units {
			if unit.position == at {
				return unitIx, playerIx, true
			}
		}
	}

	return 0, 0, false
}
