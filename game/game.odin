package game

import rl "vendor:raylib"

import "core:slice"
import "core:math"
import "core:math/rand"

import "hex"
import "ui"
import "utils"

HEIGHTS :: 11

MOUNTAIN_COLOR := rl.Color{ 154, 66, 66, 255 }

colors : [HEIGHTS]rl.Color = {
	rl.BLUE,
	rl.BLUE,
	rl.GREEN,
	rl.GREEN,
	rl.GREEN,
	rl.GREEN,
	rl.GREEN,
	rl.YELLOW,
	MOUNTAIN_COLOR,
	MOUNTAIN_COLOR,
	MOUNTAIN_COLOR
}
WALKABLE_LO :: 2
WALKABLE_HI :: 6

GameGrid :: hex.Grid(hex.GridCell)

GameUnitType :: enum { TONK, GUN, MCV, REC }
VISION := [GameUnitType] int { .TONK = 4, .GUN = 2, .MCV = 4, .REC = 8 }
MOVING := [GameUnitType] int { .TONK = 4, .GUN = 0, .MCV = 4, .REC = 5 }
ARANGE := [GameUnitType] int { .TONK = 8, .GUN = 8, .MCV = 0, .REC = 0 }
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
	grid: GameGrid,
	// players per team, 1 for free for all; player i is on team i / teamSize
	teamSize: int,
	// the map's seed, for replays
	seed: i64
}

replaySeedOf :: proc(state: GameState) -> i64 {
	return state.seed
}

teamOf :: proc(state: ^GameState, pix: int) -> int {
	return pix / max(state.teamSize, 1)
}

sameTeam :: proc(state: ^GameState, a, b: int) -> bool {
	return teamOf(state, a) == teamOf(state, b)
}

// explored terrain and remembered guns are shared by a team, kept by its first member
teamIntel :: proc(state: ^GameState, pix: int) -> ^PlayerState {
	return &state.players[teamOf(state, pix) * max(state.teamSize, 1)]
}

// members of a team get the team's color, later members a lighter shade of it
playerColor :: proc(pix: int, teamSize: int) -> rl.Color {
	size := max(teamSize, 1)
	base := PLAYER_COLORS[(pix / size) % len(PLAYER_COLORS)]
	member := f32(pix % size) * .35
	return {
		u8(f32(base.r) + (255 - f32(base.r)) * member),
		u8(f32(base.g) + (255 - f32(base.g)) * member),
		u8(f32(base.b) + (255 - f32(base.b)) * member),
		255
	}
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

// the spawns of findSpawnPoints in order around the map: E, NNE, NNW, W, SSW, SSE
@(private="file")
SPAWN_RING := [6]int { 1, 4, 2, 0, 5, 3 }

// which spawn around the map each player gets: teams sit together on one side of the map,
// free for all players are spread out
spawnSlots :: proc(playerCount: int, teamSize: int, allocator := context.allocator) -> []int {
	slots := make([]int, playerCount, allocator)
	if teamSize > 1 {
		// contiguous blocks; two teams of two leave a gap between them on either side
		start := playerCount == 4 ? 1 : 0
		for i in 0..<playerCount do slots[i] = (start + i + (i >= 2 && playerCount == 4 ? 1 : 0)) % 6
		return slots
	}
	spread := [7][]int { {}, { 0 }, { 0, 3 }, { 0, 2, 4 }, { 0, 1, 3, 4 }, { 0, 1, 2, 3, 4 }, { 0, 1, 2, 3, 4, 5 } }
	for i in 0..<playerCount do slots[i] = spread[playerCount][i]
	return slots
}

GameInitError :: enum { OK, NO_SPAWNS }
createGame :: proc(playerCount: int, mapRadius: int, seed := i64(0), teamSize := 1) -> (GameState, GameInitError) {
	seed := seed == -1 ? rand.int63() : seed
	// fmt.println("using seed ", seed)

	state := GameState {
		grid = hex.grid(mapRadius, hex.GridCell),
		players = make([]PlayerState, playerCount),
		teamSize = max(teamSize, 1),
		seed = seed
	}

	for &cell in state.grid.cells {
		elevation := hex.elevation(cell.position.world, seed)
		hi := hex.heightLevel(elevation, HEIGHTS)
		color := colors[hi]
		goldCell := color == rl.YELLOW

		cell.value = {
			color = goldCell ? MOUNTAIN_COLOR : color,
			walkable = hi <= WALKABLE_HI && hi >= WALKABLE_LO,
			seethrough = hi <= WALKABLE_HI,
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

	slots := spawnSlots(playerCount, state.teamSize, context.temp_allocator)
	for &player, i in state.players {
		units := []GameUnit {
			GameUnit {
				id = 0,
				position = spawnPoints[SPAWN_RING[slots[i]]],
				type = .MCV,
				gold = 2,
				hidden = false
			}
		}
		player = PlayerState {
			color = playerColor(i, state.teamSize),
			units = slice.clone_to_dynamic(units),
			knownTerrain = make([]bool, len(state.grid.cells)),
			unitIdCounter = 1
		}
	}
	
	return state, .OK
}

// what the player sees: the whole team's units look, and the team's memory is shared
getStateForPlayer :: proc(state: ^GameState, playerIndex: int) -> GameState {
	player := teamIntel(state, playerIndex)
	reducedState := cloneState(state^)
	for &cell, cellIndex in reducedState.grid.cells {
		if !cell.visible do continue

		known := player.knownTerrain[cellIndex]
		fallbackFogValue := known ? hex.Fog.TERRAIN : hex.Fog.FOG

		observedByUint := false
		observing: for &teammate, pix in state.players {
			if !sameTeam(state, pix, playerIndex) do continue
			for &unit in teammate.units {
				if
					hex.distance(unit.position, cell.position.axial) <= VISION[unit.type] &&
					hex.isVisible(state.grid, unit.position, cell.position.axial)
				{
					observedByUint = true
					break observing
				}
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
		if sameTeam(state, index, playerIndex) do continue

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

// own shells are marked with pix 1, everyone else's with -1 and the side they came from;
// `revealAll` shows every shell as if it were the player's own
reduceExplosionsToVisible :: proc(reducedState: ^GameState, playerIx: int, explosions: []ExplosionBufferEntry, revealAll := false) -> [dynamic]ExplosionBufferEntry {
	redex: [dynamic]ExplosionBufferEntry

	for bonk in explosions {
		bonk := bonk
		if playerIx == bonk.pix || revealAll {
			bonk.pix = 1
			bonk.side = -1
			append(&redex, bonk)
			continue
		} else {
			// a teammate's shells aren't yours, but they don't give away a teammate's gun either
			if sameTeam(reducedState, bonk.pix, playerIx) do bonk.side = -1
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
			ui.drawAmmoMarks(position, gold, GUN_SHELLS, rl.ORANGE)
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
