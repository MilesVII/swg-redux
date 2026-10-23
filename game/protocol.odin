package game

import rl "vendor:raylib"

import "core:slice"
import "core:encoding/endian"

import "hex"

TurnMessage :: struct {
	activePlayer: int,
	activeIsYou: bool,
	currentPlayerBadge: string,
	yourColor: rl.Color,
	yourId: int,
	// seconds per turn, 0 for no limit
	turnLimit: f32,
	// seconds left of the current turn when the update was sent
	turnTimeLeft: f32
}

// what the server sends a player after every change
Update :: struct {
	radius: int,
	// `cells` holds every cell of the map instead of changes to the previous update
	fullGrid: bool,
	// CELL_RECORD_SIZE bytes per cell, see packCell
	cells: []u8,
	// units of every player as the receiver sees them, knownTerrain is never sent
	players: []PlayerState,
	meta: TurnMessage,
	explosions: []ExplosionBufferEntry,
	gameStarted: bool,
	gameOver: bool,
	// players per team, 1 for free for all
	teamSize: int,
	// names of the winners joined with " & ", empty if nobody survived
	winnerBadge: string,
	// -1 if nobody survived
	winnerTeam: int,
	// per slot, "" while empty
	playerNames: []string,
	// per slot, whether the player confirmed their team; only team games wait for it
	playersReady: []bool,
	// the server has a replay of the finished game, see REPLAY_REQUEST
	replayAvailable: bool
}

// everything a replay needs to run the game again: the same map and the same orders
// with the same random seeds give the same game, see rules.odin
REPLAY_VERSION :: 1
Replay :: struct {
	version: int,
	radius: int,
	playerCount: int,
	teamSize: int,
	seed: i64,
	// per slot
	names: []string,
	turns: []ReplayTurn
}
ReplayTurn :: struct {
	player: int,
	// random seed the orders ran with
	seed: u64,
	orders: OrderSet
}
// a replay as sent to clients
ReplayFile :: struct {
	name: string,
	data: []u8
}

deleteReplay :: proc(replay: ^Replay) {
	for name in replay.names do delete(name)
	delete(replay.names)
	for &turn in replay.turns do delete(turn.orders)
	delete(replay.turns)
	replay^ = {}
}

// what an update is built from, see encodeUpdate; the server and the replay player both have one
UpdateSource :: struct {
	game: ^GameState,
	playerIndex: int,
	activePlayer: int,
	started: bool,
	over: bool,
	// the whole map regardless of fog, for replays
	revealAll: bool,
	explosions: []ExplosionBufferEntry,
	names: []string,
	ready: []bool,
	activeName: string,
	winnerName: string,
	winnerTeam: int,
	turnLimit: f32,
	turnTimeLeft: f32,
	replayAvailable: bool
}

// the update for one player, encoded; `sentCells` is what that player already has
// and is brought up to date, nil sends the whole map
encodeUpdate :: proc(src: UpdateSource, sentCells: ^[]hex.GridCell) -> []u8 {
	// explosions are filtered by what the player sees, even once the whole map is revealed
	visibleState := getStateForPlayer(src.game, src.playerIndex)
	defer deleteState(visibleState)
	reducedState := src.over || src.revealAll ? src.game^ : visibleState
	explosions := reduceExplosionsToVisible(&visibleState, src.playerIndex, src.explosions)
	defer delete(explosions)

	cells := reducedState.grid.cells
	fullGrid := sentCells^ == nil || len(sentCells^) != len(cells)
	packedCells := packCellChanges(cells, fullGrid ? nil : sentCells^)
	defer delete(packedCells)

	if fullGrid {
		delete(sentCells^)
		sentCells^ = make([]hex.GridCell, len(cells))
	}
	for cell, i in cells do sentCells^[i] = cell.value

	// units only, explored cells of other players are none of the receiver's business
	players := make([]PlayerState, len(reducedState.players), context.temp_allocator)
	for p, i in reducedState.players {
		players[i] = PlayerState { color = p.color, units = p.units, unitIdCounter = p.unitIdCounter }
	}

	update := Update {
		radius = reducedState.grid.radius,
		fullGrid = fullGrid,
		cells = packedCells,
		players = players,
		meta = {
			activePlayer = src.activePlayer,
			activeIsYou = src.playerIndex == src.activePlayer,
			yourColor = src.game.players[src.playerIndex].color,
			yourId = src.playerIndex,
			currentPlayerBadge = src.activeName,
			turnLimit = src.turnLimit,
			turnTimeLeft = src.turnTimeLeft
		},
		explosions = explosions[:],
		gameStarted = src.started,
		gameOver = src.over,
		teamSize = src.game.teamSize,
		winnerBadge = src.winnerName,
		winnerTeam = src.winnerTeam,
		playerNames = src.names,
		playersReady = src.ready,
		replayAvailable = src.replayAvailable
	}
	return encode(update)
}

