package game

import "core:fmt"
import "core:time"
import "core:net"
import "core:slice"
import synchan "core:sync/chan"

import "hex"
import "utils"
import "networking"

@(private="file")
receptionSocket : net.TCP_Socket
@(private="file")
session : Session

NAME_PLACEHOLDER :: "NAMELESS"

@(private="file")
Player :: struct {
	id: Maybe(string),
	online: bool,
	socket: net.TCP_Socket,
	// cell values the player has, updates only carry what changed since; nil sends the whole map
	sentCells: []hex.GridCell
}

@(private="file")
Session :: struct {
	activePlayerIx: int,
	players: []Player,
	game: GameState,
	over: bool,
	managed: bool
}

@(private="file")
serverOrderBuffer: OrderSet

@(private="file")
explosionsBuffer: [dynamic]ExplosionBufferEntry

@(private="file")
SERVER_IDLE_SKIP := time.Millisecond * 100

server :: proc(managed: bool, playerCount: int, mapRadius: int, mapSeed: i64, local: bool, port: int, lobbyPort: int) {
	session = Session {
		activePlayerIx = -1,
		players = make([]Player, playerCount),
		managed = managed
	}

	if managed {
		utils.loggingSilenced = true
		networking.verbose = false
	}

	networking.init()
	receptionSocket = networking.openServerSocket(
		local ? net.IP4_Loopback : net.IP4_Address { 0, 0, 0, 0 },
		port
	)

	for &player in session.players do player.online = false

	gameInitRetries := 7
	for gameInitRetries >= 0 {
		err: GameInitError
		session.game, err = createGame(playerCount, mapRadius, mapSeed)
		if err == .OK do break
		else if gameInitRetries == 0 || mapSeed != -1 {
			utils.log("failed to create a game, aborting")
			if session.managed do signalLobby(LOBBY_SIGNAL_TERMINATE)
			return
		}
		gameInitRetries -= 1
		utils.log("failed to create a game, retrying")
	}

	utils.log("session created, listening")
	if session.managed do signalLobby(LOBBY_SIGNAL_READY)

	networking.startAccepting(receptionSocket)

	for {
		for synchan.can_recv(networking.rx) {
			data, ok := synchan.recv(networking.rx)
			if ok do processPackage(data)
		}
		free_all(context.temp_allocator)
		time.sleep(SERVER_IDLE_SKIP)
	}
}

@(private="file")
processPackage :: proc(p: networking.Package) {
	defer delete(p.payload)

	playerName := utils.badgeToString(p.header.me, context.temp_allocator)
	if !session.managed && p.header.message < .CONNECTED {
		fmt.printfln("player %s said %s", playerName, p.header.message)
	}

	switch p.header.message {
		case .GENERAL:
		case .CONNECTED:
			if !session.managed do fmt.printfln("new client, waiting for JOIN")
		case .DISCONNECTED:
			for &player in session.players {
				if player.online && player.socket == p.socket {
					player.online = false
					utils.log(player.id, " disconnected")
				}
			}
			networking.hang(p.socket)
		case .JOIN:
			if onJoin(playerName, p.socket) do startGameIfFull()
		case .UPDATE:
			// the client lost track of the map, start over with a full one
			for &player, playerIndex in session.players {
				if !player.online || player.socket != p.socket do continue
				forgetSentCells(&player)
				sendUpdate(p.socket, playerIndex)
			}
		case .ORDERS:
			if session.activePlayerIx < 0 || session.over do break
			active := session.players[session.activePlayerIx]
			activeName, named := active.id.?
			if !named || !active.online || active.socket != p.socket || activeName != playerName do break

			clear(&serverOrderBuffer)
			if !decode(p.payload, &serverOrderBuffer) do break

			executeOrders(session.activePlayerIx, serverOrderBuffer)
			bonkUnits()

			session.over = gameOver()

			if !session.over do for {
				nextPlayer()
				if activeUnitsLeft(session.activePlayerIx) do break
			}

			broadcastUpdates()
			clear(&explosionsBuffer)
	}
}

