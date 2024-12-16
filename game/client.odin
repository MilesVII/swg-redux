package game

import rl "vendor:raylib"

import "core:fmt"
import "core:net"
import "core:thread"
import "core:encoding/uuid"
import "core:crypto"
import "core:math"

import "hex"
import "ui"
import "utils"
import "networking"

ClientStatus :: enum {
	CONNECTING, LOBBY, WAITING, PLAYING, FINISH
}

ClientState :: struct {
	game: GameState,
	serverSocket: net.TCP_Socket,
	status: ClientStatus
}

@(private="file")
clientState := ClientState {
	status = .CONNECTING
}

client :: proc() {
	rl.InitWindow(ui.WINDOW.x, ui.WINDOW.y, "SWGRedux")
	defer rl.CloseWindow()

	rl.SetTargetFPS(240)

	me := connect()

	for !rl.WindowShouldClose() {
		ui.updateIO()
		ui.draw(clientDrawWorld, clientDrawHUD)
	}
}

@(private="file")
clientDrawWorld :: proc() {
	if clientState.status == .CONNECTING do return

	ui.drawGrid(clientState.game.grid)

	for player in clientState.game.players {
		for unit in player.units {
			drawUnit(unit.position, unit.type, player.color)
		}
	}
}

@(private="file")
clientDrawHUD :: proc() {
	// fmt.ctprint(ui.pointedCell)
	switch clientState.status {
		case .CONNECTING: rl.DrawText("Connecting to server", 4, 4, 10, rl.BLACK)
		case .LOBBY:      rl.DrawText("Waiting for players to join", 4, 4, 10, rl.BLACK)
		case .PLAYING:    rl.DrawText("Your turn", 4, 4, 10, rl.RED)
		case .WAITING:    rl.DrawText("Waiting for other players", 4, 4, 10, rl.BLACK)
		case .FINISH:     rl.DrawText("Game over", 4, 4, 10, rl.BLACK)
	}
	framerate := math.round(1.0 / rl.GetFrameTime())
	rl.DrawText(fmt.ctprint(framerate), 4, 16, 10, rl.RED)
}

@(private="file")
connect :: proc() -> uuid.Identifier {
	context.random_generator = crypto.random_generator()
	clientState.serverSocket = networking.dial()
	me := uuid.generate_v4()

	startListening()

	header := networking.MessageHeader {
		message = .JOIN,
		me = me
	}
	networking.say(clientState.serverSocket, &header)

	return me
}

@(private="file")
startListening :: proc() {
	listener :: proc(t: ^thread.Thread) {
		onPackage :: proc(_: net.TCP_Socket, header: networking.MessageHeader, payload: string) {
			fmt.printfln("server said %s: %s bytes", header.message, len(payload))
			switch header.message {
				case .JOIN: // ignored
				case .UPDATE:
					deleteState(clientState.game)
					clientState.game = createGame()
					decode(payload, &clientState.game)
					clientState.status = .LOBBY
				case .ORDERS: // ignored
				case .TURN: 
					turnMessage: TurnMessage
					decode(payload, &turnMessage)
					clientState.status = turnMessage.activeIsYou ? .PLAYING : .WAITING
			}
		}

		networking.listenBlocking(onPackage, clientState.serverSocket)
	}

	t := thread.create(listener)
	if t != nil {
		t.init_context = context
		t.user_index = 0
		thread.start(t)
	}
}

