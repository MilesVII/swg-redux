package game

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "core:math/rand"
import "core:net"
import synchan "core:sync/chan"

import "hex"
import "utils"
import "networking"

@(private="file")
receptionSocket : net.TCP_Socket
@(private="file")
session : Session

NAME_PLACEHOLDER :: "NAMELESS"

@(private="file")
Player :: struct {
	id: Maybe(string),
	online: bool,
	socket: net.TCP_Socket,
	// cell values the player has, updates only carry what changed since; nil sends the whole map
	sentCells: []hex.GridCell,
	// confirmed their team, see onTeamChoice
	ready: bool
}

@(private="file")
Session :: struct {
	activePlayerIx: int,
	players: []Player,
	game: GameState,
	over: bool,
	managed: bool,
	// set once the game is over and everyone left, or nobody showed up for a while; ends the main loop
	closing: bool,
	// when the last player left, or the server started
	emptySince: time.Time,
	// 0 for no limit
	turnLimit: time.Duration,
	turnStarted: time.Time,
	// the game as it happened, offered to the players once it's over
	replay: Replay,
	replayTurns: [dynamic]ReplayTurn,
	replayBytes: []u8,
	replayName: string
}

@(private="file")
serverOrderBuffer: OrderSet

@(private="file")
explosionsBuffer: [dynamic]ExplosionBufferEntry

@(private="file")
SERVER_IDLE_SKIP := time.Millisecond * 100
// how long a game may sit without any player connected
ABANDONED_TIMEOUT :: time.Hour
// a late client still gets its orders in, it submits a moment before its own deadline
TURN_GRACE :: 3 * time.Second

server :: proc(managed: bool, playerCount: int, mapRadius: int, mapSeed: i64, turnSeconds: int, teamSize: int, local: bool, port: int, lobbyPort: int) {
	session = Session {
		activePlayerIx = -1,
		players = make([]Player, playerCount),
		managed = managed,
		turnLimit = time.Duration(max(turnSeconds, 0)) * time.Second
	}

	if managed {
		utils.loggingSilenced = true
		networking.verbose = false
	}

	networking.init()
	receptionSocket = networking.openServerSocket(
		local ? net.IP4_Loopback : net.IP4_Address { 0, 0, 0, 0 },
		port
	)

	for &player in session.players do player.online = false

	// small maps are often too cramped for six spawns, random seeds get plenty of tries
	gameInitRetries := 40
	for gameInitRetries >= 0 {
		err: GameInitError
		// the seed is kept for the replay, so it's picked here rather than in createGame
		seed := mapSeed == -1 ? rand.int63() : mapSeed
		session.game, err = createGame(playerCount, mapRadius, seed, teamSize)
		if err == .OK {
			session.replay = { version = REPLAY_VERSION, radius = mapRadius, playerCount = playerCount, teamSize = max(teamSize, 1), seed = seed }
			break
		}
		else if gameInitRetries == 0 || mapSeed != -1 {
			utils.log("failed to create a game, aborting")
			if session.managed do signalLobby(LOBBY_SIGNAL_TERMINATE)
			return
		}
		gameInitRetries -= 1
		utils.log("failed to create a game, retrying")
	}

	utils.log("session created, listening")
	if session.managed do signalLobby(LOBBY_SIGNAL_READY)

	networking.startAccepting(receptionSocket)
	session.emptySince = time.now()

	for !session.closing {
		for synchan.can_recv(networking.rx) {
			data, ok := synchan.recv(networking.rx)
			if ok do processPackage(data)
		}

		// out of time: the turn passes without orders
		if session.turnLimit > 0 && gameStarted() && !session.over && time.since(session.turnStarted) > session.turnLimit + TURN_GRACE {
			utils.log("turn timed out")
			clear(&serverOrderBuffer)
			endTurn(serverOrderBuffer)
		}

		// abandoned games go down after a while, finished ones as soon as they're empty
		if anyPlayerOnline() do session.emptySince = time.now()
		else if time.since(session.emptySince) > ABANDONED_TIMEOUT do shutDown("nobody connected for a while")

		free_all(context.temp_allocator)
		time.sleep(SERVER_IDLE_SKIP)
	}
}

@(private="file")
shutDown :: proc(reason: string) {
	utils.log(reason, ", shutting down")
	if session.managed do signalLobby(LOBBY_SIGNAL_TERMINATE)
	session.closing = true
}