@(private="file")
onJoin :: proc(player: string, socket: net.TCP_Socket) -> bool {
	freeSlot := -1
	for &p, index in session.players {
		id, exists := p.id.?
		if exists && id == player {
			utils.log(player, " reconnected")
			// welcome back
			if p.online && p.socket != socket {
				// the old connection's DISCONNECTED will close it
				networking.kick(p.socket)
			}
			// a new connection knows nothing about the map
			forgetSentCells(&p)
			p.socket = socket
			p.online = true
			freeSlot = index
			break
		}
	}
	if freeSlot == -1 do for &p, index in session.players {
		_, exists := p.id.?
		if !exists {
			p.id = utils.badgeToString(utils.stringToBadge(player))
			p.socket = socket
			p.online = true
			freeSlot = index
			break
		}
	}

	if freeSlot == -1 {
		utils.log("no slots available for player ", player)
		sendNotice(socket, "NO FREE SLOTS IN THIS GAME")
		return false
	}
	utils.log("assigned slot ", freeSlot)

	sendUpdate(socket, freeSlot)
	return true
}

@(private="file")
gameFull :: proc() -> bool {
	for player in session.players do if !player.online do return false
	return true
}
@(private="file")
gameStarted :: proc() -> bool {
	return session.activePlayerIx >= 0
}
@(private="file")
startGameIfFull :: proc() {
	// reconnects into a running game must not reset the turn
	if gameStarted() || !gameFull() do return

	if session.managed do signalLobby(LOBBY_SIGNAL_FULL)
	session.activePlayerIx = 0
	broadcastUpdates()
}

@(private="file")
broadcastUpdates :: proc() {
	for player, playerIndex in session.players {
		if player.online do sendUpdate(player.socket, playerIndex)
	}
}

@(private="file")
getActivePlayerName :: proc() -> string {
	if session.activePlayerIx < 0 do return NAME_PLACEHOLDER
	currentPlayer, cpe := session.players[session.activePlayerIx].id.?
	return cpe ? currentPlayer : NAME_PLACEHOLDER
}

@(private="file")
getWinnerName :: proc() -> string {
	for player, pix in session.players {
		if activeUnitsLeft(pix) {
			name, named := player.id.?
			return named ? name : NAME_PLACEHOLDER
		}
	}
	return ""
}

@(private="file")
sendNotice :: proc(socket: net.TCP_Socket, notice: string) {
	header := networking.MessageHeader {
		message = .GENERAL,
	}
	networking.say(socket, &header, encode(notice))
}

@(private="file")
forgetSentCells :: proc(player: ^Player) {
	delete(player.sentCells)
	player.sentCells = nil
}

@(private="file")
sendUpdate :: proc(socket: net.TCP_Socket, playerIndex: int) {
	header := networking.MessageHeader {
		message = .UPDATE,
	}
	// explosions are filtered by what the player sees, even once the whole map is revealed
	visibleState := getStateForPlayer(&session.game, playerIndex)
	defer deleteState(visibleState)
	reducedState := session.over ? session.game : visibleState
	explosions := reduceExplosionsToVisible(&visibleState, playerIndex, explosionsBuffer[:])
	defer delete(explosions)

	player := &session.players[playerIndex]
	cells := reducedState.grid.cells
	fullGrid := player.sentCells == nil || len(player.sentCells) != len(cells)
	packedCells := packCellChanges(cells, fullGrid ? nil : player.sentCells)
	defer delete(packedCells)

	if fullGrid {
		delete(player.sentCells)
		player.sentCells = make([]hex.GridCell, len(cells))
	}
	for cell, i in cells do player.sentCells[i] = cell.value

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
			activePlayer = session.activePlayerIx,
			activeIsYou = playerIndex == session.activePlayerIx,
			yourColor = session.game.players[playerIndex].color,
			yourId = playerIndex,
			currentPlayerBadge = getActivePlayerName()
		},
		explosions = explosions[:],
		gameStarted = gameStarted(),
		gameOver = session.over,
		winnerBadge = session.over ? getWinnerName() : ""
	}

	networking.say(socket, &header, encode(update))
}

// orders run in unit id order so results don't depend on map iteration order
// units built during this turn can't act until the next one
executeOrders :: proc(playerIx: int, orders: OrderSet) {
	idLimit := session.game.players[playerIx].unitIdCounter

	unitIds := make([dynamic]int, 0, len(orders), context.temp_allocator)
	for unitId in orders do if unitId < idLimit do append(&unitIds, unitId)
	slice.sort(unitIds[:])

	for unitId in unitIds do executeOrder(playerIx, unitId, orders[unitId])
}

