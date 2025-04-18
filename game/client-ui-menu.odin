
package game

import "ui"
import "networking"

import "core:strings"

import rl "vendor:raylib"

@(private="file")
MenuStatus :: enum { MAIN, NEW_GAME }

@(private="file")
MenuState :: struct {
	status: MenuStatus,
	ngr: NewGameRequest,
	ngrSent: bool,
	index: int,
	sessions: [dynamic]Session
}

menuState: MenuState

drawMenu :: proc() {
	if menuState.status == .MAIN do drawMain()
}

@(private="file")
drawMain :: proc() {
	drawItemButton("REQUEST A NEW GAME", 0)
	drawItemButton("REFRESH SESSION LIST", 1)
	for session, i in menuState.sessions {
		drawItemButton("s", i + 2)
	}
	if len(menuState.sessions) == 0 {
		drawItemButton("<NO AVAILABLE SESSIONS FOUND>", 2)
	}
	drawSelectorBullet({100, 100}, 20)

	if rl.IsKeyPressed(.UP) do menuState.index -= 1
	if rl.IsKeyPressed(.DOWN) do menuState.index += 1
	listLength := max(3, len(menuState.sessions) + 2 - 1)
	menuState.index = wrapClamp(menuState.index, 0, listLength - 1)

	if rl.IsKeyPressed(.ENTER) {
		switch i := menuState.index; i {
			case 0:
				// start requesting new game
				menuState.status = .NEW_GAME
			case 1:
				// request session list
				message := networking.MessageHeader {
					message = .UPDATE
				}
				networking.say(clientState.serverSocket, &message)
			case i > 1 && len(menuState.sessions) > 0:
				clientState.status = .CONNECTING
				
		}
	}
}

drawItemButton :: proc(caption: string, offset: int) {
	bulletRadius := FONT_SIZE * .42
	bulletSpace := bulletRadius * 2

	origin := [2]f32 {
		UI_CORNER_PAD.x,
		f32(ui.windowSize.y) * .5 - FONT_SIZE * .5
	}
	indexDisplacement := offset - menuState.index
	vOffset := f32(indexDisplacement) * (FONT_SIZE + UI_SPACING)
	alpha := clamp(f32(1) - abs(f32(indexDisplacement)) * .25, .5, 1.0)

	color := rl.BLACK
	color.a = u8(255 * alpha)

	if offset == menuState.index {
		drawSelectorBullet(
			origin + { bulletRadius, FONT_SIZE * .5 },
			bulletRadius
		)
	}
	rl.DrawTextEx(
		vcrFont,
		strings.unsafe_string_to_cstring(caption),
		origin + { bulletSpace + UI_SPACING, vOffset },
		FONT_SIZE,
		FONT_SPACING,
		color
	)
}

drawSelectorBullet :: proc(origin: [2]f32, radius: f32) {
	ray := rl.Vector2 { radius, 0 }
	v0 := origin + ray;
	v1 := origin + rl.Vector2Rotate(ray, 6.28 * .33)
	v2 := origin + rl.Vector2Rotate(ray, 6.28 * .66)
	rl.DrawTriangle(v2, v1, v0, rl.BLACK)
}

// FONT_SPACING :: f32(.2)
// FONT_SIZE :: f32(16)
// UI_SPACING :: 6
// UI_CORNER_PAD :: [2]f32 { UI_SPACING, UI_SPACING }

// create new game
// refresh
// list
// -- map radius
// -- player count

@(private="file")
wrapClamp :: proc(value: int, min: int, max: int) -> int {
	if value < min do return max
	else if value > max do return min
	else do return value
}