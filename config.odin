package main

import "core:os"
import "core:flags"
import "core:fmt"
import "core:net"

import "lib/toml"

Mode :: enum { client, server, lobby, debug }

Options :: struct {
	mode: Mode,
	name: string
}

Config :: struct {
	common: struct {
		port: int,
		local: bool,
		mode: Mode
	},
	client: struct {
		name: string,
		server: net.Address,
		framerate: int
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
		mode = .client
	},
	client = {
		name = "fops",
		server = net.IP4_Loopback,
		framerate = 120
	},
	server = {
		players = 2,
		radius = 16,
		seed = -1
	}
}

config :: proc() -> Config {
	config := DEFAULT_CONFIG

	section, err := toml.parse_file("config.toml")
	if !toml.print_error(err) {
		commonTable, commonTableFound := toml.get_table(section, "common")
		if commonTableFound {
			port, portFound := toml.get(i64, commonTable, "port")
			if portFound do config.common.port = int(port)
	
			local, localFound := toml.get(bool, commonTable, "local")
			if localFound do config.common.local = local
	
			mode, modeFound := toml.get(string, commonTable, "mode")
			if modeFound do config.common.mode = modeStringToMode(mode)
		}

		clientTable, clientTableFound := toml.get_table(section, "client")
		if clientTableFound {
			name, nameFound := toml.get(string, clientTable, "name")
			if nameFound do config.client.name = name
			
			addressString, addressFound := toml.get(string, clientTable, "server")
			if addressFound {
				address, ok := net.parse_ip4_address(addressString)
				if ok {
					config.client.server = address
				} else {
					fmt.println("failed to parse server address for client")
				}
			}

			framerate, framerateFound := toml.get(i64, clientTable, "framerate_cap")
			if framerateFound do config.client.framerate = int(framerate)
		}

		serverTable, serverTableFound := toml.get_table(section, "server")
		if serverTableFound {
			players, playersFound := toml.get(i64, serverTable, "players")
			if playersFound do config.server.players = int(players)
			
			radius, radiusFound := toml.get(i64, serverTable, "radius")
			if radiusFound do config.server.radius = int(radius)
			
			seed, seedFound := toml.get(i64, serverTable, "seed")
			if seedFound do config.server.seed = seed
		}
	}

	options: Options
	cliErr := flags.parse(&options, os.args[1:], .Unix)
	if cliErr != nil {
		fmt.println("failed to parse cli parameters: ", cliErr)
	}
	if options.mode != nil do config.common.mode = options.mode == .client ? .client : .server
	if len(options.name) > 0 do config.client.name = options.name

	return config
}

@(private="file")
modeStringToMode :: proc(mode: string) -> Mode {
	switch mode {
		case "client": return .client
		case "server": return .server
		case "lobby": return .lobby
		case "debug": return .debug
	}
	return .client
}
