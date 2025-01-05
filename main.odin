package main

import "core:os"
import "core:flags"
import "core:fmt"
import "core:net"
import "core:math/rand"

import "game"
import "lib/toml"

Options :: struct {
	mode: enum { unknown, client, server },
	name: string
}

Config :: struct {
	common: struct {
		port: int,
		local: bool,
		mode: enum { Client, Server }
	},
	client: struct {
		name: string,
		server: net.Address
	},
	server: struct {
		players: int,
		radius: int,
		seed: i64
	}
}

DEFAULT_CONFIG := Config {
	common = {
		port = 7420,
		local = false,
		mode = .Client
	},
	client = {
		name = "fops",
		server = net.IP4_Loopback
	},
	server = {
		players = 2,
		radius = 16,
		seed = rand.int63()
	}
}

config :: proc() -> Config {
	config := DEFAULT_CONFIG

	section, err := toml.parse_file("config.toml")
	if !toml.print_error(err) {
		port, portFound := toml.get(i64, section, "port")
		if portFound do config.common.port = int(port)

		local, localFound := toml.get(bool, section, "local")
		if localFound do config.common.local = local

		mode, modeFound := toml.get(bool, section, "run_as_server")
		if modeFound do config.common.mode = mode ? .Server : .Client

		clientTable, clientTableFound := toml.get_table(section, "client")
		if clientTableFound {
			name, nameFound := toml.get(string, section, "name")
			if nameFound do config.client.name = name

			addressString, addressFound := toml.get(string, section, "server")
			if addressFound {
				address, ok := net.aton(addressString, .IP4)
				if ok {
					config.client.server = address
				} else {
					fmt.println("failed to parse server address for client: ", err)
				}
			}
		}

		serverTable, serverTableFound := toml.get_table(section, "server")
		if serverTableFound {
			players, playersFound := toml.get(i64, section, "players")
			if playersFound do config.server.players = int(players)
			
			radius, radiusFound := toml.get(i64, section, "radius")
			if radiusFound do config.server.radius = int(radius)
			
			seed, seedFound := toml.get(i64, section, "seed")
			if seedFound do config.server.seed = seed
		}
	}

	options: Options
	cliErr := flags.parse(&options, os.args[1:], .Unix)
	if cliErr != nil {
		fmt.println("failed to parse cli parameters: ", cliErr)
	}
	if options.mode != .unknown do config.common.mode = options.mode == .client ? .Client : .Server
	if len(options.name) > 0 do config.client.name = options.name

	return config
}

main :: proc () {
	config := config()
	switch config.common.mode {
		case .Client: game.client(config.client.name)
		case .Server: game.server()
	}
}
