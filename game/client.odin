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
	// no player name yet, see drawNamePrompt
	NAMING,
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

// MCVs may queue two builds or two digs per turn, every other unit one order
MAX_UNIT_ORDERS :: 2

OrderList :: struct {
	items: [MAX_UNIT_ORDERS]Order,
	count: int
}

// orders of every unit by unit id
OrderSet :: map[int]OrderList

oneOrder :: proc(order: Order) -> OrderList {
	return { items = { 0 = order }, count = 1 }
}

// the orders of a list, safe with counts that came over the network
listedOrders :: proc(list: ^OrderList) -> []Order {
	return list.items[:clamp(list.count, 0, MAX_UNIT_ORDERS)]
}

// whether a list may hold more than one order: an MCV with only builds or only digs
multipleOrdersAllowed :: proc(unitType: GameUnitType, orders: []Order) -> bool {
	if unitType != .MCV || len(orders) == 0 do return false
	kind := orders[0].type
	if kind != .BUILD && kind != .DIG do return false
	for order in orders do if order.type != kind do return false
	return true
}

// whether `order` can join the unit's queued orders instead of replacing them
canQueueOrder :: proc(unitType: GameUnitType, list: OrderList, order: Order) -> bool {
	list := list
	if list.count == 0 || list.count >= MAX_UNIT_ORDERS do return false
	queued := listedOrders(&list)
	extended := make([dynamic]Order, 0, len(queued) + 1, context.temp_allocator)
	append(&extended, ..queued)
	append(&extended, order)
	return multipleOrdersAllowed(unitType, extended[:])
}

// how many queued orders of a kind a unit has
countOrders :: proc(list: OrderList, kind: OrderType) -> int {
	list := list
	count := 0
	for order in listedOrders(&list) do if order.type == kind do count += 1
	return count
}

Explosion :: struct {
	at: hex.Axial,
	lethal: bool,
	highlight: bool,
	elapsedTime: f32,
	// the hit moment has been shown by the view
	impacted: bool,
	// the hit has been applied to the state
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
	// guns keep firing at their last target until told otherwise
	storedGunOrders: map[int]Order,
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
	fragCounter = 0,
	fragCounterTTS = 0
}
// latest update from the server, applied once its explosions finish playing
@(private)
clientUpdateBuffer: Update
// the state that update describes, its grid built on top of the previously received one
@(private)
clientPendingState: GameState
@(private)
clientUpdateAnimationsPending: bool = false
@(private)
clientFirstUpdate: bool = true
// orders of the last turn this client submitted, to tell which of your units fired a shot
@(private)
clientSentOrders: OrderSet

// bumped whenever a new server state replaces the shown one
@(private)
clientStateVersion: int

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
	lobbyToken: [64]rune,
	renderer3D: bool,
	rendererFromCommandLine: bool
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

	for view in CLIENT_VIEWS do if view.init != nil do view.init()
	activeView = renderer3D ? &VIEW_3D : &VIEW_2D

	session = {
		server = server,
		port = port,
		lobbyEnabled = lobbyEnabled,
		lobbyAddress = lobbyAddress,
		lobbyPort = lobbyPort,
		lobbyToken = lobbyToken,
		rendererFromCommandLine = rendererFromCommandLine
	}
	if len(name) > 0 do startClientSession()
	else do clientState.status = .NAMING

	for !rl.WindowShouldClose() {
		for synchan.can_recv(networking.rx) {
			data, ok := synchan.recv(networking.rx)
			if ok do processPackage(data)
		}
		utils.updateFlicker()

		if clientState.status != .PLAYING do clientState.uiState = .DISABLED
		ui.updateWindow()
		handleClientHotkeys()

		inputBlocked := settingsPanelHovered()
		utils.cursorHoverBegin()
		activeView.update(!clientState.cameraControlsEnabled, inputBlocked)
		updateExplosions()
		clientPlanFrame(inputBlocked)
		ui.drawFrame(activeView.scene, clientDrawHUD, clientPostFX)
		utils.cursorHoverEnd()
		flushClickQueue()
		saveClientSettingsIfChanged()

		free_all(context.temp_allocator)
	}

	saveClientSettingsIfChanged(force = true)
	for view in CLIENT_VIEWS do if view.deinit != nil do view.deinit()
}

// where to connect once the player has a name
@(private="file")
session: struct {
	server: net.Address,
	port: int,
	lobbyEnabled: bool,
	lobbyAddress: net.Address,
	lobbyPort: int,
	lobbyToken: [64]rune,
	rendererFromCommandLine: bool
}

// loads the player's settings and connects, needs clientState.name
@(private)
startClientSession :: proc() {
	loadClientSettings(clientState.name, session.rendererFromCommandLine)

	if session.lobbyEnabled {
		menuState.ngr.token = session.lobbyToken
		menuState.ngr.name = clientState.name
		menuState.lobbyAddress = session.lobbyAddress

		clientState.status = .CONNECTING_L
		connectToLobby(session.lobbyAddress, session.lobbyPort)
	} else {
		clientState.status = .CONNECTING
		connect(session.server, session.port)
	}
}

