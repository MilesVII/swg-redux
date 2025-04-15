package game

import rl "vendor:raylib"

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
@(private="file")
session : Session

@(private="file")
Session :: struct {
	pid: int,
	port: int
}

@(private="file")
sessions: [dynamic]Session
@(private="file")
connectedClients: [dynamic]net.TCP_Socket
@(private="file")
token: [64]rune

lobby :: proc(portRange: [2]int, local: bool, port: int, authToken: [64]rune) {
	// TODO: load sessions from file
	token = authToken

	networking.init()
	receptionSocket = networking.openServerSocket(
		local ? net.IP4_Loopback : net.IP4_Address { 0, 0, 0, 0 },
		port
	)

	startListeningForClients()

	for {
		for synchan.can_recv(networking.rx) {
			data, ok := synchan.recv(networking.rx)
			if ok do processPackage(data)
		}
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
		networking.listenBlocking(tx, playerSocket)
		// listenBlocking terminates if there's a socket error
		free(t.data)
	}

	t := thread.create(clientWorker)
	if t != nil {
		t.init_context = context
		t.data = socket
		thread.start(t)
	}
}

NewGameRequest :: struct {
	token: [64]rune,
	playerCount: int,
	mapSeed: i64,
	mapRadius: int
}

@(private="file")
processPackage :: proc(p: networking.Package) {
	fmt.printfln("player %s said %s", p.header.me, p.header.message)
	playerName := utils.badgeToString(p.header.me)
	switch p.header.message {
		case .JOIN:
		case .UPDATE:
		case .ORDERS:
			// messages 
			newGame: NewGameRequest
			decode(p.payload, &newGame)
			if newGame.token != token do return

			process, err := os.process_start({
				command = {
					"--managed", "true",
					"--players", fmt.aprint(newGame.playerCount),
					"--radius", fmt.aprint(newGame.mapRadius),
					"--seed", fmt.aprint(newGame.mapSeed)
				},
				// stdout  = w,
			})
			
			
			
	}
}
