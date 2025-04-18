package main

import "core:os"
import "core:flags"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:strconv"
import "core:encoding/hex"
import "core:crypto/hash"
import "core:unicode/utf8"

import "lib/toml"

Mode :: enum { client, server, lobby, debug }

Options :: struct {
	mode: Mode,
	name: string,
	managed: bool,
	players: int,
	radius: int,
	seed: i64
}

TOKEN_LENGTH :: 64
AUTH_TOKEN :: [TOKEN_LENGTH]rune

Config :: struct {
	common: struct {
		port: int,
		local: bool,
		mode: Mode,
		lobbyPort: int,
		lobbyToken: AUTH_TOKEN
	},
	client: struct {
		name: string,
		server: net.Address,
		framerate: int,
		lobby: net.Address,
		lobbyEnabled: bool
	},
	server: struct {
		players: int,
		radius: int,
		seed: i64,
		managed: bool
	},
	lobby: struct {
		portRange: [2]int,
	}
}

DEFAULT_CONFIG := Config {
	common = {
		port = 7420,
		local = false,
		mode = .client,
		lobbyPort = 7600,
		lobbyToken = hashToken("")
	},
	client = {
		name = "fops",
		framerate = 120,
		server = net.IP4_Loopback,
		lobby = net.IP4_Loopback,
		lobbyEnabled = false
	},
	server = {
		players = 2,
		radius = 16,
		seed = -1,
		managed = false
	},
	lobby = {
		portRange = { 7420, 7500 }
	}
}

config :: proc() -> Config {
	config := DEFAULT_CONFIG

	readFileConfig("config.toml", &config)

	options: Options
	cliErr := flags.parse(&options, os.args[1:], .Unix)
	if cliErr != nil {
		fmt.println("failed to parse cli parameters: ", cliErr)
	}

	if options.mode != nil do config.common.mode = options.mode
	if len(options.name) > 0 do config.client.name = options.name
	if config.common.mode == .server && options.managed {
		config.server.managed = true
		config.server.players = options.players
		config.server.radius = options.radius
		config.server.seed = options.seed
	}

	return config
}

readFileConfig :: proc(filename: string, config: ^Config) {
	section, err := toml.parse_file(filename)
	if !toml.print_error(err) {
		commonTable, commonTableFound := toml.get_table(section, "common")
		if commonTableFound {
			port, portFound := toml.get(i64, commonTable, "port")
			if portFound do config.common.port = int(port)
	
			local, localFound := toml.get(bool, commonTable, "local")
			if localFound do config.common.local = local
	
			mode, modeFound := toml.get(string, commonTable, "mode")
			if modeFound do config.common.mode = modeStringToMode(mode)

			lobbyPort, lobbyPortFound := toml.get(i64, commonTable, "lobby_port")
			if lobbyPortFound do config.common.lobbyPort = int(lobbyPort)

			token, tokenFound := toml.get(string, commonTable, "lobby_token")
			if tokenFound do config.common.lobbyToken = hashToken(token)
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
			
			lobbyAddress, lobbyAddressFound := toml.get(string, clientTable, "lobby")
			if lobbyAddressFound {
				address, ok := net.parse_ip4_address(lobbyAddress)
				if ok {
					config.client.lobby = address
					config.client.lobbyEnabled = true
				} else {
					fmt.println("failed to parse server address for client")
				}
			}
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

		lobbyTable, lobbyTableFound := toml.get_table(section, "lobby")
		if lobbyTableFound {
			portRange, portRangeFound := toml.get(string, lobbyTable, "game_ports")
			if portRangeFound {
				parsed, ok := parsePortRange(portRange)
				if ok do config.lobby.portRange = parsed
			}
		}
	}
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

@(private="file")
parsePortRange :: proc(range: string) -> (pair: [2]int, ok: bool) {
	values := strings.split(range, "-")
	if len(values) < 2 do return { 0, 0 }, false

	v0, ok0 := strconv.parse_int(values[0], 10)
	v1, ok1 := strconv.parse_int(values[1], 10)
	if ok0 && ok1 do return { v0, v1 }, true
	return { 0, 0 }, false
}

@(private="file")
hashToken :: proc(raw: string) -> AUTH_TOKEN {
	hashsum := transmute(string)hex.encode(hash.hash_string(.SHA256, raw))
	return stringToHash(hashsum)
}

@(private="file")
stringToHash :: proc(raw: string) -> AUTH_TOKEN {
	r : AUTH_TOKEN
	runes := utf8.string_to_runes(raw)
	for c, i in raw {
		if i >= TOKEN_LENGTH do break
		r[i] = c
	}
	return r
}
