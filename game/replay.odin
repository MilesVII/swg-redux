package game

// running a recorded game again, see Replay in protocol.odin

// the game as it was after `turns` turns of the replay; fails when the map can't be rebuilt
rebuildReplayGame :: proc(replay: Replay, turns: int) -> (state: GameState, ok: bool) {
	if replay.version != REPLAY_VERSION || replay.playerCount <= 0 do return {}, false
	err: GameInitError
	state, err = createGame(replay.playerCount, replay.radius, replay.seed, replay.teamSize)
	if err != .OK do return {}, false

	explosions: [dynamic]ExplosionBufferEntry
	defer delete(explosions)
	for i in 0..<min(turns, len(replay.turns)) {
		clear(&explosions)
		applyReplayTurn(&state, replay.turns[i], &explosions)
	}
	return state, true
}

// one recorded turn, exactly as the server ran it
applyReplayTurn :: proc(state: ^GameState, turn: ReplayTurn, explosions: ^[dynamic]ExplosionBufferEntry) {
	if turn.player < 0 || turn.player >= len(state.players) do return
	executeOrders(state, turn.player, turn.orders, explosions, turn.seed)
	bonkUnits(state, explosions[:])
}

// who plays the turn after `turns` turns, or the last player once the game is over
replayActivePlayer :: proc(replay: Replay, turns: int) -> int {
	if len(replay.turns) == 0 do return 0
	return replay.turns[min(turns, len(replay.turns) - 1)].player
}
