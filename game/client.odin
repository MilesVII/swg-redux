package game

import rl "vendor:raylib"

import "core:net"
import "core:strings"
import synchan "core:sync/chan"

import "hex"
import "ui"
import "utils"
import "networking"
import "shaded"

@(private)
EXPLOSION_DURATION_S := f32(1.2)
@(private)
EXPLOSION_HATTRICK_S := f32(0.32)
@(private)
EXPLOSION_CHAINING_S := f32(0.5)
@(private)
FRAG_COUNTER_DISAPPEAR_S := f32(4.2)

ClientStatus :: enum {
	CONNECTING_L,
	LOBBY,
	CONNECTING,
	NOT_FULL,
	WAITING,
	// last turn's explosions are still playing, orders are locked
	RESOLVING,
	PLAYING,
	FINISH,
	DISCONNECTED
}

UIState :: enum {
	DISABLED,
	FREE,
	ORDER_MOV,
	ORDER_BLD,
	ORDER_ATK,
	ORDER_DIG
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
	lethal: bool,
	highlight: bool,
	elapsedTime: f32,
	bonked: bool
}

ClientState :: struct {
	game: GameState,
	serverSocket: net.TCP_Socket,
	// packages from older sockets (e.g. the lobby after joining a game) are ignored
	connection: int,
	activePlayerName: string,
	winnerName: string,
	// message from lobby or server, shown in the HUD
	notice: string,
	status: ClientStatus,
	uiState: UIState,
	orders: OrderSet,
	storedGunOrders: OrderSet,
	myPix: int,
	name: string,
	explosions: [dynamic]Explosion,
	fragCounter: int,
	fragCounterTTS: f32,
	cameraControlsEnabled: bool
}

@(private)
clientState := ClientState {
	status = .CONNECTING,
	uiState = .DISABLED,
	orders = make(OrderSet),
	storedGunOrders = make(OrderSet),
	fragCounter = 0,
	fragCounterTTS = 0
}
// latest update from the server, applied once its explosions finish playing
@(private)
clientUpdateBuffer: Update
@(private)
clientUpdateAnimationsPending: bool = false
@(private)
clientFirstUpdate: bool = true

stripeShader: shaded.StripedShader
shockShader: shaded.ShockShader
sweepShader: shaded.SweepShader
progressShader: shaded.ProgressShader
postfxShader: shaded.PostFXShader
backgroundShader: shaded.BackgroundShader

menuSound: rl.Sound
buttonSound: rl.Sound
placeSound: rl.Sound
hitSound: rl.Sound
fragSound: rl.Sound

vcrFont: rl.Font

postfxEnabled := true

client :: proc(
	name: string,
	framerate: int,
	server: net.Address,
	port: int,
	lobbyEnabled: bool,
	lobbyAddress: net.Address,
	lobbyPort: int,
	lobbyToken: [64]rune
) {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({ .WINDOW_RESIZABLE })
	rl.InitWindow(ui.windowSize.x, ui.windowSize.y, "SWGRedux")
	defer rl.CloseWindow()

	rl.SetExitKey(.KEY_NULL)
	rl.SetTargetFPS(i32(framerate))

	ui.initTextTextures()
	ui.onResize()

	networking.init()
	clientState.name = name

	stripeShader = shaded.createStripedShader()
	shockShader = shaded.createShockShader()
	progressShader = shaded.createProgressShader()
	sweepShader = shaded.createSweepShader()
	postfxShader = shaded.createPostFXShader()
	backgroundShader = shaded.createBackgroundShader()

	rl.InitAudioDevice()
	menuSound =   rl.LoadSound("assets/770201__yuugfr1a__modern-ui-click.wav")
	buttonSound = rl.LoadSound("assets/683048__squirrel_404__click-tick.wav")
	placeSound =  rl.LoadSound("assets/770203__yuugfr1a__modern-ui-hover.wav")
	hitSound =    rl.LoadSound("assets/425728__moogy73__click01.wav")
	fragSound =   rl.LoadSound("assets/658594__javieralejp2__clic-alerta.wav")
	ui.buttonSound = buttonSound

	vcrFont = rl.LoadFontEx("assets/VCR_OSD_MONO.ttf", 16, nil, 0)

	if lobbyEnabled {
		menuState.ngr.token = lobbyToken
		menuState.ngr.name = name
		menuState.lobbyAddress = lobbyAddress

		clientState.status = .CONNECTING_L
		connectToLobby(lobbyAddress, lobbyPort)
	} else {
		connect(server, port)
	}

	for !rl.WindowShouldClose() {
		for synchan.can_recv(networking.rx) {
			data, ok := synchan.recv(networking.rx)
			if ok do processPackage(data)
		}
		utils.updateFlicker()

		if clientState.status != .PLAYING do clientState.uiState = .DISABLED
		ui.updateIO(!clientState.cameraControlsEnabled)
		ui.draw(clientDrawWorld, clientDrawHUD, clientPostFX, clientDrawBackground)
		flushClickQueue()

		if rl.IsKeyPressed(.P) {
			if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) {
				shaded.deletePostFXShader(postfxShader)
				postfxShader = shaded.createPostFXShader()
			} else {
				postfxEnabled = !postfxEnabled
			}
		}

		free_all(context.temp_allocator)
	}
}

