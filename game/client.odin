package game

import rl "vendor:raylib"

import "core:net"
import "core:strings"
import "core:math/rand"
import synchan "core:sync/chan"

import "hex"
import "ui"
import "utils"
import "networking"
import "shaded"

EXPLOSION_DURATION_S := f32(1.2)
@(private)
EXPLOSION_HATTRICK_S := f32(0.32)
// the next explosion starts this long after the previous one, picked at random per explosion
EXPLOSION_GAP_RANGE := [2]f32 { .3, .7 }
// a whole salvo plays within this long, gaps are compressed to fit
EXPLOSIONS_MAX_S := f32(10)
EXPLOSION_MIN_GAP_S := f32(.05)
// the hit sound varies this much around its normal pitch
EXPLOSION_PITCH_RANGE := [2]f32 { .92, 1.08 }
@(private)
FRAG_COUNTER_DISAPPEAR_S := f32(4.2)

ClientStatus :: enum {
	// no player name yet, see drawNamePrompt
	NAMING,
	CONNECTING_L,
	LOBBY,
	CONNECTING,
	NOT_FULL,
	// a team game waiting for everyone to pick a team, see drawTeamPicker
	TEAMS,
	WAITING,
	// no MCV left while the game goes on, watching only
	LOST,
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
	bonked: bool,
	// seconds after this one starts before the next may, see scheduleExplosions
	gap: f32,
	pitch: f32,
	// tile side the shell came from, -1 when unknown, see ExplosionBufferEntry
	side: int
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
	cameraControlsEnabled: bool,
	// GetTime() when the current turn runs out, 0 without a turn timer
	turnDeadline: f64,
	// orders went out this turn, SUBMIT is gone until the next update
	ordersSent: bool,
	target: ConnectionTarget,
	targetAddress: net.Address,
	targetPort: int,
	// the dialAsync attempt in progress, 0 when not dialing
	dialTicket: int,
	// GetTime() of the next reconnection attempt, 0 when none is due
	retryAt: f64,
	lastHeard: f64,
	lastPing: f64,
	// asking whether to leave the game for the lobby
	leavePrompt: bool,
	winnerTeam: int,
	// per slot, from the last update
	playerNames: []string,
	playersReady: []bool
}

// before a team game starts: ask for a team, or confirm the current one
@(private)
sendTeamChoice :: proc(team: int, ready: bool) {
	header := networking.MessageHeader { message = .TEAM, me = utils.stringToBadge(clientState.name) }
	networking.say(clientState.serverSocket, &header, encode(TeamChoice { team, ready }))
}

// a red sector flashing once outside the side of a hit tile that faces the gun that fired
CounterBatterySign :: struct {
	at: hex.Axial,
	side: int,
	start: f64
}
@(private)
counterBatterySigns: [dynamic]CounterBatterySign
COUNTER_BATTERY_S :: 1.1

// fades shapes in and out without blending, see shaders/dither-fs.glsl
@(private)
ditherShader: rl.Shader

// coverage of a sign over its short life: a quick flash, then a dithered fade
@(private)
counterBatteryCoverage :: proc(sign: CounterBatterySign) -> f32 {
	t := f32((rl.GetTime() - sign.start) / COUNTER_BATTERY_S)
	if t < 0 || t >= 1 do return 0
	if t < .1 do return t / .1
	fade := 1 - (t - .1) / .9
	return fade * fade
}

// quad outside the tile edge facing `side`, widening away from the tile
@(private)
counterBatteryQuad :: proc(sign: CounterBatterySign) -> [4]rl.Vector2 {
	center := hex.axialToWorld(sign.at)
	toward := rl.Vector2Normalize(hex.axialToWorld(hex.AXIAL_NBS[sign.side]))
	inner := hex.vertesex(sign.at, 1.06)
	outer := hex.vertesex(sign.at, 1.9)
	edge := 0
	best := min(f32)
	for k in 0..<6 {
		middle := (inner[k] + inner[(k + 1) % 6]) * .5 - center
		if d := rl.Vector2DotProduct(rl.Vector2Normalize(middle), toward); d > best {
			best = d
			edge = k
		}
	}
	next := (edge + 1) % 6
	return { inner[edge], outer[edge], outer[next], inner[next] }
}

