package utils

import rl "vendor:raylib"
import "core:unicode/utf8"
import "core:strings"
import "core:math"
import "core:math/rand"

TAU :: (rl.PI * 2)

includes_dynamic :: proc(array: ^[dynamic]$T, value: ^T) -> bool {
	for v in array {
		if v == value^ do return true
	}
	return false
}
includes_slice :: proc(array: []$T, value: ^T) -> bool {
	for v in array {
		if v == value^ do return true
	}
	return false
}
includes :: proc {
	includes_dynamic,
	includes_slice,
}

some :: proc(array: ^[dynamic]$T, cb: proc(^T) -> bool) -> bool {
	for &v in array {
		if cb(&v) do return true
	}
	return false
}

@(private)
cursorHover := false
cursorHoverBegin :: proc() {
	cursorHover = false
}
setCursorHover :: proc(hover: bool) {
	if hover do cursorHover = true
}
cursorHoverEnd :: proc() {
	rl.SetMouseCursor(cursorHover ? .POINTING_HAND : .DEFAULT)
}

BADGE_SIZE :: 16
Badge :: [BADGE_SIZE]rune

stringToBadge :: proc(name: string) -> Badge {
	r : Badge
	runes := utf8.string_to_runes(name)
	for c, i in name {
		if i >= BADGE_SIZE do break
		r[i] = c
	}
	return r
}

badgeToString :: proc(badge: Badge) -> string {
	badge := badge
	cutset := [1]rune { }
	return strings.trim(utf8.runes_to_string(badge[:]), utf8.runes_to_string(cutset[:]))
}

swap :: proc(a: ^$T, b:^T) {
	c := a^
	a^ = b^
	b^ = c
}

shuffle :: proc(target: []$T) {
	for _, i in target {
		tix := rand.int31_max(i32(len(target)))
		if i == int(tix) do continue
		swap(&target[i], &target[tix])
	}
}

FLICKER_PERIOD_S := f32(.800)
flicker: f32
updateFlicker :: proc() {
	flicker = math.mod(flicker + rl.GetFrameTime() / FLICKER_PERIOD_S, f32(1.0))
}
