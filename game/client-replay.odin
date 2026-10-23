package game

import rl "vendor:raylib"

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

import "hex"
import "utils"
import "networking"

// watching a replay: the game is run again turn by turn and each turn is fed to the client
// as if the server had sent it, so it looks like a game being played

REPLAYS_DIR :: "replays"
// seconds between turns when a replay plays by itself, after the explosions have landed
REPLAY_AUTO_DELAY_S :: 1.2

ReplayPrompt :: enum { NONE, SAVE, WATCH }

replay: struct {
	active: bool,
	data: Replay,
	game: GameState,
	// turns applied so far
	turn: int,
	// whose fog of war is shown, -1 for the whole map
	viewer: int,
	auto: bool,
	nextAt: f64,
	sentCells: []hex.GridCell,
	explosions: [dynamic]ExplosionBufferEntry,

	// the finished game's replay was offered or received, and the player hasn't answered yet
	prompt: ReplayPrompt,
	promptedFor: bool,
	pendingName: string,
	pendingData: []u8,

	// files listed in the lobby's submenu
	files: [dynamic]string
}

// --- starting and stopping ---

startReplayFromFile :: proc(path: string) -> bool {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		setNotice(fmt.tprintf("CAN'T READ %s", path))
		return false
	}
	defer delete(data)
	return startReplayFromBytes(data, 0)
}

startReplayFromBytes :: proc(bytes: []u8, viewer: int) -> bool {
	parsed: Replay
	if !decode(bytes, &parsed) || parsed.version != REPLAY_VERSION || len(parsed.turns) == 0 {
		deleteReplay(&parsed)
		setNotice("THAT'S NOT A REPLAY THIS CLIENT CAN PLAY")
		return false
	}
	game, ok := rebuildReplayGame(parsed, 0)
	if !ok {
		deleteReplay(&parsed)
		setNotice("CAN'T REBUILD THE REPLAY'S MAP")
		return false
	}

	stopReplayPlayback()
	resetGameState()
	replay.active = true
	replay.data = parsed
	replay.game = game
	replay.turn = 0
	replay.viewer = clamp(viewer, 0, parsed.playerCount - 1)
	replay.auto = true
	replay.prompt = .NONE
	clientFirstUpdate = true
	refreshReplayIntel()
	feedReplayTurn(nil)
	replay.nextAt = rl.GetTime() + REPLAY_AUTO_DELAY_S
	return true
}

@(private="file")
stopReplayPlayback :: proc() {
	if !replay.active do return
	replay.active = false
	deleteReplay(&replay.data)
	deleteState(replay.game)
	replay.game = {}
	delete(replay.sentCells)
	replay.sentCells = nil
	clear(&replay.explosions)
}

// back to wherever the replay was started from
stopReplay :: proc() {
	stopReplayPlayback()
	resetGameState()
	switch {
		case clientState.target == .LOBBY && clientState.connection != 0:
			clientState.status = .LOBBY
			menuState.status = .MAIN
		case lobbyAvailable():
			leaveToLobby()
		case:
			clientState.status = .DISCONNECTED
			setNotice("REPLAY OVER")
	}
}

// --- running it ---

// every player's memory of the map is kept current, so switching the viewer stays consistent
@(private="file")
refreshReplayIntel :: proc() {
	for _, pix in replay.game.players {
		seen := getStateForPlayer(&replay.game, pix)
		deleteState(seen)
	}
}

// hands the current replay state to the client like a server update
@(private="file")
feedReplayTurn :: proc(explosions: []ExplosionBufferEntry) {
	over := replay.turn >= len(replay.data.turns)
	active := replayActivePlayer(replay.data, replay.turn)
	ready := make([]bool, replay.data.playerCount, context.temp_allocator)
	for &r in ready do r = true

	winnerTeam := -1
	winnerName := ""
	if over {
		standing := teamsStanding(&replay.game, context.temp_allocator)
		if len(standing) > 0 {
			winnerTeam = standing[0]
			names := make([dynamic]string, context.temp_allocator)
			for name, pix in replay.data.names do if teamOf(&replay.game, pix) == winnerTeam do append(&names, name)
			winnerName = strings.join(names[:], " & ", context.temp_allocator)
		}
	}

	viewer := max(replay.viewer, 0)
	// the viewer's own shots get muzzle blasts, like in a game
	clear(&clientSentOrders)
	if replay.turn > 0 {
		last := replay.data.turns[replay.turn - 1]
		if last.player == viewer do for unitId, list in last.orders do clientSentOrders[unitId] = list
	}

	source := UpdateSource {
		game = &replay.game,
		playerIndex = viewer,
		activePlayer = active,
		started = true,
		over = over,
		revealAll = replay.viewer < 0,
		explosions = explosions,
		names = replay.data.names,
		ready = ready,
		activeName = replay.data.names[active],
		winnerName = winnerName,
		winnerTeam = winnerTeam,
	}
	payload := encodeUpdate(source, &replay.sentCells)
	defer delete(payload)
	onUpdate(payload)
}

@(private="file")
replayForward :: proc() {
	if replay.turn >= len(replay.data.turns) do return
	clear(&replay.explosions)
	applyReplayTurn(&replay.game, replay.data.turns[replay.turn], &replay.explosions)
	replay.turn += 1
	refreshReplayIntel()
	feedReplayTurn(replay.explosions[:])
}

// rebuilds the game up to the previous turn, explosions aren't played backwards
@(private="file")
replayBack :: proc() {
	if replay.turn == 0 do return
	game, ok := rebuildReplayGame(replay.data, replay.turn - 1)
	if !ok do return
	deleteState(replay.game)
	replay.game = game
	replay.turn -= 1
	refreshReplayIntel()
	feedReplayTurn(nil)
}

