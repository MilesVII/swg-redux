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
socket : net.TCP_Socket
@(private="file")
session : Session

Player :: struct {
	id: Maybe(string),
	online: bool,
	socket: net.TCP_Socket
}

Session :: struct {
	activePlayerIx: int,
	players: [PLAYER_COUNT]Player,
	game: GameState
}

TurnMessage :: struct {
	activePlayer: int,
	activeIsYou: bool,
	yourColor: rl.Color
}
Update :: struct {
	gameState: GameState,
	meta: TurnMessage
}


@(private="file")
serverOrderBuffer: OrderSet
@(private="file")
clientSockets: [dynamic]net.TCP_Socket

server :: proc() {
	networking.init()
	socket = networking.openServerSocket()

	session = Session {
		activePlayerIx = -1,
	}
	for &player in session.players do player.online = false
	session.game = createGame()
	
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
			clientSocket := networking.waitForClient(socket)
			append(&clientSockets, clientSocket)
			fmt.printfln("new client, waiting for JOIN")
			startClientThread(counter)
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
startClientThread :: proc(userIndex: int) {
	clientWorker :: proc(t: ^thread.Thread) {
		playerSocket := clientSockets[t.user_index]
		tx := networking.tx
		networking.listenBlocking(tx, playerSocket)
		// listenBlocking terminates if there's a socket error
		for &player in session.players {
			if player.socket == playerSocket do player.online = false
		}
	}

	t := thread.create(clientWorker)
	if t != nil {
		t.init_context = context
		t.user_index = userIndex
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
			if onJoin(utils.badgeToString(p.header.me), socket) do startGameIfFull()
		case .UPDATE: //ignored
		case .ORDERS:
			if (session.players[session.activePlayerIx].id != playerName) do break

			clear(&serverOrderBuffer)
			decode(p.payload, &serverOrderBuffer)

			for unitId in serverOrderBuffer {
				executeOrder(session.activePlayerIx, unitId, serverOrderBuffer[unitId])
			}

			session.activePlayerIx += 1
			if session.activePlayerIx >= PLAYER_COUNT {
				session.activePlayerIx = 0
			}
			broadcastUpdates()
	}
}

@(private="file")
onJoin :: proc(player: string, socket: net.TCP_Socket) -> bool {
	freeSlot := -1
	for &p, index in session.players {
		id, exists := p.id.?
		if exists && id == player {
			// TODO
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
	update := Update {
		gameState = getStateForPlayer(&session.game, playerIndex),
		meta = {
			activePlayer = session.activePlayerIx,
			activeIsYou = playerIndex == session.activePlayerIx,
			yourColor = session.game.players[playerIndex].color
		}
	}

	// gameJSON := encode(game)
	networking.say(socket, &header, encode(update))
}

executeOrder :: proc(playerIx: int, unitId: int, order: Order) {
	unit, ok := findUnitById(session.game.players[playerIx].units[:], unitId)
	if !ok do return

	switch order.type {
		case .BUILD: 
			newUnit := GameUnit {
				position = order.target,
				type = order.targetUnitType
			}
			append(&session.game.players[playerIx].units, newUnit)
		case .DIG:
			cellIx := hex.axialToIndex(order.target, session.game.grid.radius)
			session.game.grid.cells[cellIx].value.gold -= 1
			unit.gold += 1
		case .DIREKT:
			// todo
		case .INDIREKT:
			// todo
		case .MOVE:
			unit.position = order.target
	}
}
