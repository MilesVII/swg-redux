package main

import "core:net"

import "game"

main :: proc () {
	config := config()
	switch config.common.mode {
		case .client: 
			server: net.Address
			if config.common.local do server = net.IP4_Loopback
			else do server = config.client.server

			lobbyAddress: net.Address
			if config.common.local do lobbyAddress = net.IP4_Loopback
			else do lobbyAddress = config.client.lobby

			game.client(
				config.client.name,
				config.client.framerate,
				server,
				config.common.port,
				config.client.lobbyEnabled,
				lobbyAddress,
				config.common.lobbyPort,
				config.common.lobbyToken
			)
		case .server:
			game.server(
				config.server.managed,
				config.server.players,
				config.server.radius,
				config.server.seed,
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
