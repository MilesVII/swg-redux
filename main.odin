package main

import "core:os"
import "core:flags"
import "core:fmt"
import "game"

Mode :: enum {
	client, server, debug
}

Options :: struct {
	mode: Mode `args:"required=1`,
	name: string
}

main :: proc () {
	options: Options
	flags.parse_or_exit(&options, os.args, .Unix)

	name := len(options.name) == 0 ? "fops" : options.name

	switch options.mode {
		case .client: game.client(name)
		case .debug: game.debug()
		case .server: game.server()
	}
}
