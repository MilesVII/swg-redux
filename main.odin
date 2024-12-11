package main

import "core:os"
import "game"

main :: proc () {
	if (len(os.args) >= 2 && os.args[1] == "server") do game.server()
	else do game.client()
}
