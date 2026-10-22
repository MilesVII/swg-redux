package rules_test

import "core:testing"

import "../game"

@(test)
explosion_gaps_are_shuffled :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	explosions := make([]game.Explosion, 12)
	game.scheduleExplosions(explosions)
	lo, hi := game.EXPLOSION_GAP_RANGE[0], game.EXPLOSION_GAP_RANGE[1]
	allSame := true
	for bonk, i in explosions {
		testing.expect(t, bonk.gap >= lo && bonk.gap <= hi, "a small salvo keeps its gaps in range")
		testing.expect(t, bonk.pitch >= game.EXPLOSION_PITCH_RANGE[0] && bonk.pitch <= game.EXPLOSION_PITCH_RANGE[1], "pitch stays in range")
		if i > 0 && bonk.gap != explosions[0].gap do allSame = false
	}
	testing.expect(t, !allSame, "gaps differ")
}

@(test)
huge_salvos_are_compressed :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	explosions := make([]game.Explosion, 60)
	game.scheduleExplosions(explosions)
	total := game.EXPLOSION_DURATION_S
	for bonk, i in explosions {
		testing.expect(t, bonk.gap >= game.EXPLOSION_MIN_GAP_S, "gaps never collapse entirely")
		if i < len(explosions) - 1 do total += bonk.gap
	}
	testing.expectf(t, total <= game.EXPLOSIONS_MAX_S + .01, "60 explosions play in %.1f s", total)
	testing.expectf(t, total > game.EXPLOSIONS_MAX_S - 1, "the budget is used, %.1f s", total)
}
