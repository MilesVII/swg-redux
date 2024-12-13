package game

import "core:fmt"
import "core:net"
import "core:thread"
import "core:sync"

import "hex"
import "networking"
import "core:encoding/uuid"

socket : net.TCP_Socket
session : Session
PLAYER_COUNT :: 2

Message :: enum { JOIN, UPDATE_GRID, UPDATE_UNIT, SUBMIT }
GamePackage :: struct {
	message: Message,
	me: uuid.Identifier,
	grid: GameGrid
}

Player :: struct {
	id: Maybe(uuid.Identifier),
	online: bool,
	socket: net.TCP_Socket
}

Session :: struct {
	activePlayerIx: int,
	players: [PLAYER_COUNT]Player,
	game: GameState
}

wg : sync.Wait_Group

// GameState :: struct {
// 	visible units
// 	visible tiles
// }

server :: proc() {
	socket = networking.openServerSocket()

	session = Session {
		activePlayerIx = 0,
	}
	for &player in session.players do player.online = false
	session.game = createGame()
	
	waitForClients()
	// startThread(0)
	sync.wait_group_wait(&wg)
}

@(private)
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

@(private)
startThread :: proc(socket: ^net.TCP_Socket, userIndex: int) {
	t := thread.create(clientWorker)
	if t != nil {
		t.init_context = context
		t.user_index = userIndex
		t.data = socket
		thread.start(t)
	}
}

@(private)
clientWorker :: proc(t: ^thread.Thread) {
	onPackage :: proc(socket: net.TCP_Socket, header: networking.MessageHeader, payload: string) {
		fmt.printfln("player %s said %s", header.me, header.message)
		if header.payloadSize > 0 do fmt.printfln("payload: %s", payload)
		switch header.message {
			case .JOIN:
				// session.connections[playerSocket]
				onJoin(header.me, socket)
			case .UPDATE:
			case .SUBMIT:
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

sendGameGrid :: proc(socket: net.TCP_Socket) {
	header := networking.MessageHeader {
		message = .UPDATE,
	}
	gridJSON := hex.gridToJSON(session.game.grid)
	networking.say(socket, &header, gridJSON)
}

// checkPlayers

@(private)
onJoin :: proc(player: uuid.Identifier, socket: net.TCP_Socket) -> bool {
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
		}
	}

	if freeSlot == -1 {
		fmt.println("no slots available for player ", player)
		return false
	}

	sendGameGrid(socket)
	return true
}