@(private="file")
clientPostFX :: proc(tex: rl.RenderTexture2D) {
	if postfxEnabled {
		rl.BeginTextureMode(tex)
		rl.BeginShaderMode(postfxShader.shader)
		postfxShader.state.windowSize = ui.windowSizeF()
		shaded.updatePostFXShader(&postfxShader)
		rl.DrawTextureRec(
			tex.texture,
			{ 0, 0, f32(tex.texture.width), f32(-tex.texture.height) },
			{ 0, 0 }, rl.WHITE
		)
		rl.EndShaderMode()
		rl.EndTextureMode()
	}

	for bonk in clientState.explosions {
		if !bonk.lethal do continue
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

	if clientState.uiState != .DISABLED {
		ui.drawCellBorder(ui.pointedCell, .2, rl.WHITE)
	}

	for &player, pix in clientState.game.players {
		for &unit in player.units {
			ordered := unit.id in clientState.orders
			highlight := clientState.status == .PLAYING && pix == clientState.myPix && !ordered
			unitHovered := drawUnit(
				unit.position,
				unit.type,
				unit.gold,
				player.color,
				highlight
			)
			if pix != clientState.myPix do continue

			utils.setCursorHover(unitHovered)

			shouldSelect :=
				unitHovered &&
				clientState.uiState == .FREE &&
				selectedUnitId != unit.id &&
				rl.IsMouseButtonPressed(.LEFT)

			if shouldSelect do postponeClick(SelectAction(unit.id))
		}
	}

	if clientUpdateAnimationsPending {
		for &bonk in clientState.explosions {
			if bonk.elapsedTime == 0 do rl.PlaySound(hitSound)
			bonk.elapsedTime += rl.GetFrameTime()
			ui.drawExplosion(bonk.at, bonk.elapsedTime / (EXPLOSION_HATTRICK_S * 2.0), &sweepShader)
			onGrid := hex.isWithinGrid(bonk.at, clientState.game.grid.radius)

			if onGrid && !bonk.bonked && bonk.elapsedTime > EXPLOSION_HATTRICK_S {
				bonk.bonked = true
				if bonk.highlight && bonk.lethal {
					rl.PlaySound(fragSound)
					clientState.fragCounter += 1
				}

				uix, pix, found := findUnitAt(&clientState.game, bonk.at)
				if found {
					unit := &clientState.game.players[pix].units[uix]
					if unit.type == .TONK && unit.gold > 1 do unit.gold -= 1
					else do unordered_remove(&clientState.game.players[pix].units, uix)
				}
			}
			if bonk.elapsedTime < EXPLOSION_CHAINING_S do break
		}

		if allExplosionsBonked() && clientState.fragCounterTTS == 0 {
			clientState.fragCounterTTS = FRAG_COUNTER_DISAPPEAR_S
		}
		for i := len(clientState.explosions) - 1; i >= 0; i -= 1 {
			if clientState.explosions[i].elapsedTime >= EXPLOSION_DURATION_S {
				ordered_remove(&clientState.explosions, i)
			}
		}
		if len(clientState.explosions) == 0 {
			applyBufferedUpdate()
			clientUpdateAnimationsPending = false
		}
	}
}

@(private)
connect :: proc(to: net.Address, port: int) -> bool {
	socket, ok := networking.dial(to, port)
	if !ok {
		clientState.status = .DISCONNECTED
		setNotice("CAN'T REACH GAME SERVER")
		return false
	}
	clientState.serverSocket = socket
	clientState.connection = networking.listen(socket)

	header := networking.MessageHeader {
		message = .JOIN,
		me = utils.stringToBadge(clientState.name)
	}
	networking.say(clientState.serverSocket, &header)
	return true
}

@(private="file")
connectToLobby :: proc(to: net.Address, port: int) {
	socket, ok := networking.dial(to, port)
	if !ok {
		clientState.status = .DISCONNECTED
		setNotice("CAN'T REACH LOBBY")
		return
	}
	clientState.serverSocket = socket
	clientState.connection = networking.listen(socket)
}

// takes ownership of a heap string, copies literals
@(private)
setNotice :: proc(notice: string, owned := false) {
	delete(clientState.notice)
	clientState.notice = owned ? notice : strings.clone(notice)
}

@(private="file")
processPackage :: proc(p: networking.Package) {
	defer delete(p.payload)
	if p.connection != clientState.connection do return

	switch p.header.message {
		case .CONNECTED:
		case .DISCONNECTED:
			networking.hang(p.socket)
			clientState.status = .DISCONNECTED
			setNotice("CONNECTION LOST")
		case .GENERAL:
			// notice from lobby or server
			notice: string
			if decode(p.payload, &notice) do setNotice(notice, owned = true)
			// lobby only sends notices when a game request failed
			if clientState.status == .LOBBY do menuState.ngrSent = false
		case .JOIN:
			// lobby offers session list
			if clientState.status != .CONNECTING_L && clientState.status != .LOBBY do break
			clientState.status = .LOBBY
			clearSessions()
			if !decode(p.payload, &menuState.sessions) do clearSessions()
		case .UPDATE:
			// game update from server
			onUpdate(p.payload)
		case .ORDERS: // ignored
	}
}

@(private="file")
onUpdate :: proc(payload: []u8) {
	// finish whatever the previous update was still animating,
	// its explosions must not replay against the new state
	if clientUpdateAnimationsPending {
		clear(&clientState.explosions)
		applyBufferedUpdate()
		clientUpdateAnimationsPending = false
		clientState.fragCounter = 0
		clientState.fragCounterTTS = 0
	}

	// everything owned by the buffer was handed over by applyBufferedUpdate
	clientUpdateBuffer = {}
	if !decode(payload, &clientUpdateBuffer) {
		deleteState(clientUpdateBuffer.gameState)
		clientUpdateBuffer = {}
		return
	}
	defer {
		delete(clientUpdateBuffer.explosions)
		clientUpdateBuffer.explosions = nil
	}

	rl.PlaySound(menuSound)
	clientState.cameraControlsEnabled = true
	clear(&clientState.orders)
	setNotice("")
	clientState.myPix = clientUpdateBuffer.meta.yourId

	if clientFirstUpdate {
		applyBufferedUpdate()
		if clientState.myPix >= 0 && clientState.myPix < len(clientState.game.players) {
			units := clientState.game.players[clientState.myPix].units
			if len(units) > 0 do ui.camera.target = hex.axialToWorld(units[0].position)
		}

		clientFirstUpdate = false
	} else if len(clientUpdateBuffer.explosions) > 0 {
		// keep orders locked until the explosions land and the new state is applied
		clientUpdateAnimationsPending = true
		clientState.status = .RESOLVING
	} else {
		applyBufferedUpdate()
	}

	for bonk in clientUpdateBuffer.explosions {
		append(
			&clientState.explosions,
			Explosion {
				at = bonk.position,
				lethal = bonk.lethal,
				highlight = bonk.pix == 1,
				elapsedTime = 0,
				bonked = false
			}
		)
	}
}

// moves state and captions out of the buffer and updates the status
@(private="file")
applyBufferedUpdate :: proc() {
	deleteState(clientState.game)
	clientState.game = clientUpdateBuffer.gameState
	clientUpdateBuffer.gameState = {}

	delete(clientState.activePlayerName)
	clientState.activePlayerName = clientUpdateBuffer.meta.currentPlayerBadge
	clientUpdateBuffer.meta.currentPlayerBadge = ""

	delete(clientState.winnerName)
	clientState.winnerName = clientUpdateBuffer.winnerBadge
	clientUpdateBuffer.winnerBadge = ""

	applyStoredGunOrders()
	promoteStatusChange()
}

@(private="file")
promoteStatusChange :: proc() {
	switch {
		case clientUpdateBuffer.gameOver:
			clientState.status = .FINISH
		case !clientUpdateBuffer.gameStarted:
			clientState.status = .NOT_FULL
		case clientUpdateBuffer.meta.activeIsYou:
			clientState.status = .PLAYING
			clientState.uiState = .FREE
		case:
			clientState.status = .WAITING
	}
}

@(private)
clientSayOrders :: proc() {
	header := networking.MessageHeader {
		message = .ORDERS,
		me = utils.stringToBadge(clientState.name)
	}

	networking.say(clientState.serverSocket, &header, encode(clientState.orders))
	clear(&clientState.storedGunOrders)

	for unitId in clientState.orders {
		unit, found := findUnitById(clientState.game.players[clientState.myPix].units[:], unitId)
		if found && unit.type == .GUN {
			clientState.storedGunOrders[unitId] = clientState.orders[unitId]
		}
	}
}

@(private="file")
applyStoredGunOrders :: proc () {
	if clientState.myPix < 0 || clientState.myPix >= len(clientState.game.players) do return
	for unitId in clientState.storedGunOrders {
		_, found := findUnitById(clientState.game.players[clientState.myPix].units[:], unitId)
		if found {
			clientState.orders[unitId] = clientState.storedGunOrders[unitId]
		}
	}
}

@(private)
allExplosionsBonked :: proc() -> bool {
	for bonk in clientState.explosions do if !bonk.bonked do return false
	return true
}
