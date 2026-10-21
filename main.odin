package main

import "core:net"
import "core:os"
import "core:strings"

import "game"

// builds without the client and so without raylib, X11 and OpenGL, for servers and lobbies:
// odin build . -define:HEADLESS=true
HEADLESS :: #config(HEADLESS, false)

main :: proc () {
	// before anything prints, see game.reserveStdoutForLobby
	for arg in os.args[1:] {
		if strings.has_prefix(arg, "--managed") || strings.has_prefix(arg, "-managed") {
			game.reserveStdoutForLobby()
			break
		}
	}

	// a client built without a console still prints to the terminal it was started from
	attachParentConsole()

	config := config()
	if config.common.mode != .client && !config.server.managed do ensureConsole()

	switch config.common.mode {
		case .client: 
			server: net.Address
			if config.common.local do server = net.IP4_Loopback
			else do server = config.client.server

			lobbyAddress: net.Address
			if config.common.local do lobbyAddress = net.IP4_Loopback
			else do lobbyAddress = config.client.lobby

			when HEADLESS {
				_, _ = os.write_string(os.stderr, "this build has no client, it was built with -define:HEADLESS=true\n")
				os.exit(1)
			} else {
				game.client(
					config.client.name,
					config.client.framerate,
					server,
					config.common.port,
					config.client.lobbyEnabled,
					lobbyAddress,
					config.common.lobbyPort,
					config.common.lobbyToken,
					config.client.renderer3D,
					config.client.rendererFromCommandLine
				)
			}
		case .server:
			game.server(
				config.server.managed,
				config.server.players,
				config.server.radius,
				config.server.seed,
				config.server.turnTime,
				config.server.teamSize,
				config.common.local,
				config.common.port,
				config.common.lobbyPort
			)
		case .lobby:
			game.lobby(
				config.lobby.portRange,
				config.common.local,
				config.common.lobbyPort,
				config.common.lobbyToken
			)
		case .debug:
	}
}
