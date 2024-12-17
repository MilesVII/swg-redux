package utils

import rl "vendor:raylib"

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
	rl.SetMouseCursor(cursorHover ? rl.MouseCursor.POINTING_HAND : rl.MouseCursor.DEFAULT)
}
