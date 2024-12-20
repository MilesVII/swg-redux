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

UIState :: enum {
	DISABLED, FREE, ORDER_MOV, ORDER_BLD, ORDER_ATK, ORDER_DIG
}

OrderType :: enum {
	DIREKT, INDIREKT, BUILD, DIG, MOVE
}

Order :: struct {
	type: OrderType,
	target: hex.Axial
}

ClientState :: struct {
	game: GameState,
	serverSocket: net.TCP_Socket,
	status: ClientStatus,
	uiState: UIState,
	orders: map[int]Order,
	color: rl.Color,
	currentPlayer: int
}

@(private)
clientState := ClientState {
	status = .CONNECTING,
	uiState = UIState.DISABLED
}
@(private="file")
updateBuffer: Update

client :: proc() {
	rl.InitWindow(ui.WINDOW.x, ui.WINDOW.y, "SWGRedux")
	defer rl.CloseWindow()

	rl.SetTargetFPS(240)
	ui.initTextTextures()

	me := connect()

	for !rl.WindowShouldClose() {
		if clientState.status != .PLAYING do clientState.uiState = .DISABLED
		ui.updateIO()
		ui.draw(clientDrawWorld, clientDrawHUD)
	}
}

@(private="file")
clientDrawWorld :: proc() {
	if clientState.status == .CONNECTING do return

	ui.drawGrid(clientState.game.grid)

	for &player in clientState.game.players {
		for &unit in player.units {
			unitHovered := drawUnit(unit.position, unit.type, player.color)
			if player.color != clientState.color do return

			utils.setCursorHover(unitHovered)
			if clientState.uiState == .FREE && rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
				selectedUnit = &unit
			}
		}
	}
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
			updateCurrentPlayer :: proc(color: rl.Color) {
				clientState.color = updateBuffer.meta.yourColor
				for &player, index in clientState.game.players {
					if player.color == color {
						clientState.currentPlayer = index
						return
					}
				}
			}

			switch header.message {
				case .JOIN: // ignored
				case .UPDATE:
					deleteState(clientState.game)
					decode(payload, &updateBuffer)
					clientState.game = updateBuffer.gameState

					updateCurrentPlayer(updateBuffer.meta.yourColor)

					if clientState.status == .CONNECTING {
						spawn := clientState.game.players[clientState.currentPlayer].units[0].position
						ui.camera.target = hex.axialToWorld(spawn)
					}
					clientState.status = updateBuffer.meta.activeIsYou ? .PLAYING : .WAITING
					if updateBuffer.meta.activeIsYou do clientState.uiState = .FREE
				case .ORDERS: // ignored
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
