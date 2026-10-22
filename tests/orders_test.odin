package rules_test

import "core:testing"

import "../game"

@(test)
orders_lose_their_target :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeState(2)
	addUnit(&state, 0, 1, .MCV, { 0, 0 }, 2)
	addUnit(&state, 0, 2, .TONK, { -2, 0 }, 2)
	// an enemy moved onto the planned tiles meanwhile
	addUnit(&state, 1, 1, .TONK, { 1, 0 }, 2)

	move := queue({ type = .MOVE, target = { 1, 0 } })
	kept, dropped := game.validOrders(&state, 0, 2, move)
	testing.expect_value(t, kept.count, 0)
	testing.expect_value(t, dropped, 1)

	builds := queue(
		{ type = .BUILD, target = { 1, 0 }, targetUnitType = .GUN },
		{ type = .BUILD, target = { 0, 1 }, targetUnitType = .REC },
	)
	kept, dropped = game.validOrders(&state, 0, 1, builds)
	testing.expect_value(t, kept.count, 1)
	testing.expect_value(t, dropped, 1)
	if kept.count == 1 do testing.expect_value(t, kept.items[0].target, ({ 0, 1 }))
}

@(test)
queued_orders_fit_the_gold :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeState(1)
	addUnit(&state, 0, 1, .MCV, { 0, 0 }, 1)
	builds := queue(
		{ type = .BUILD, target = { 1, 0 }, targetUnitType = .GUN },
		{ type = .BUILD, target = { 0, 1 }, targetUnitType = .REC },
	)
	kept, dropped := game.validOrders(&state, 0, 1, builds)
	testing.expect_value(t, kept.count, 1)
	testing.expect_value(t, dropped, 1)

	// digs are capped at three gold the same way
	cellAt(&state, { 1, 0 }).gold = 1
	cellAt(&state, { 0, 1 }).gold = 1
	state.players[0].units[0].gold = 2
	digs := queue({ type = .DIG, target = { 1, 0 } }, { type = .DIG, target = { 0, 1 } })
	kept, dropped = game.validOrders(&state, 0, 1, digs)
	testing.expect_value(t, kept.count, 1)
}

@(test)
valid_orders_are_kept :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	state := makeState(1)
	addUnit(&state, 0, 1, .MCV, { 0, 0 }, 2)
	builds := queue(
		{ type = .BUILD, target = { 1, 0 }, targetUnitType = .GUN },
		{ type = .BUILD, target = { 0, 1 }, targetUnitType = .REC },
	)
	kept, dropped := game.validOrders(&state, 0, 1, builds)
	testing.expect_value(t, kept.count, 2)
	testing.expect_value(t, dropped, 0)

	_, lost := game.validOrders(&state, 0, 99, builds)
	testing.expect_value(t, lost, 2)
}