@(private="file")
pruneCounterBatterySigns :: proc() {
	for i := len(counterBatterySigns) - 1; i >= 0; i -= 1 {
		if rl.GetTime() - counterBatterySigns[i].start >= COUNTER_BATTERY_S do ordered_remove(&counterBatterySigns, i)
	}
}

// submitted this long before the deadline, the server allows a few seconds more
AUTO_SUBMIT_LEAD :: 1.0

// orders can be prepared on your turn and while others play theirs
// whether there's a game map to draw, the menus and connecting screens only show the backdrop
@(private)
showsGame :: proc() -> bool {
	#partial switch clientState.status {
		case .NAMING, .CONNECTING_L, .LOBBY, .CONNECTING: return false
	}
	return clientState.target == .SERVER
}

@(private)
canPlanOrders :: proc() -> bool {
	return clientState.status == .PLAYING || clientState.status == .WAITING
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

	ditherShader = rl.LoadShader(nil, "shaders/dither-fs.glsl")
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

		if !canPlanOrders() do clientState.uiState = .DISABLED
		// out of time: send whatever is queued
		if clientState.status == .PLAYING && !clientState.ordersSent && clientState.turnDeadline > 0 {
			if rl.GetTime() >= clientState.turnDeadline - AUTO_SUBMIT_LEAD do clientSayOrders()
		}
		ui.updateWindow()
		handleClientHotkeys()

		maintainConnection()
		inputBlocked := settingsPanelHovered() || clientState.leavePrompt
		utils.cursorHoverBegin()
		activeView.update(!clientState.cameraControlsEnabled, inputBlocked)
		updateExplosions()
		pruneCounterBatterySigns()
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

		connectTo(.LOBBY, session.lobbyAddress, session.lobbyPort, true)
	} else {
		connectTo(.SERVER, session.server, session.port, true)
	}
}