@(private="file")
processPackage :: proc(p: networking.Package) {
	defer delete(p.payload)

	playerName := utils.badgeToString(p.header.me, context.temp_allocator)
	if !session.managed && p.header.message < .CONNECTED {
		fmt.printfln("player %s said %s", playerName, p.header.message)
	}

	switch p.header.message {
		case .GENERAL:
		case .PING:
			header := networking.MessageHeader { message = .PING }
			networking.say(p.socket, &header)
		case .REPLAY_REQUEST:
			if session.replayBytes == nil do break
			header := networking.MessageHeader { message = .REPLAY }
			networking.say(p.socket, &header, encode(ReplayFile { session.replayName, session.replayBytes }))
		case .REPLAY:
		case .TEAM:
			if gameStarted() || session.game.teamSize <= 1 do break
			choice: TeamChoice
			if !decode(p.payload, &choice) do break
			for player, pix in session.players {
				if player.online && player.socket == p.socket {
					onTeamChoice(pix, choice)
					break
				}
			}
		case .DIAL_FAILED:
		case .CONNECTED:
			if !session.managed do fmt.printfln("new client, waiting for JOIN")
		case .DISCONNECTED:
			for &player in session.players {
				if player.online && player.socket == p.socket {
					player.online = false
					utils.log(player.id, " disconnected")
				}
			}
			networking.hang(p.socket)
			// a finished game has nothing left to serve once its last player is gone
			if session.over && !anyPlayerOnline() do shutDown("game over and everyone left")
		case .JOIN:
			if onJoin(playerName, p.socket) do startGameIfFull()
		case .UPDATE:
			// the client lost track of the map, start over with a full one
			for &player, playerIndex in session.players {
				if !player.online || player.socket != p.socket do continue
				forgetSentCells(&player)
				sendUpdate(p.socket, playerIndex)
			}
		case .ORDERS:
			if session.activePlayerIx < 0 || session.over do break
			active := session.players[session.activePlayerIx]
			activeName, named := active.id.?
			if !named || !active.online || active.socket != p.socket || activeName != playerName do break

			clear(&serverOrderBuffer)
			if !decode(p.payload, &serverOrderBuffer) do break
			endTurn(serverOrderBuffer)
	}
}

// resolves the active player's orders and hands the turn to the next player
@(private="file")
endTurn :: proc(orders: OrderSet) {
	seed := rand.uint64()
	recordTurn(session.activePlayerIx, seed, orders)
	executeOrders(&session.game, session.activePlayerIx, orders, &explosionsBuffer, seed)
	bonkUnits(&session.game, explosionsBuffer[:])

	session.over = gameOver(&session.game)
	if session.over do finishReplay()

	if !session.over do for {
		nextPlayer()
		if activeUnitsLeft(&session.game, session.activePlayerIx) do break
	}
	session.turnStarted = time.now()

	broadcastUpdates()
	clear(&explosionsBuffer)
}

@(private="file")
onJoin :: proc(player: string, socket: net.TCP_Socket) -> bool {
	freeSlot := -1
	for &p, index in session.players {
		id, exists := p.id.?
		if exists && id == player {
			utils.log(player, " reconnected")
			// welcome back
			if p.online && p.socket != socket {
				// the old connection's DISCONNECTED will close it
				networking.kick(p.socket)
			}
			// a new connection knows nothing about the map
			forgetSentCells(&p)
			p.socket = socket
			p.online = true
			freeSlot = index
			break
		}
	}
	if freeSlot == -1 do for &p, index in session.players {
		_, exists := p.id.?
		if !exists {
			p.id = utils.badgeToString(utils.stringToBadge(player))
			p.socket = socket
			p.online = true
			freeSlot = index
			break
		}
	}

	if freeSlot == -1 {
		utils.log("no slots available for player ", player)
		sendNotice(socket, "NO FREE SLOTS IN THIS GAME")
		return false
	}
	utils.log("assigned slot ", freeSlot)

	sendUpdate(socket, freeSlot)
	return true
}

@(private="file")
anyPlayerOnline :: proc() -> bool {
	for player in session.players do if player.online do return true
	return false
}

@(private="file")
gameFull :: proc() -> bool {
	for player in session.players do if !player.online do return false
	return true
}

@(private="file")
allReady :: proc() -> bool {
	for player in session.players do if !player.ready do return false
	return true
}

// moves the player to a free slot of the wanted team, and records whether they're ready;
// slots decide the team, so the player records are swapped
@(private="file")
onTeamChoice :: proc(pix: int, choice: TeamChoice) {
	teamSize := session.game.teamSize
	teams := len(session.players) / teamSize
	if choice.team < 0 || choice.team >= teams do return

	current := pix
	if choice.team != teamOf(&session.game, pix) {
		for slot in choice.team * teamSize..<(choice.team + 1) * teamSize {
			if _, taken := session.players[slot].id.?; taken do continue
			session.players[slot], session.players[pix] = session.players[pix], session.players[slot]
			// both views changed
			forgetSentCells(&session.players[slot])
			forgetSentCells(&session.players[pix])
			current = slot
			break
		}
	}
	// readiness only counts for the team the player ends up on
	session.players[current].ready = choice.ready && teamOf(&session.game, current) == choice.team

	broadcastUpdates()
	startGameIfFull()
}
@(private="file")
gameStarted :: proc() -> bool {
	return session.activePlayerIx >= 0
}
@(private="file")
startGameIfFull :: proc() {
	// reconnects into a running game must not reset the turn
	if gameStarted() || !gameFull() do return
	// team games wait for everyone to settle on a team
	if session.game.teamSize > 1 && !allReady() do return

	if session.managed do signalLobby(LOBBY_SIGNAL_FULL)
	session.activePlayerIx = 0
	session.turnStarted = time.now()

	// the slots are settled now, the replay needs the names
	names := make([]string, len(session.players))
	for player, i in session.players do names[i] = strings.clone(player.id.? or_else NAME_PLACEHOLDER)
	session.replay.names = names

	broadcastUpdates()
}