executeOrder :: proc(playerIx: int, unitId: int, order: Order) {
	unit, ok := findUnitById(session.game.players[playerIx].units[:], unitId)
	if !ok do return
	if !orderAllowed(unit^, order) {
		utils.log("rejected order ", order, " for unit ", unitId)
		return
	}

	switch order.type {
		case .BUILD:
			unit.gold -= 1

			newUnit := GameUnit {
				position = order.target,
				type = order.targetUnitType,
				id = session.game.players[playerIx].unitIdCounter,
				gold = order.targetUnitType == .TONK ? 2 : 0
			}
			// invalidates `unit`
			append(&session.game.players[playerIx].units, newUnit)
			session.game.players[playerIx].unitIdCounter += 1
		case .DIG:
			cellIx := hex.axialToIndex(order.target, session.game.grid.radius)
			session.game.grid.cells[cellIx].value.gold -= 1
			unit.gold += 1
		case .DIREKT:
			entry := ExplosionBufferEntry {
				position = order.target,
				pix = playerIx
			}
			append(&explosionsBuffer, entry)
		case .INDIREKT:
			utils.shuffle(BONK_OFFSETS[:])

			for i in 0..<INDIREKT_BARRAGE_SIZE {
				entry := ExplosionBufferEntry {
					position = order.target + BONK_OFFSETS[i],
					pix = playerIx
				}
				append(&explosionsBuffer, entry)
			}
		case .MOVE:
			unit.position = order.target
	}
}

// mirrors the checks the client does before placing an order
@(private="file")
orderAllowed :: proc(unit: GameUnit, order: Order) -> bool {
	grid := session.game.grid
	target := order.target
	onGrid := hex.isWithinGrid(target, grid.radius)
	distance := hex.distance(unit.position, target)

	cellAt :: proc(grid: GameGrid, at: hex.Axial) -> hex.GridCell {
		return grid.cells[hex.axialToIndex(at, grid.radius)].value
	}

	switch order.type {
		case .BUILD:
			validType := order.targetUnitType >= min(GameUnitType) && order.targetUnitType <= max(GameUnitType)
			return validType &&
				unit.type == .MCV &&
				unit.gold > 0 &&
				distance == 1 &&
				onGrid &&
				cellAt(grid, target).walkable &&
				noUnitsAt(target, session.game.players)
		case .DIG:
			return unit.type == .MCV &&
				unit.gold < 3 &&
				distance == 1 &&
				onGrid &&
				cellAt(grid, target).gold > 0
		case .DIREKT:
			return unit.type == .TONK &&
				distance <= ARANGE[.TONK] &&
				hex.isVisible(grid, unit.position, target)
		case .INDIREKT:
			return unit.type == .GUN &&
				distance <= ARANGE[.GUN]
		case .MOVE:
			if MOVING[unit.type] == 0 || target == unit.position do return false
			if !noUnitsAt(target, session.game.players) do return false
			allowedCells := hex.findWalkableOutline(grid, unit.position, MOVING[unit.type], context.temp_allocator)
			return utils.includes(allowedCells, &target)
	}
	return false
}

bonkUnits :: proc() {
	for &bonk in explosionsBuffer {
		if !hex.isWithinGrid(bonk.position, session.game.grid.radius) do continue

		uix, pix, found := findUnitAt(&session.game, bonk.position)
		if found {
			unit := &session.game.players[pix].units[uix]

			if unit.type == .TONK && unit.gold > 1 do unit.gold -= 1
			else {
				unordered_remove(&session.game.players[pix].units, uix)
				bonk.lethal = true
			}
		}
	}
}

gameOver :: proc() -> bool {
	ablePlayers := 0
	for _, pix in session.game.players {
		if activeUnitsLeft(pix) do ablePlayers += 1
	}

	return ablePlayers <= 1
}

activeUnitsLeft :: proc(playerIx: int) -> bool {
	for unit in session.game.players[playerIx].units {
		if unit.type == .MCV do return true
	}
	return false
}

nextPlayer :: proc() {
	session.activePlayerIx += 1
	if session.activePlayerIx >= len(session.players) {
		session.activePlayerIx = 0
	}
}