@(private="file")
switchReplayViewer :: proc() {
	// every player, then the whole map
	replay.viewer += 1
	if replay.viewer >= replay.data.playerCount do replay.viewer = -1
	feedReplayTurn(nil)
}

// keys and automatic playback, called every frame while a replay is active
updateReplay :: proc() {
	if !replay.active do return
	now := rl.GetTime()
	animating := clientUpdateAnimationsPending

	if rl.IsKeyPressed(.ESCAPE) {
		stopReplay()
		return
	}
	if rl.IsKeyPressed(.SPACE) {
		replay.auto = !replay.auto
		replay.nextAt = now + REPLAY_AUTO_DELAY_S
	}
	if rl.IsKeyPressed(.TAB) do switchReplayViewer()
	if !animating && (rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT)) {
		replayForward()
		replay.nextAt = now + REPLAY_AUTO_DELAY_S
	}
	if !animating && (rl.IsKeyPressed(.LEFT) || rl.IsKeyPressedRepeat(.LEFT)) {
		replayBack()
		replay.nextAt = now + REPLAY_AUTO_DELAY_S
	}

	if replay.auto && !animating {
		if replay.turn >= len(replay.data.turns) do replay.auto = false
		else if now >= replay.nextAt {
			replayForward()
			replay.nextAt = now + REPLAY_AUTO_DELAY_S
		}
	}
}

replayStatus :: proc() -> cstring {
	if replay.turn >= len(replay.data.turns) {
		if len(clientState.winnerName) == 0 do return fmt.ctprintf("REPLAY OVER, NOBODY SURVIVED")
		return fmt.ctprintf("REPLAY OVER, %s WON", clientState.winnerName)
	}
	active := replayActivePlayer(replay.data, replay.turn)
	return fmt.ctprintf("REPLAY %d/%d, %s IS MAKING ORDERS", replay.turn, len(replay.data.turns), replay.data.names[active])
}

replayHint :: proc() -> cstring {
	view := replay.viewer < 0 ? "ALL" : replay.data.names[replay.viewer]
	return fmt.ctprintf("LEFT/RIGHT TURNS, SPACE AUTO %s, TAB VIEW: %s, ESC EXIT", replay.auto ? "ON" : "OFF", view)
}

// --- saving what the server offers ---

// called with every update of a finished game
offerReplayIfNew :: proc(available: bool) {
	if !available || replay.promptedFor || replay.active do return
	replay.promptedFor = true
	replay.prompt = .SAVE
}

onReplayReceived :: proc(payload: []u8) {
	file: ReplayFile
	if !decode(payload, &file) {
		setNotice("THE REPLAY ARRIVED BROKEN")
		return
	}
	delete(replay.pendingName)
	delete(replay.pendingData)
	replay.pendingName = file.name
	replay.pendingData = file.data

	if err := os.make_directory_all(REPLAYS_DIR); err != nil && err != .Exist {
		setNotice("CAN'T CREATE THE REPLAYS FOLDER")
		return
	}
	path := fmt.tprintf("%s/%s", REPLAYS_DIR, file.name)
	if err := os.write_entire_file(path, file.data); err != nil {
		setNotice(fmt.tprintf("CAN'T WRITE %s", path))
		return
	}
	setNotice(fmt.tprintf("REPLAY SAVED AS %s", path))
	replay.prompt = .WATCH
}

// enter and escape while a prompt is up; returns true when a key was consumed
replayPromptKeys :: proc() -> bool {
	if replay.prompt == .NONE do return false
	yes := rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER)
	no := rl.IsKeyPressed(.ESCAPE)
	if !yes && !no do return false

	prompt := replay.prompt
	replay.prompt = .NONE
	if !yes do return true
	switch prompt {
		case .NONE:
		case .SAVE:
			header := networking.MessageHeader { message = .REPLAY_REQUEST, me = utils.stringToBadge(clientState.name) }
			networking.say(clientState.serverSocket, &header)
			setNotice("WAITING FOR THE REPLAY")
		case .WATCH:
			startReplayFromBytes(replay.pendingData, clientState.myPix)
	}
	return true
}

drawReplayPrompt :: proc() {
	if replay.prompt == .NONE do return
	title: cstring = replay.prompt == .SAVE ? "SAVE THE REPLAY?" : "WATCH THE REPLAY NOW?"
	drawPromptBox(title, "ENTER FOR YES, ESC FOR NO")
}

// --- the lobby's list of saved replays ---

refreshReplayFiles :: proc() {
	for file in replay.files do delete(file)
	clear(&replay.files)
	infos, err := os.read_all_directory_by_path(REPLAYS_DIR, context.temp_allocator)
	if err != nil do return
	slice.sort_by(infos, proc(a, b: os.File_Info) -> bool { return a.modification_time._nsec > b.modification_time._nsec })
	for info in infos {
		if info.type == .Directory || !strings.has_suffix(info.name, ".replay") do continue
		append(&replay.files, strings.clone(info.name))
	}
}

replayFilePath :: proc(index: int) -> string {
	return fmt.tprintf("%s/%s", REPLAYS_DIR, replay.files[index])
}

// the file name without the date stamp and extension: the players
replayFileLabel :: proc(name: string) -> string {
	label := strings.trim_suffix(name, ".replay")
	date := label
	if len(label) > 16 && label[8] == '-' && label[15] == '-' {
		date = fmt.tprintf("%s-%s-%s %s:%s", label[0:4], label[4:6], label[6:8], label[9:11], label[11:13])
		return fmt.tprintf("%s  %s", date, strings.to_upper(label[16:], context.temp_allocator))
	}
	return strings.to_upper(label, context.temp_allocator)
}
