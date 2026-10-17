package game

import "core:time"
import "core:fmt"
import "core:net"
import os "core:os/os2"
import synchan "core:sync/chan"

import "networking"

@(private="file")
receptionSocket : net.TCP_Socket

NewGameRequest :: struct {
	token: [64]rune,
	name: string,
	playerCount: int,
	mapSeed: i64,
	mapRadius: int
}

NGR_RADIUS_RANGE :: [2]int { 4, 64 }
NGR_PLAYERS_RANGE :: [2]int { 2, 6 }

GameSession :: struct {
	port: int,
	full: bool,
	yours: bool,
	config: NewGameRequest
}

@(private="file")
Session :: struct {
	initiator: net.TCP_Socket,
	initiatorOnline: bool,
	process: os.Process,
	port: int,
	pipeR: ^os.File,
	ready: bool,
	full: bool,
	terminated: bool,
	config: NewGameRequest
}

// only touched from the main thread
@(private="file")
lobbyState: struct {
	token: [64]rune,
	portRange: [2]int,
	gameAddress: net.Address,
	sessions: [dynamic]Session,
	connectedClients: [dynamic]net.TCP_Socket
}

@(private="file")
LOBBY_IDLE_SKIP := time.Millisecond * 100

LOBBY_SIGNAL_READY := u8(0)
LOBBY_SIGNAL_FULL := u8(1)
LOBBY_SIGNAL_TERMINATE := u8(2)

lobby :: proc(portRange: [2]int, local: bool, port: int, authToken: [64]rune) {
	// TODO: persist sessions in file

	lobbyState.token = authToken
	lobbyState.portRange = portRange
	// game servers decide their own bind address from the same `local` flag
	lobbyState.gameAddress = local ? net.IP4_Loopback : net.IP4_Address { 0, 0, 0, 0 }

	networking.init()
	receptionSocket = networking.openServerSocket(
		local ? net.IP4_Loopback : net.IP4_Address { 0, 0, 0, 0 },
		port
	)

	networking.startAccepting(receptionSocket)
	fmt.println("lobby online")

	for {
		for synchan.can_recv(networking.rx) {
			data, ok := synchan.recv(networking.rx)
			if ok do processPackage(data)
		}

		if pollSessions() do broadcastUpdates()

		free_all(context.temp_allocator)
		time.sleep(LOBBY_IDLE_SKIP)
	}
}

// reads signals from game servers and drops the ones that exited
// returns true if the session list visible to clients changed
@(private="file")
pollSessions :: proc() -> (changed: bool) {
	for i := len(lobbyState.sessions) - 1; i >= 0; i -= 1 {
		session := &lobbyState.sessions[i]

		for {
			hasData, err := os.pipe_has_data(session.pipeR)
			if err != nil || !hasData do break

			message: [1]byte
			redBytes, err2 := os.read(session.pipeR, message[:])

			if err2 != nil || redBytes != 1 do break

			switch message[0] {
				case LOBBY_SIGNAL_READY:
					session.ready = true
					changed = true
				case LOBBY_SIGNAL_FULL:
					session.full = true
					changed = true
				case LOBBY_SIGNAL_TERMINATE:
					session.terminated = true
			}
		}

		state, waitErr := os.process_wait(session.process, 0)
		exited := waitErr == nil && state.exited
		if !exited && !session.terminated do continue

		fmt.printfln("game server on port %d is gone", session.port)
		if !session.ready && session.initiatorOnline {
			sendNotice(session.initiator, "GAME SERVER FAILED TO START")
		}
		if session.ready do changed = true

		if exited do _ = os.process_close(session.process)
		else {
			// signalled termination but still running, don't leave it hanging
			_ = os.process_kill(session.process)
			_, _ = os.process_wait(session.process)
			_ = os.process_close(session.process)
		}
		os.close(session.pipeR)
		delete(session.config.name)
		ordered_remove(&lobbyState.sessions, i)
	}
	return
}

@(private="file")
processPackage :: proc(p: networking.Package) {
	defer delete(p.payload)

	switch p.header.message {
		case .GENERAL:
		case .JOIN:
		case .CONNECTED:
			fmt.println("new client")
			append(&lobbyState.connectedClients, p.socket)
			sendUpdate(p.socket)
		case .DISCONNECTED:
			fmt.println("client left")
			for client, i in lobbyState.connectedClients {
				if client == p.socket {
					unordered_remove(&lobbyState.connectedClients, i)
					break
				}
			}
			for &session in lobbyState.sessions {
				if session.initiator == p.socket do session.initiatorOnline = false
			}
			networking.hang(p.socket)
		case .UPDATE:
			// asking for session list
			sendUpdate(p.socket)
		case .ORDERS:
			// asking for a new game
			requestNewGame(p)
	}
}

