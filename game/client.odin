package game

import rl "vendor:raylib"

import "core:fmt"
import "core:net"
import "core:thread"
import "core:unicode/utf8"
import "core:crypto"
import "core:math"
import synchan "core:sync/chan"

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
	target: hex.Axial,
	targetUnitType: GameUnitType
}

OrderSet :: map[int]Order

ClientState :: struct {
	game: GameState,
	serverSocket: net.TCP_Socket,
	status: ClientStatus,
	uiState: UIState,
	orders: OrderSet,
	color: rl.Color,
	currentPlayer: int,
	name: string
}

@(private)
clientState := ClientState {
	status = .CONNECTING,
	uiState = UIState.DISABLED,
	orders = make(OrderSet)
}
@(private="file")
updateBuffer: Update

client :: proc(name: string) {
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(ui.WINDOW.x, ui.WINDOW.y, "SWGRedux")
	defer rl.CloseWindow()

	rl.SetTargetFPS(240)
	ui.initTextTextures()

	networking.init()
	clientState.name = name
	connect()

	for !rl.WindowShouldClose() {
		for synchan.can_recv(networking.rx) {
			data, ok := synchan.recv(networking.rx)
			processPackage(data)
		}

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
			if player.color != clientState.color do continue

			utils.setCursorHover(unitHovered)
			if clientState.uiState == .FREE && rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
				selectedUnit = &unit
			}
		}
	}
}

@(private="file")
connect :: proc() {
	context.random_generator = crypto.random_generator()
	clientState.serverSocket = networking.dial()

	startListening()

	header := networking.MessageHeader {
		message = .JOIN,
		me = utils.stringToBadge(clientState.name)
	}
	networking.say(clientState.serverSocket, &header)
}

@(private="file")
processPackage :: proc(p: networking.Package) {
	updateCurrentPlayer :: proc(color: rl.Color) {
		clientState.color = updateBuffer.meta.yourColor
		for &player, index in clientState.game.players {
			if player.color == color {
				clientState.currentPlayer = index
				return
			}
		}
	}

	switch p.header.message {
		case .JOIN: // ignored
		case .UPDATE:
			deleteState(clientState.game)
			clear(&clientState.orders)

			decode(p.payload, &updateBuffer)
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

@(private="file")
startListening :: proc() {
	listener :: proc(t: ^thread.Thread) {
		networking.listenBlocking(networking.tx, clientState.serverSocket)
	}

	t := thread.create(listener)
	if t != nil {
		t.init_context = context
		t.user_index = 0
		thread.start(t)
	}
}

@(private)
clientSayOrders :: proc() {
	header := networking.MessageHeader {
		message = .ORDERS,
		me = utils.stringToBadge(clientState.name)
	}

	networking.say(clientState.serverSocket, &header, encode(clientState.orders))
}
