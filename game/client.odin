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
import "shaded"

@(private)
EXPLOSION_DURATION_S := f32(2.2)
@(private)
EXPLOSION_HATTRICK_S := f32(1.1)
@(private)
EXPLOSION_CHAINING_S := f32(0.5)

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

Explosion :: struct {
	at: hex.Axial,
	elapsedTime: f32,
	bonked: bool
}

ClientState :: struct {
	game: GameState,
	serverSocket: net.TCP_Socket,
	status: ClientStatus,
	uiState: UIState,
	orders: OrderSet,
	color: rl.Color,
	currentPlayer: int,
	name: string,
	explosions: [dynamic]Explosion
}

@(private)
clientState := ClientState {
	status = .CONNECTING,
	uiState = UIState.DISABLED,
	orders = make(OrderSet)
}
@(private)
clientUpdateBuffer: Update
@(private)
clientUpdateAnimationsPending: bool = false
@(private)
clientFirstUpdate: bool = true

stripeShader: shaded.StripedShader
shockShader: shaded.ShockShader

client :: proc(to: net.Address, port: int, name: string) {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({ .MSAA_4X_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE })
	rl.InitWindow(ui.windowSize.x, ui.windowSize.y, "SWGRedux")
	defer rl.CloseWindow()

	rl.SetExitKey(.KEY_NULL)
	rl.SetTargetFPS(240)
	ui.initTextTextures()
	ui.onResize()

	networking.init()
	clientState.name = name
	connect(to, port)

	stripeShader = shaded.createStripedShader()
	shockShader = shaded.createShockShader()

	for !rl.WindowShouldClose() {
		for synchan.can_recv(networking.rx) {
			data, ok := synchan.recv(networking.rx)
			processPackage(data)
		}

		if clientState.status != .PLAYING do clientState.uiState = .DISABLED
		ui.updateIO()
		ui.draw(clientDrawWorld, clientDrawHUD, clientPostFX)
	}
}

@(private="file")
clientPostFX :: proc(tex: rl.RenderTexture2D) {
	for bonk in clientState.explosions {
		rl.BeginTextureMode(tex)

		origin := hex.axialToWorld(bonk.at)
		screenOrigin := rl.GetWorldToScreen2D(origin, ui.camera)
		shockShader.state.origin = { screenOrigin.x, f32(ui.windowSize.y) - screenOrigin.y }
		shockShader.state.progress = bonk.elapsedTime / EXPLOSION_DURATION_S
		shockShader.state.resolution = { f32(ui.windowSize.x), f32(ui.windowSize.y) }
		shaded.updateShockShader(shockShader, tex)

		rl.BeginShaderMode(shockShader.shader)
		rl.DrawTextureRec(
			tex.texture,
			{ 0, 0, f32(tex.texture.width), f32(-tex.texture.height) },
			{ 0, 0 }, rl.WHITE
		)
		rl.EndShaderMode()
		rl.EndTextureMode()
	}
}

@(private="file")
clientDrawWorld :: proc() {
	if clientState.status == .CONNECTING do return

	ui.drawGrid(clientState.game.grid)

	for &player in clientState.game.players {
		for &unit in player.units {
			unitHovered := drawUnit(unit.position, unit.type, unit.gold, player.color)
			if player.color != clientState.color do continue

			utils.setCursorHover(unitHovered)

			shouldSelect :=
				unitHovered &&
				clientState.uiState == .FREE &&
				(selectedUnit == nil || selectedUnit.id != unit.id) &&
				utils.isClicked()
			
			if shouldSelect do selectedUnit = &unit
		}
	}

	if clientUpdateAnimationsPending {
		for &bonk in clientState.explosions {
			bonk.elapsedTime += ui.drawExplosion(bonk.at, bonk.elapsedTime / EXPLOSION_DURATION_S)
			if !bonk.bonked && bonk.elapsedTime > EXPLOSION_HATTRICK_S {
				bonk.bonked = true
				uix, pix, found := findUnitAt(&clientState.game, bonk.at)
				if found do unordered_remove(&clientState.game.players[pix].units, uix)
			}
			if bonk.elapsedTime < EXPLOSION_CHAINING_S do break
		}
		for i := len(clientState.explosions) - 1; i >= 0; i -= 1 {
			if clientState.explosions[i].elapsedTime >= EXPLOSION_DURATION_S {
				unordered_remove(&clientState.explosions, i)
			}
		}
		if len(clientState.explosions) == 0 {
			promoteStateChange()
			clientUpdateAnimationsPending = false
		}
	}
}

@(private="file")
connect :: proc(to: net.Address, port: int) {
	clientState.serverSocket = networking.dial(to, port)
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
		clientState.color = clientUpdateBuffer.meta.yourColor
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
			clear(&clientState.orders)

			if clientUpdateAnimationsPending {
				promoteStateChange()
				clientUpdateAnimationsPending = false
			}

			decode(p.payload, &clientUpdateBuffer)
			updateCurrentPlayer(clientUpdateBuffer.meta.yourColor)
			promoteStatusChange()

			if clientFirstUpdate {
				promoteStateChange()

				spawn := clientState.game.players[clientState.currentPlayer].units[0].position
				ui.camera.target = hex.axialToWorld(spawn)

				clientFirstUpdate = false
			} else {
				if len(clientUpdateBuffer.explosions) > 0 {
					clientUpdateAnimationsPending = true
				} else do promoteStateChange();
			}

			for bonk in clientUpdateBuffer.explosions {
				append(
					&clientState.explosions,
					Explosion {
						at = bonk,
						elapsedTime = 1,
						bonked = false
					}
				)
			}
		case .ORDERS: // ignored
	}
}

@(private="file")
promoteStateChange :: proc() {
	deleteState(clientState.game)
	clientState.game = clientUpdateBuffer.gameState
}
@(private="file")
promoteStatusChange :: proc() {
	clientState.status = clientUpdateBuffer.meta.activeIsYou ? .PLAYING : .WAITING
	if clientUpdateBuffer.meta.activeIsYou do clientState.uiState = .FREE
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