// a player's choice before a team game starts
TeamChoice :: struct {
	team: int,
	ready: bool
}

ExplosionBufferEntry :: struct {
	position: hex.Axial,
	pix: int,
	lethal: bool,
	// side of the hit tile the shell came from, an index into hex.AXIAL_NBS; -1 when unknown or own
	side: int
}

// u32 cell index, rgba color, flags, gold, u16 elevation
CELL_RECORD_SIZE :: 12

@(private="file")
FLAG_WALKABLE :: u8(1)
@(private="file")
FLAG_SEETHROUGH :: u8(2)
@(private="file")
FLAG_MAIN_AREA :: u8(4)
@(private="file")
FOG_SHIFT :: 3
@(private="file")
FLAG_SCRAP :: u8(1 << 5)

@(private="file")
packCell :: proc(buffer: []u8, index: int, value: hex.GridCell) {
	endian.put_u32(buffer[0:4], .Little, u32(index))
	buffer[4] = value.color.r
	buffer[5] = value.color.g
	buffer[6] = value.color.b
	buffer[7] = value.color.a
	flags := u8(0)
	if value.walkable do flags |= FLAG_WALKABLE
	if value.seethrough do flags |= FLAG_SEETHROUGH
	if value.mainArea do flags |= FLAG_MAIN_AREA
	flags |= u8(value.fog) << FOG_SHIFT
	if value.scrap do flags |= FLAG_SCRAP
	buffer[8] = flags
	buffer[9] = u8(clamp(value.gold, 0, 255))
	endian.put_u16(buffer[10:12], .Little, u16(clamp(value.elevation, 0, 1) * 65535 + .5))
}

@(private="file")
unpackCell :: proc(buffer: []u8) -> (index: int, value: hex.GridCell) {
	raw, _ := endian.get_u32(buffer[0:4], .Little)
	index = int(raw)
	value.color = { buffer[4], buffer[5], buffer[6], buffer[7] }
	flags := buffer[8]
	value.walkable = flags & FLAG_WALKABLE != 0
	value.seethrough = flags & FLAG_SEETHROUGH != 0
	value.mainArea = flags & FLAG_MAIN_AREA != 0
	value.scrap = flags & FLAG_SCRAP != 0
	value.fog = hex.Fog(clamp(int(flags >> FOG_SHIFT) & 3, 0, len(hex.Fog) - 1))
	value.gold = int(buffer[9])
	elevation, _ := endian.get_u16(buffer[10:12], .Little)
	value.elevation = f32(elevation) / 65535
	return
}

// cells that differ from `previous`, or all cells of the map when there is nothing to compare with
packCellChanges :: proc(cells: []hex.Cell(hex.GridCell), previous: []hex.GridCell) -> []u8 {
	full := previous == nil || len(previous) != len(cells)
	count := 0
	for cell, i in cells {
		if !cell.visible do continue
		if full || previous[i] != cell.value do count += 1
	}

	packed := make([]u8, count * CELL_RECORD_SIZE)
	offset := 0
	for cell, i in cells {
		if !cell.visible do continue
		if !full && previous[i] == cell.value do continue
		packCell(packed[offset:offset + CELL_RECORD_SIZE], i, cell.value)
		offset += CELL_RECORD_SIZE
	}
	return packed
}

// the grid the update describes, built on `base` (the previously received grid) unless the update is full
// fails when the update doesn't fit the base, the caller should ask for a full update then
buildGrid :: proc(base: GameGrid, update: Update) -> (grid: GameGrid, ok: bool) {
	if update.radius <= 0 || len(update.cells) % CELL_RECORD_SIZE != 0 do return {}, false

	if update.fullGrid {
		grid = hex.grid(update.radius, hex.GridCell)
	} else {
		if base.radius != update.radius || len(base.cells) == 0 do return {}, false
		grid = GameGrid { radius = base.radius, cells = slice.clone(base.cells) }
	}

	for offset := 0; offset < len(update.cells); offset += CELL_RECORD_SIZE {
		index, value := unpackCell(update.cells[offset:offset + CELL_RECORD_SIZE])
		if index >= len(grid.cells) {
			delete(grid.cells)
			return {}, false
		}
		grid.cells[index].value = value
	}
	return grid, true
}

// frees everything decode allocated for an update
deleteUpdate :: proc(update: ^Update) {
	delete(update.cells)
	for player in update.players {
		delete(player.units)
		delete(player.knownTerrain)
	}
	delete(update.players)
	delete(update.explosions)
	delete(update.meta.currentPlayerBadge)
	delete(update.winnerBadge)
	for name in update.playerNames do delete(name)
	delete(update.playerNames)
	delete(update.playersReady)
	update^ = {}
}