@(private="file")
handleClientHotkeys :: proc() {
	// esc leaves a game for the lobby: right away once it's over, after asking while it runs;
	// with a unit selected it belongs to the ABORT button
	if clientState.leavePrompt {
		if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) do leaveToLobby()
		else if rl.IsKeyPressed(.ESCAPE) do clientState.leavePrompt = false
	} else if rl.IsKeyPressed(.ESCAPE) && canLeaveToLobby() && getSelectedUnit() == nil {
		if clientState.status == .FINISH do leaveToLobby()
		else do clientState.leavePrompt = true
	}

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
// is its gap old, hits after EXPLOSION_HATTRICK_S and expires after
// EXPLOSION_DURATION_S, then the buffered server state is applied
@(private="file")
updateExplosions :: proc() {
	if !clientUpdateAnimationsPending do return

	for &bonk in clientState.explosions {
		if bonk.elapsedTime == 0 {
			rl.SetSoundPitch(hitSound, bonk.pitch)
			rl.PlaySound(hitSound)
			if activeView.onExplosionStart != nil do activeView.onExplosionStart(bonk)
		}
		bonk.elapsedTime += rl.GetFrameTime()

		if !bonk.impacted && bonk.elapsedTime > EXPLOSION_HATTRICK_S {
			bonk.impacted = true
			if activeView.onExplosionImpact != nil do activeView.onExplosionImpact(bonk)
			if bonk.side >= 0 do append(&counterBatterySigns, CounterBatterySign { bonk.at, bonk.side, rl.GetTime() })
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
		if bonk.elapsedTime < bonk.gap do break
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

// what the client talks to, kept to reconnect after the connection drops
ConnectionTarget :: enum { NONE, LOBBY, SERVER }

// seconds between reconnection attempts
RECONNECT_S :: 3.0
// seconds between heartbeats, and of silence after which the connection counts as lost
PING_INTERVAL_S :: 5.0
SILENCE_TIMEOUT_S :: 15.0

// starts dialing in the background, see onConnected and onDialFailed;
// `initial` shows the connecting status, reconnects keep the last map on screen
@(private)
connectTo :: proc(target: ConnectionTarget, address: net.Address, port: int, initial: bool) {
	clientState.target = target
	clientState.targetAddress = address
	clientState.targetPort = port
	clientState.retryAt = 0
	if initial do clientState.status = target == .LOBBY ? .CONNECTING_L : .CONNECTING
	clientState.dialTicket = networking.dialAsync(address, port)
}

@(private="file")
onConnected :: proc(p: networking.Package) {
	clientState.dialTicket = 0
	clientState.serverSocket = p.socket
	clientState.connection = p.connection
	clientState.lastHeard = rl.GetTime()
	clientState.lastPing = rl.GetTime()
	setNotice("")

	// game servers know players by name, rejoining continues the game
	if clientState.target == .SERVER {
		header := networking.MessageHeader { message = .JOIN, me = utils.stringToBadge(clientState.name) }
		networking.say(clientState.serverSocket, &header)
	}
}

@(private="file")
scheduleReconnect :: proc(notice: string) {
	clientState.status = .DISCONNECTED
	clientState.retryAt = rl.GetTime() + RECONNECT_S
	setNotice(notice)
}

// retries and heartbeats, called every frame
@(private="file")
maintainConnection :: proc() {
	now := rl.GetTime()

	if clientState.status == .DISCONNECTED && clientState.dialTicket == 0 && clientState.retryAt > 0 && now >= clientState.retryAt {
		connectTo(clientState.target, clientState.targetAddress, clientState.targetPort, false)
	}

	if clientState.connection == 0 do return
	if now - clientState.lastPing >= PING_INTERVAL_S {
		clientState.lastPing = now
		header := networking.MessageHeader { message = .PING }
		networking.say(clientState.serverSocket, &header)
	}
	// a dead link doesn't always close the socket, silence does the job
	if now - clientState.lastHeard > SILENCE_TIMEOUT_S {
		clientState.lastHeard = now
		networking.kick(clientState.serverSocket)
	}
}

// ends the current game and goes back to the lobby's menu
@(private)
leaveToLobby :: proc() {
	if !session.lobbyEnabled do return
	resetGameState()
	clearSessions()
	menuState.status = .MAIN
	menuState.index = 0
	menuState.ngrSent = false

	// the listener reports DISCONNECTED, which closes the socket
	if clientState.connection != 0 do networking.kick(clientState.serverSocket)
	clientState.connection = 0
	connectTo(.LOBBY, session.lobbyAddress, session.lobbyPort, true)
}

// from the lobby menu into one of its games
@(private)
joinLobbyGame :: proc(port: int) {
	if clientState.connection != 0 do networking.kick(clientState.serverSocket)
	clientState.connection = 0
	connectTo(.SERVER, session.lobbyAddress, port, true)
}

@(private)
canLeaveToLobby :: proc() -> bool {
	return session.lobbyEnabled && clientState.target == .SERVER
}

// forgets everything about the current game
@(private="file")
resetGameState :: proc() {
	if clientUpdateAnimationsPending {
		deleteState(clientPendingState)
		clientPendingState = {}
		clientUpdateAnimationsPending = false
	}
	deleteUpdate(&clientUpdateBuffer)
	deleteState(clientState.game)
	clientState.game = {}
	clientStateVersion += 1

	clear(&clientState.orders)
	clear(&clientState.storedGunOrders)
	clear(&clientSentOrders)
	clear(&clientState.explosions)
	clear(&counterBatterySigns)
	clientFirstUpdate = true
	selectedUnitId = NO_SELECTION
	clientState.uiState = .DISABLED
	clientState.cameraControlsEnabled = false

	delete(clientState.activePlayerName)
	clientState.activePlayerName = ""
	delete(clientState.winnerName)
	clientState.winnerName = ""
	clientState.turnDeadline = 0
	clientState.ordersSent = false
	clientState.fragCounter = 0
	clientState.fragCounterTTS = 0
	clientState.leavePrompt = false
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

	// results of dialing: only the latest attempt counts, late ones are dropped
	if p.header.message == .CONNECTED || p.header.message == .DIAL_FAILED {
		current := p.ticket != 0 && p.ticket == clientState.dialTicket
		if p.header.message == .CONNECTED {
			if current do onConnected(p)
			else do networking.kick(p.socket)
		} else if current {
			clientState.dialTicket = 0
			scheduleReconnect(clientState.target == .LOBBY ? "CAN'T REACH LOBBY, RETRYING" : "CAN'T REACH GAME SERVER, RETRYING")
		}
		return
	}
	// sockets are closed here only, whichever connection they belonged to
	if p.header.message == .DISCONNECTED do networking.hang(p.socket)

	if p.connection != clientState.connection do return
	clientState.lastHeard = rl.GetTime()

	switch p.header.message {
		case .CONNECTED, .DIAL_FAILED:
		case .PING:
		case .TEAM:
		case .DISCONNECTED:
			clientState.connection = 0
			// a finished game has nothing to come back to
			if clientState.status == .FINISH {
				setNotice("CONNECTION CLOSED")
				break
			}
			scheduleReconnect("CONNECTION LOST, RETRYING")
		case .GENERAL:
			// notice from lobby or server
			notice: string
			if decode(p.payload, &notice) do setNotice(notice, owned = true)
			// lobby only sends notices when a game request failed
			if clientState.status == .LOBBY do menuState.ngrSent = false
		case .JOIN:
			// lobby offers session list
			if clientState.target != .LOBBY do break
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
	clientPendingState = GameState { players = clientUpdateBuffer.players, grid = grid, teamSize = clientUpdateBuffer.teamSize }
	clientUpdateBuffer.players = nil
	delete(clientUpdateBuffer.cells)
	clientUpdateBuffer.cells = nil
	defer {
		delete(clientUpdateBuffer.explosions)
		clientUpdateBuffer.explosions = nil
	}

	clientState.cameraControlsEnabled = true
	// queued orders survive other players' turns, they're cleared when submitted
	clientState.ordersSent = false
	meta := clientUpdateBuffer.meta
	running := meta.turnLimit > 0 && clientUpdateBuffer.gameStarted && !clientUpdateBuffer.gameOver
	clientState.turnDeadline = running ? rl.GetTime() + f64(meta.turnTimeLeft) : 0
	setNotice("")
	previousPix := clientState.myPix
	clientState.myPix = clientUpdateBuffer.meta.yourId

	if clientFirstUpdate {
		applyBufferedUpdate()
		focusOnOwnUnits()
		clientFirstUpdate = false
	} else if len(clientUpdateBuffer.explosions) > 0 {
		// keep orders locked until the explosions land and the new state is applied
		clientUpdateAnimationsPending = true
		clientState.status = .RESOLVING
	} else {
		applyBufferedUpdate()
	}

	// switching teams before the start moves the player to another spawn
	if previousPix != clientState.myPix && !clientUpdateBuffer.gameStarted do focusOnOwnUnits()

	for bonk in clientUpdateBuffer.explosions {
		append(
			&clientState.explosions,
			Explosion {
				at = bonk.position,
				lethal = bonk.lethal,
				highlight = bonk.pix == 1,
				side = bonk.side,
				elapsedTime = 0,
				impacted = false,
				bonked = false
			}
		)
	}
	scheduleExplosions(clientState.explosions[:])
}

// random gaps and pitches, with the gaps compressed so the salvo fits EXPLOSIONS_MAX_S
scheduleExplosions :: proc(explosions: []Explosion) {
	if len(explosions) == 0 do return
	total := f32(0)
	for &bonk, i in explosions {
		bonk.gap = EXPLOSION_GAP_RANGE[0] + rand.float32() * (EXPLOSION_GAP_RANGE[1] - EXPLOSION_GAP_RANGE[0])
		bonk.pitch = EXPLOSION_PITCH_RANGE[0] + rand.float32() * (EXPLOSION_PITCH_RANGE[1] - EXPLOSION_PITCH_RANGE[0])
		// the last one's gap leads nowhere
		if i < len(explosions) - 1 do total += bonk.gap
	}
	budget := EXPLOSIONS_MAX_S - EXPLOSION_DURATION_S
	if total <= budget do return
	scale := budget / total
	for &bonk in explosions do bonk.gap = max(bonk.gap * scale, EXPLOSION_MIN_GAP_S)
}

@(private="file")
focusOnOwnUnits :: proc() {
	if clientState.myPix < 0 || clientState.myPix >= len(clientState.game.players) do return
	units := clientState.game.players[clientState.myPix].units
	if len(units) > 0 do for view in CLIENT_VIEWS do view.focus(units[0].position)
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
	clientState.winnerTeam = clientUpdateBuffer.winnerTeam

	for name in clientState.playerNames do delete(name)
	delete(clientState.playerNames)
	delete(clientState.playersReady)
	clientState.playerNames = clientUpdateBuffer.playerNames
	clientState.playersReady = clientUpdateBuffer.playersReady
	clientUpdateBuffer.playerNames = nil
	clientUpdateBuffer.playersReady = nil

	pruneOrders()
	promoteStatusChange()
}

// drops orders that the new state no longer allows: units that are gone, targets that got
// occupied or dug out, shots out of sight; orders planned while waiting are the usual victims
@(private="file")
pruneOrders :: proc() {
	if clientState.myPix < 0 || clientState.myPix >= len(clientState.game.players) do return
	dropped := 0
	gone := make([dynamic]int, context.temp_allocator)
	for unitId, &list in clientState.orders {
		kept, lost := validOrders(&clientState.game, clientState.myPix, unitId, list)
		dropped += lost
		if kept.count == 0 do append(&gone, unitId)
		else do list = kept
	}
	for unitId in gone do delete_key(&clientState.orders, unitId)
	if dropped > 0 do setNotice(dropped == 1 ? "AN ORDER WAS DROPPED, ITS TARGET IS NO LONGER VALID" : "SOME ORDERS WERE DROPPED, THEIR TARGETS ARE NO LONGER VALID")
}

@(private="file")
promoteStatusChange :: proc() {
	previous := clientState.status
	switch {
		case clientUpdateBuffer.gameOver:
			clientState.status = .FINISH
		case !clientUpdateBuffer.gameStarted:
			clientState.status = clientUpdateBuffer.teamSize > 1 ? .TEAMS : .NOT_FULL
		case hasLost():
			clientState.status = .LOST
		case clientUpdateBuffer.meta.activeIsYou:
			clientState.status = .PLAYING
		case:
			clientState.status = .WAITING
	}
	// your turn has come
	if clientState.status == .PLAYING && previous != .PLAYING do rl.PlaySound(menuSound)
	// out of the game: nothing left to order
	if clientState.status == .LOST && previous != .LOST {
		clear(&clientState.orders)
		clear(&clientState.storedGunOrders)
		selectedUnitId = NO_SELECTION
	}
	// keeps a placement that's in progress
	if canPlanOrders() && clientState.uiState == .DISABLED do clientState.uiState = .FREE
}

// without an MCV a player is out, their turns are skipped by the server
@(private)
hasLost :: proc() -> bool {
	if clientState.myPix < 0 || clientState.myPix >= len(clientState.game.players) do return false
	for unit in clientState.game.players[clientState.myPix].units do if unit.type == .MCV do return false
	return true
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

	// the next turn starts from scratch, except guns keep their targets
	clear(&clientState.orders)
	applyStoredGunOrders()
	clientState.ordersSent = true
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
