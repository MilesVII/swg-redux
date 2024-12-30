package game

import rl "vendor:raylib"

import "core:fmt"
import "core:net"
import "core:thread"
import "core:sync"

import "hex"
import "utils"
import "networking"

@(private="file")
socket : net.TCP_Socket
@(private="file")
session : Session
@(private="file")
wg : sync.Wait_Group

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

Update :: struct {
	gameState: GameState,
	meta: struct {
		activePlayer: int,
		activeIsYou: bool,
		yourColor: rl.Color
	}
}

TurnMessage :: struct {
	activePlayer: int,
	activeIsYou: bool,
	yourColor: rl.Color
}

serverOrderBuffer: OrderSet

server :: proc() {
	socket = networking.openServerSocket()

	session = Session {
		activePlayerIx = -1,
	}
	for &player in session.players do player.online = false
	session.game = createGame()
	
	waitForClients()
	sync.wait_group_wait(&wg)
}

@(private="file")
waitForClients :: proc() {
	connections : [dynamic] net.TCP_Socket

	for counter := 0; ; counter += 1 {
		clientSocket := networking.waitForClient(socket)
		append(&connections, clientSocket)
		fmt.printfln("new client, waiting for JOIN")
		sync.wait_group_add(&wg, 1)
		startThread(&connections[len(connections) - 1], counter)
	}
}

@(private="file")
startThread :: proc(socket: ^net.TCP_Socket, userIndex: int) {
	t := thread.create(clientWorker)
	if t != nil {
		t.init_context = context
		t.user_index = userIndex
		t.data = socket
		thread.start(t)
	}
}

@(private="file")
clientWorker :: proc(t: ^thread.Thread) {
	onPackage :: proc(socket: net.TCP_Socket, header: networking.MessageHeader, payload: string) {
		fmt.printfln("player %s said %s", header.me, header.message)
		playerName := utils.badgeToString(header.me)
		if header.payloadSize > 0 do fmt.printfln("payload: %s", payload)
		switch header.message {
			case .JOIN:
				if onJoin(utils.badgeToString(header.me), socket) do startGameIfFull()
			case .UPDATE: //ignored
			case .ORDERS:
				if (session.players[session.activePlayerIx].id != playerName) do break

				clear(&serverOrderBuffer)
				decode(payload, &serverOrderBuffer)

				fmt.println(serverOrderBuffer)
		}
	}

	playerSocket := (transmute(^net.TCP_Socket)t.data)^
	networking.listenBlocking(onPackage, playerSocket)
	// listenBlocking terminates if there's a socket error
	for &player in session.players {
		if player.socket == playerSocket do player.online = false
	}

	sync.wait_group_done(&wg)
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

