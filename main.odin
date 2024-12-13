package main

import "core:os"
import "game"

main :: proc () {
	if len(os.args) >= 2{
		if os.args[1] == "server" do game.server()
		if os.args[1] == "debug" do game.debug()
	}
	else do game.client()
}
