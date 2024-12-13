package game

import rl "vendor:raylib"

import "core:fmt"
import "core:net"
import "core:thread"
import "core:encoding/uuid"
import "core:crypto"

import "hex"
import "ui"
import "utils"
import "networking"

ClientStatus :: enum {
	CONNECTING, LOBBY, WAITING, PLAYING, FINISH
}

ClientState :: struct {
	grid: GameGrid,
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
	// if clientState.status != .CONNECTING do drawGrid()
	
}

@(private="file")
clientDrawHUD :: proc() {

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
				case .JOIN:
				case .UPDATE:
					clientState.grid = hex.jsonToGrid(payload)
					clientState.status = .LOBBY
				case .SUBMIT:
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

