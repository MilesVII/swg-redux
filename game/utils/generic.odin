package utils

import rl "vendor:raylib"

TAU :: (rl.PI * 2)

includes :: proc(array: ^[dynamic]$T, value: ^T) -> bool {
	for v in array {
		if v == value^ do return true
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
