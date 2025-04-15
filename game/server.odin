package game

import rl "vendor:raylib"

import "core:fmt"
import "core:net"
import "core:thread"
import synchan "core:sync/chan"

import "hex"
import "utils"
import "networking"

@(private="file")
receptionSocket : net.TCP_Socket
@(private="file")
session : Session

Player :: struct {
	id: Maybe(string),
	online: bool,
	socket: net.TCP_Socket
}

Session :: struct {
	activePlayerIx: int,
	players: []Player,
	game: GameState,
	over: bool
}

TurnMessage :: struct {
	activePlayer: int,
	activeIsYou: bool,
	yourColor: rl.Color,
	yourId: int
}
Update :: struct {
	gameState: GameState,
	meta: TurnMessage,
	explosions: []ExplosionBufferEntry
}

ExplosionBufferEntry :: struct {
	position: hex.Axial,
	pix: int,
	lethal: bool
}

@(private="file")
serverOrderBuffer: OrderSet

@(private="file")
explosionsBuffer: [dynamic]ExplosionBufferEntry

server :: proc(playerCount: int, mapRadius: int, mapSeed: i64, local: bool, port: int) {
	session = Session {
		activePlayerIx = -1,
		players = make([]Player, playerCount)
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
		if err == nil do break
		else if gameInitRetries == 0 || mapSeed == -1 {
			fmt.println("failed to create a game, aborting")
			return
		}
		gameInitRetries -= 1
		fmt.println("failed to create a game, retrying")
	}

	startListeningForClients()

	for {
		for synchan.can_recv(networking.rx) {
			data, ok := synchan.recv(networking.rx)
			processPackage(data)
		}
	}
}

@(private="file")
startListeningForClients :: proc() {
	waitForClients :: proc(t: ^thread.Thread) {
		for counter := 0; ; counter += 1 {
			clientSocket := new(net.TCP_Socket)
			clientSocket^ = networking.waitForClient(receptionSocket)
			fmt.printfln("new client, waiting for JOIN")
			startClientThread(clientSocket)
		}
	}

	t := thread.create(waitForClients)
	if t != nil {
		t.init_context = context
		t.user_index = 0
		thread.start(t)
	}
}

@(private="file")
startClientThread :: proc(socket: ^net.TCP_Socket) {
	clientWorker :: proc(t: ^thread.Thread) {
		playerSocket := (transmute(^net.TCP_Socket)t.data)^
		tx := networking.tx
		networking.listenBlocking(tx, playerSocket)
		// listenBlocking terminates if there's a socket error
		for &player in session.players {
			if player.socket == playerSocket do player.online = false
		}
		free(t.data)
	}

	t := thread.create(clientWorker)
	if t != nil {
		t.init_context = context
		t.data = socket
		thread.start(t)
	}
}


@(private="file")
processPackage :: proc(p: networking.Package) {
	fmt.printfln("player %s said %s", p.header.me, p.header.message)
	playerName := utils.badgeToString(p.header.me)
	if p.header.payloadSize > 0 do fmt.printfln("payload: %s", p.payload)
	switch p.header.message {
		case .JOIN:
			if onJoin(utils.badgeToString(p.header.me), p.socket) do startGameIfFull()
		case .UPDATE: //ignored
		case .ORDERS:
			if (session.players[session.activePlayerIx].id != playerName) do break

			clear(&serverOrderBuffer)
			decode(p.payload, &serverOrderBuffer)

			for unitId in serverOrderBuffer {
				executeOrder(session.activePlayerIx, unitId, serverOrderBuffer[unitId])
			}
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
			// welcome back
			p.socket = socket
			p.online = true
			freeSlot = index
			break
		}
	}
	if freeSlot == -1 do for &p, index in session.players {
		id, exists := p.id.?
		if !exists {
			p.id = player
			p.socket = socket
			p.online = true
			freeSlot = index
			break
		}
	}

	if freeSlot == -1 {
		fmt.println("no slots available for player ", player)
		return false
	}
	fmt.println("assigned slot ", freeSlot)

	sendUpdate(socket, freeSlot)
	return true
}

@(private="file")
startGameIfFull :: proc() {
	for player in session.players do if !player.online do return

	session.activePlayerIx = 0
	broadcastUpdates()
}

@(private="file")
broadcastUpdates :: proc() {
	for player, playerIndex in session.players {
		sendUpdate(player.socket, playerIndex)
	}
}

@(private="file")
sendUpdate :: proc(socket: net.TCP_Socket, playerIndex: int) {
	header := networking.MessageHeader {
		message = .UPDATE,
	}
	reducedState := session.over ? session.game : getStateForPlayer(&session.game, playerIndex)
	update := Update {
		gameState = reducedState,
		meta = {
			activePlayer = session.activePlayerIx,
			activeIsYou = playerIndex == session.activePlayerIx,
			yourColor = session.game.players[playerIndex].color,
			yourId = playerIndex
		},
		explosions = reduceExplosionsToVisible(&reducedState, playerIndex, explosionsBuffer[:])[:]
	}

	networking.say(socket, &header, encode(update))
	if !session.over do deleteState(reducedState)
}

executeOrder :: proc(playerIx: int, unitId: int, order: Order) {
	unit, ok := findUnitById(session.game.players[playerIx].units[:], unitId)
	if !ok do return

	switch order.type {
		case .BUILD: 
			if unit.gold <= 0 do break
			unit.gold -= 1

			newUnit := GameUnit {
				position = order.target,
				type = order.targetUnitType,
				id = session.game.players[playerIx].unitIdCounter,
				gold = order.targetUnitType == .TONK ? 2 : 0
			}
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
	for player, pix in session.game.players {
		if activeUnitsLeft(pix) do ablePlayers += 1
	}

	return ablePlayers <= 1
}

activeUnitsLeft :: proc(playerIx: int) -> bool {
	for unit in session.game.players[playerIx].units {
		if unit.type == .MCV || unit.type == .TONK do return true
	}
	return false
}

nextPlayer :: proc() {
	session.activePlayerIx += 1
	if session.activePlayerIx >= len(session.players) {
		session.activePlayerIx = 0
	}
}