@(private="file")
requestNewGame :: proc(p: networking.Package) {
	newGame: NewGameRequest
	if !decode(p.payload, &newGame) {
		sendNotice(p.socket, "MALFORMED REQUEST")
		return
	}
	accepted := false
	defer if !accepted do delete(newGame.name)

	if newGame.token != lobbyState.token {
		fmt.println("no auth")
		sendNotice(p.socket, "LOBBY TOKEN REJECTED")
		return
	}

	radiusOk := newGame.mapRadius >= NGR_RADIUS_RANGE[0] && newGame.mapRadius <= NGR_RADIUS_RANGE[1]
	playersOk := newGame.playerCount >= NGR_PLAYERS_RANGE[0] && newGame.playerCount <= NGR_PLAYERS_RANGE[1]
	if !radiusOk || !playersOk {
		sendNotice(p.socket, "INVALID GAME PARAMETERS")
		return
	}

	port, portFound := pickFreePort()
	if !portFound {
		fmt.println("no free game port")
		sendNotice(p.socket, "NO FREE GAME PORTS")
		return
	}

	// the lobby binary itself, so debug builds don't spawn a stale release build
	executable, exeErr := os.get_executable_path(context.temp_allocator)
	if exeErr != nil {
		fmt.println("can't locate own executable:", exeErr)
		sendNotice(p.socket, "LOBBY CAN'T START GAMES")
		return
	}

	pipeR, pipeW, pipeE := os.pipe()
	if pipeE != nil {
		fmt.println("no pipe:", pipeE)
		sendNotice(p.socket, "LOBBY CAN'T START GAMES")
		return
	}

	process, err := os.process_start(os.Process_Desc {
		command = {
			executable,
			"--managed",
			"--mode", "server",
			"--port", fmt.tprint(port),
			"--players", fmt.tprint(newGame.playerCount),
			"--radius", fmt.tprint(newGame.mapRadius),
			"--seed", fmt.tprint(newGame.mapSeed)
		},
		stdout = pipeW
	})
	// the child has its own copy now
	os.close(pipeW)

	if err != nil {
		fmt.println("no process:", err)
		os.close(pipeR)
		sendNotice(p.socket, "LOBBY CAN'T START GAMES")
		return
	}

	accepted = true
	append(&lobbyState.sessions, Session {
		process = process,
		port = port,
		pipeR = pipeR,
		initiator = p.socket,
		initiatorOnline = true,
		ready = false,
		full = false,
		config = newGame,
	})
}

@(private="file")
broadcastUpdates :: proc() {
	for client in lobbyState.connectedClients do sendUpdate(client)
}

@(private="file")
sendNotice :: proc(client: net.TCP_Socket, notice: string) {
	header := networking.MessageHeader {
		message = .GENERAL,
	}
	networking.say(client, &header, encode(notice))
}

@(private="file")
sendUpdate :: proc(client: net.TCP_Socket) {
	header := networking.MessageHeader {
		message = .JOIN,
	}

	payload := getAvailableSessions(client)
	networking.say(client, &header, encode(payload))
}

// full sessions stay listed so dropped players can rejoin
@(private="file")
getAvailableSessions :: proc(client: net.TCP_Socket) -> [dynamic]GameSession {
	payload := make([dynamic]GameSession, context.temp_allocator)
	for session in lobbyState.sessions {
		if session.ready {
			append(&payload, GameSession {
				config = session.config,
				full = session.full,
				port = session.port,
				yours = session.initiatorOnline && client == session.initiator
			})
		}
	}
	return payload
}

@(private="file")
pickFreePort :: proc() -> (port: int, found: bool) {
	for i in lobbyState.portRange[0]..=lobbyState.portRange[1] {
		freePortFound := true
		for session in lobbyState.sessions {
			if session.port == i {
				freePortFound = false
				break
			}
		}
		// something outside the lobby may be holding it
		if freePortFound && networking.portAvailable(lobbyState.gameAddress, i) do return i, true
	}
	return 0, false
}
