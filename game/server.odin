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

Message :: enum { JOIN, UPDATE_GRID, UPDATE_UNIT, SUBMIT }
GamePackage :: struct {
	message: Message,
	me: uuid.Identifier,
	grid: GameGrid
}

Player :: struct {
	id: Maybe(uuid.Identifier),
	socket: net.TCP_Socket
}

Session :: struct {
	started: bool,
	activePlayerIx: int,
	players: [2]Maybe(Player),
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
		started = false,
		activePlayerIx = -1,
		players = { nil, nil }
	}
	session.game = createGame()
	
	sync.wait_group_add(&wg, 2)
	waitForClients()
	// startThread(0)
	sync.wait_group_wait(&wg)
}

@(private)
startThread :: proc(userIndex: int) {
	t := thread.create(clientWorker)
	if t != nil {
		t.init_context = context
		t.user_index = userIndex
		thread.start(t)
	}
}

@(private)
clientWorker :: proc(t: ^thread.Thread) {
	onPackage :: proc(header: networking.MessageHeader, payload: string) {
		fmt.printfln("player %s said %s", header.me, header.message)
		if header.payloadSize > 0 do fmt.printfln("payload: %s", payload)
		switch header.message {
			case .JOIN:
				onJoin(header.me)
			case .UPDATE:
			case .SUBMIT:
		}
	}

	player, ok := session.players[t.user_index].?
	assert(ok, "client socket not registered")
	networking.listenBlocking(onPackage, player.socket)

	sync.wait_group_done(&wg)
}

@(private)
waitForClients :: proc() {
	client0 := networking.waitForClient(socket)
	fmt.println("player0 connected")
	session.players[0] = Player { nil, client0 }
	startThread(0)

	client1 := networking.waitForClient(socket)
	fmt.println("player1 connected")
	session.players[1] = Player { nil, client1 }
	startThread(1)
}

@(private)
onJoin :: proc(player: uuid.Identifier) -> bool {
	if session.started {
		fmt.printfln("player %s tried to join active game session", player)
		return false
	}

	player0, player0Connected := session.players[0].?
	if player0Connected && player0.id == nil {
		player0.id = player
		header := networking.MessageHeader {
			message = .UPDATE,
		}
		gridJSON := hex.gridToJSON(session.game.grid)
		networking.say(player0.socket, &header, gridJSON)
		return true
	}

	
	player1, player1Connected := session.players[0].?
	if player1Connected && player1.id == nil {
		player1.id = player
		session.started = true
		// notify both players and start the game
		return true
	}

	assert(false, "session not marked as started but player slots are full")
	return false
}