@(private="file")
recordTurn :: proc(player: int, seed: u64, orders: OrderSet) {
	copied := make(OrderSet)
	for unitId, list in orders do copied[unitId] = list
	append(&session.replayTurns, ReplayTurn { player, seed, copied })
}

// encodes the finished game and keeps the file under replays/
@(private="file")
finishReplay :: proc() {
	session.replay.turns = session.replayTurns[:]
	session.replayBytes = encode(session.replay)

	y, mon, d := time.date(time.now())
	h, min, sec := time.clock(time.now())
	parts := make([dynamic]string, context.temp_allocator)
	for name in session.replay.names do append(&parts, name)
	session.replayName = fmt.aprintf("%04d%02d%02d-%02d%02d%02d-%s.replay", y, int(mon), d, h, min, sec, strings.join(parts[:], "-", context.temp_allocator))

	if err := os.make_directory_all("replays"); err != nil && err != .Exist {
		utils.log("can't create the replays folder: ", err)
		return
	}
	path := fmt.tprintf("replays/%s", session.replayName)
	if err := os.write_entire_file(path, session.replayBytes); err != nil do utils.log("can't write ", path, ": ", err)
	else do utils.log("replay saved as ", path)
}

@(private="file")
broadcastUpdates :: proc() {
	for player, playerIndex in session.players {
		if player.online do sendUpdate(player.socket, playerIndex)
	}
}

@(private="file")
getActivePlayerName :: proc() -> string {
	if session.activePlayerIx < 0 do return NAME_PLACEHOLDER
	currentPlayer, cpe := session.players[session.activePlayerIx].id.?
	return cpe ? currentPlayer : NAME_PLACEHOLDER
}

@(private="file")
getWinnerTeam :: proc() -> int {
	standing := teamsStanding(&session.game, context.temp_allocator)
	return len(standing) > 0 ? standing[0] : -1
}

// the winning team's names, joined
getWinnerName :: proc() -> string {
	winner := getWinnerTeam()
	if winner < 0 do return ""
	names := make([dynamic]string, context.temp_allocator)
	for player, pix in session.players {
		if teamOf(&session.game, pix) != winner do continue
		name, named := player.id.?
		append(&names, named ? name : NAME_PLACEHOLDER)
	}
	return strings.join(names[:], " & ", context.temp_allocator)
}

@(private="file")
sendNotice :: proc(socket: net.TCP_Socket, notice: string) {
	header := networking.MessageHeader {
		message = .GENERAL,
	}
	networking.say(socket, &header, encode(notice))
}

@(private="file")
turnTimeLeft :: proc() -> f32 {
	if session.turnLimit == 0 || !gameStarted() || session.over do return 0
	return max(f32(time.duration_seconds(session.turnLimit - time.since(session.turnStarted))), 0)
}

@(private="file")
forgetSentCells :: proc(player: ^Player) {
	delete(player.sentCells)
	player.sentCells = nil
}

@(private="file")
sendUpdate :: proc(socket: net.TCP_Socket, playerIndex: int) {
	header := networking.MessageHeader {
		message = .UPDATE,
	}

	names := make([]string, len(session.players), context.temp_allocator)
	ready := make([]bool, len(session.players), context.temp_allocator)
	for p, i in session.players {
		names[i] = p.id.? or_else ""
		ready[i] = p.ready
	}

	source := UpdateSource {
		game = &session.game,
		playerIndex = playerIndex,
		activePlayer = session.activePlayerIx,
		started = gameStarted(),
		over = session.over,
		explosions = explosionsBuffer[:],
		names = names,
		ready = ready,
		activeName = getActivePlayerName(),
		winnerName = session.over ? getWinnerName() : "",
		winnerTeam = session.over ? getWinnerTeam() : -1,
		turnLimit = f32(time.duration_seconds(session.turnLimit)),
		turnTimeLeft = turnTimeLeft(),
		replayAvailable = session.replayBytes != nil
	}
	networking.say(socket, &header, encodeUpdate(source, &session.players[playerIndex].sentCells))
}

// teams alternate: with two teams of two the order is 0, 2, 1, 3
nextPlayer :: proc() {
	teamSize := max(session.game.teamSize, 1)
	teams := len(session.players) / teamSize
	team := session.activePlayerIx / teamSize
	member := session.activePlayerIx % teamSize
	team += 1
	if team >= teams {
		team = 0
		member = (member + 1) % teamSize
	}
	session.activePlayerIx = team * teamSize + member
}
