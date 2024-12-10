package main

import "game"

RUN_SERVER :: false

main :: proc () {
	if (RUN_SERVER) do game.server()
	else do game.main()
}
