package game

import rl "vendor:raylib"

import "core:time"
import "core:fmt"
import "core:net"
import os "core:os/os2"
import "core:thread"
import synchan "core:sync/chan"

import "hex"
import "utils"
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

GameSession :: struct {
	port: int,
	full: bool,
	yours: bool,
	config: NewGameRequest
}

@(private="file")
Session :: struct {
	initiator: net.TCP_Socket,
	process: os.Process,
	port: int,
	pipeR: ^os.File,
	ready: bool,
	full: bool,
	config: NewGameRequest
}

@(private="file")
lobbyState: struct {
	token: [64]rune,
	portRange: [2]int,
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

	networking.init()
	receptionSocket = networking.openServerSocket(
		local ? net.IP4_Loopback : net.IP4_Address { 0, 0, 0, 0 },
		port
	)

	startListeningForClients()
	fmt.println("lobby online")

	for {
		for synchan.can_recv(networking.rx) {
			data, ok := synchan.recv(networking.rx)
			if ok do processPackage(data)
		}

		for &session in lobbyState.sessions {
			for {
				hasData, err := os.pipe_has_data(session.pipeR)
				if err != nil || !hasData do break

				message: [1]byte;
				redBytes, err2 := os.read(session.pipeR, message[:])

				if err2 != nil || redBytes != 1 do break

				switch message[0] {
					case LOBBY_SIGNAL_READY:
						session.ready = true
						sendUpdate(session.initiator)
					case LOBBY_SIGNAL_FULL:
						session.full = true
					case LOBBY_SIGNAL_TERMINATE:
						err3 := os.process_close(session.process)
				}
			}
		}

		time.sleep(LOBBY_IDLE_SKIP)
	}
}

@(private="file")
startListeningForClients :: proc() {
	waitForClients :: proc(t: ^thread.Thread) {
		for {
			clientSocket := new(net.TCP_Socket)
			clientSocket^ = networking.waitForClient(receptionSocket)
			fmt.printfln("new client")
			startClientThread(clientSocket)
			sendUpdate(clientSocket^)
		}
	}

	t := thread.create(waitForClients)
	if t != nil {
		t.init_context = context
		t.user_index = 0
		thread.start(t)
	}
}

@(private="file")
startClientThread :: proc(socket: ^net.TCP_Socket) {
	clientWorker :: proc(t: ^thread.Thread) {
		playerSocket := (transmute(^net.TCP_Socket)t.data)^
		tx := networking.tx
		append(&lobbyState.connectedClients, playerSocket)
	
		networking.listenBlocking(tx, playerSocket)
		// listenBlocking terminates if there's a socket error
		for i in 0..<len(lobbyState.connectedClients) {
			if lobbyState.connectedClients[i] == playerSocket {
				unordered_remove(&lobbyState.connectedClients, i);
				return
			}
		}
		free(t.data)
	}

	t := thread.create(clientWorker)
	if t != nil {
		t.init_context = context
		t.data = socket
		thread.start(t)
	}
}

@(private="file")
processPackage :: proc(p: networking.Package) {
	playerName := utils.badgeToString(p.header.me)
	switch p.header.message {
		case .GENERAL:
		case .JOIN:
		case .UPDATE:
			// asking for session list
			sendUpdate(p.socket)
		case .ORDERS:
			// asking for a new game
			newGame: NewGameRequest
			decode(p.payload, &newGame)
			if newGame.token != lobbyState.token {
				fmt.println("no auth")
				return
			}

			pipeR, pipeW, pipeE := os.pipe()
			if pipeE != nil {
				fmt.println("no pipe")
				return
			}

			port, portFound := pickFreePort()
			if !portFound {
				fmt.println("porn ton found")
				return
			}

			process, err := os.process_start(os.Process_Desc {
				command = {
					"./swg-redux",
					"--managed",
					"--mode", "server",
					"--port", fmt.aprint(port),
					"--players", fmt.aprint(newGame.playerCount),
					"--radius", fmt.aprint(newGame.mapRadius),
					"--seed", fmt.aprint(newGame.mapSeed)
				},
				stdout = pipeW
			})

			if err != nil {
				fmt.println("no process:", err)
				return
			}

			append(&lobbyState.sessions, Session {
				process = process,
				port = port,
				pipeR = pipeR,
				initiator = p.socket,
				ready = false,
				full = false,
				config = newGame,
			})
	}
}

@(private="file")
broadcastUpdates :: proc() {
	for client in lobbyState.connectedClients do sendUpdate(client)
}

@(private="file")
sendUpdate :: proc(client: net.TCP_Socket) {
	header := networking.MessageHeader {
		message = .JOIN,
	}

	payload := getAvailableSessions(client)
	defer delete(payload)

	networking.say(client, &header, encode(payload))
}

@(private="file")
getAvailableSessions :: proc(client: net.TCP_Socket) -> [dynamic]GameSession {
	payload: [dynamic]GameSession
	for session in lobbyState.sessions {
		if session.ready && !session.full {
			append(&payload, GameSession {
				config = session.config,
				full = session.full,
				port = session.port,
				yours = client == session.initiator
			})
		}
	}
	return payload
}

@(private="file")
pickFreePort :: proc() -> (port: int, found: bool) {
	for i in lobbyState.portRange[0]..<lobbyState.portRange[1] {
		freePortFound := true
		for session in lobbyState.sessions {
			if session.port == i {
				freePortFound = false
				break
			}
		}
		if freePortFound do return i, true
	}
	return 0, false
}
