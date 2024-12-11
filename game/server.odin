package game

import "core:fmt"
import "core:net"
import "core:thread"
// import "core:sync"

import "networking"
import "core:encoding/uuid"

socket : net.TCP_Socket
session : Session

Message :: enum { JOIN, UPDATE_GRID, UPDATE_UNIT, SUBMIT }
GamePackage :: struct {
	message: Message,
	me: uuid.Identifier,
}

Session :: struct {
	started: bool,
	activePlayerIx: int,
	players: [2]Maybe(uuid.Identifier)
}

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
	game := createGame()
	
	listenToClient()
	// startThread(0)
}

// @(private)
// startThread :: proc(userIndex: int) {
// 	t := thread.create(listenToClient)
// 	if t != nil {
// 		t.init_context = context
// 		t.user_index = userIndex
// 		thread.start(t)
// 	}
// }

@(private)
listenToClient :: proc(/* t: ^thread.Thread */) {
	onPackage :: proc(data: GamePackage) {
		switch data.message {
			case .JOIN:
				onJoin(data.me)
			case .UPDATE_GRID:
			case .UPDATE_UNIT:
			case .SUBMIT:
		}
	}

	networking.listen(GamePackage, onPackage, socket)
}

@(private)
onJoin :: proc(player: uuid.Identifier) -> bool {
	if session.started {
		fmt.printfln("player %s tried to join active game session", player)
		return false
	}

	if session.players[0] == nil {
		session.players[0] = player
		return true
	}
	if session.players[1] == nil {
		session.players[1] = player
		session.started = true
		// notify both players and start the game
		return true
	}

	assert(false, "session not marked as started but player slots are full")
	return false
}