@(private="file")
handleClientHotkeys :: proc() {
	// letters belong to the name being typed
	if clientState.status != .NAMING && rl.IsKeyPressed(.P) {
		if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) {
			// keep the settings, only the code is reloaded
			state := postfxShader.state
			shaded.deletePostFXShader(postfxShader)
			postfxShader = shaded.createPostFXShader()
			postfxShader.state = state
		} else {
			postfxEnabled = !postfxEnabled
		}
	}
	if rl.IsKeyPressed(.LEFT_BRACKET) || rl.IsKeyPressedRepeat(.LEFT_BRACKET) {
		postfxShader.state.intensity = clamp(postfxShader.state.intensity - .1, 0, 1)
	}
	if rl.IsKeyPressed(.RIGHT_BRACKET) || rl.IsKeyPressedRepeat(.RIGHT_BRACKET) {
		postfxShader.state.intensity = clamp(postfxShader.state.intensity + .1, 0, 1)
	}
	if rl.IsKeyPressed(.F1) do settingsOpen = !settingsOpen
	if rl.IsKeyPressed(.F2) do switchView()
}

@(private)
switchView :: proc() {
	activeView = activeView == &VIEW_3D ? &VIEW_2D : &VIEW_3D
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

	shocks := make([dynamic]ScreenShock, context.temp_allocator)
	for bonk in clientState.explosions {
		if !bonk.lethal do continue
		append(&shocks, ScreenShock { activeView.toScreen(bonk.at), bonk.elapsedTime / EXPLOSION_DURATION_S, 1, 1 })
	}
	if activeView.shocks != nil do append(&shocks, ..activeView.shocks())

	for shock in shocks {
		rl.BeginTextureMode(tex)

		shockShader.state.origin = { shock.origin.x, f32(ui.windowSize.y) - shock.origin.y }
		shockShader.state.progress = shock.progress
		shockShader.state.scale = shock.scale
		shockShader.state.strength = shock.strength
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

// explosion timeline shared by all views: each bonk starts once the previous one
// is EXPLOSION_CHAINING_S old, hits after EXPLOSION_HATTRICK_S and expires after
// EXPLOSION_DURATION_S, then the buffered server state is applied
@(private="file")
updateExplosions :: proc() {
	if !clientUpdateAnimationsPending do return

	for &bonk in clientState.explosions {
		if bonk.elapsedTime == 0 {
			rl.PlaySound(hitSound)
			if activeView.onExplosionStart != nil do activeView.onExplosionStart(bonk)
		}
		bonk.elapsedTime += rl.GetFrameTime()

		if !bonk.impacted && bonk.elapsedTime > EXPLOSION_HATTRICK_S {
			bonk.impacted = true
			if activeView.onExplosionImpact != nil do activeView.onExplosionImpact(bonk)
		}

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

	// what applyBufferedUpdate didn't take over
	deleteUpdate(&clientUpdateBuffer)
	if !decode(payload, &clientUpdateBuffer) {
		deleteUpdate(&clientUpdateBuffer)
		return
	}

	// the last received grid is the one shown now, pending animations were just applied
	grid, gridOk := buildGrid(clientState.game.grid, clientUpdateBuffer)
	if !gridOk {
		// out of sync, ask for the whole map and wait for it
		header := networking.MessageHeader { message = .UPDATE, me = utils.stringToBadge(clientState.name) }
		networking.say(clientState.serverSocket, &header)
		deleteUpdate(&clientUpdateBuffer)
		return
	}
	clientPendingState = GameState { players = clientUpdateBuffer.players, grid = grid }
	clientUpdateBuffer.players = nil
	delete(clientUpdateBuffer.cells)
	clientUpdateBuffer.cells = nil
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
			if len(units) > 0 do for view in CLIENT_VIEWS do view.focus(units[0].position)
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
				impacted = false,
				bonked = false
			}
		)
	}
}

// moves state and captions out of the buffer and updates the status
@(private="file")
applyBufferedUpdate :: proc() {
	deleteState(clientState.game)
	clientState.game = clientPendingState
	clientPendingState = {}
	clientStateVersion += 1

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
	clear(&clientSentOrders)
	for unitId, list in clientState.orders do clientSentOrders[unitId] = list
	clear(&clientState.storedGunOrders)

	for unitId, &list in clientState.orders {
		unit, found := findUnitById(clientState.game.players[clientState.myPix].units[:], unitId)
		if found && unit.type == .GUN && list.count > 0 {
			clientState.storedGunOrders[unitId] = list.items[0]
		}
	}
}

@(private="file")
applyStoredGunOrders :: proc () {
	if clientState.myPix < 0 || clientState.myPix >= len(clientState.game.players) do return
	for unitId in clientState.storedGunOrders {
		_, found := findUnitById(clientState.game.players[clientState.myPix].units[:], unitId)
		if found {
			clientState.orders[unitId] = oneOrder(clientState.storedGunOrders[unitId])
		}
	}
}

// your unit whose submitted order produced this explosion, and the cell it aimed at;
// barrage shells scatter around that cell, the aim stays the same
@(private)
findShooter :: proc(bonk: Explosion) -> (unitId: int, aim: hex.Axial, found: bool) {
	if !bonk.highlight do return 0, {}, false
	for id, &list in clientSentOrders {
		for order in listedOrders(&list) {
			#partial switch order.type {
				case .DIREKT:
					if order.target == bonk.at do return id, order.target, true
				case .INDIREKT:
					if hex.distance(order.target, bonk.at) <= 1 do return id, order.target, true
			}
		}
	}
	return 0, {}, false
}

@(private)
allExplosionsBonked :: proc() -> bool {
	for bonk in clientState.explosions do if !bonk.bonked do return false
	return true
}
