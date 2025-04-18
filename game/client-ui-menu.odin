
package game

import "ui"
import "networking"

import "core:fmt"
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

menuState: MenuState = {
	ngr = {
		mapRadius = 16,
		playerCount = 2,
		mapSeed = -1,
		name = clientState.name
	}
}

drawMenu :: proc() {
	switch menuState.status {
		case .MAIN: drawMain()
		case .NEW_GAME: drawNGRMenu()
	}
}

@(private="file")
drawMain :: proc() {
	menuNavigation(max(3, len(menuState.sessions) + 2 - 1))

	if rl.IsKeyPressed(.ENTER) {
		switch i := menuState.index; i {
			case 0:
				// start requesting new game
				if !menuState.ngrSent do menuState.status = .NEW_GAME
			case 1:
				// request session list
				message := networking.MessageHeader {
					message = .UPDATE
				}
				networking.say(
					clientState.serverSocket,
					&message
				)
			case i > 1 && len(menuState.sessions) > 0:
				clientState.status = .CONNECTING
				
		}
	}

	drawItemButton("REQUEST A NEW GAME", 0, menuState.ngrSent ? rl.GRAY : rl.BLACK)
	drawItemButton("REFRESH SESSION LIST", 1)
	for session, i in menuState.sessions {
		drawItemButton(
			fmt.aprintf(
				"R%d P%d %s",
				session.config.mapRadius,
				session.config.playerCount,
				session.config.name
			),
			i + 2
		)
	}
	if len(menuState.sessions) == 0 {
		drawItemButton("<NO AVAILABLE SESSIONS FOUND>", 2)
	}
	drawSelectorBullet({100, 100}, 20)
}

@(private="file")
drawNGRMenu :: proc() {
	menuNavigation(4)

	if rl.IsKeyPressed(.ENTER) {
		switch i := menuState.index; i {
			case 0:
				// go back
				menuState.status = .MAIN
			case i == 1 && !menuState.ngrSent:
				// request session list
				message := networking.MessageHeader {
					message = .ORDERS,
				}
				fmt.println(menuState.ngr)

				networking.say(
					clientState.serverSocket,
					&message,
					encode(menuState.ngr)
				)
				menuState.ngrSent = true
				menuState.status = .MAIN
		}
	}

	left := rl.IsKeyPressed(.LEFT)  || rl.IsKeyPressed(.A) || rl.IsKeyPressedRepeat(.LEFT)  || rl.IsKeyPressedRepeat(.A)
	rite := rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D) || rl.IsKeyPressedRepeat(.RIGHT) || rl.IsKeyPressedRepeat(.D)
	switch menuState.index {
		case 2:
			if left do menuState.ngr.mapRadius -= 1
			if rite do menuState.ngr.mapRadius += 1
		case 3:
			if left do menuState.ngr.playerCount -= 1
			if rite do menuState.ngr.playerCount += 1
	}

	menuState.ngr.mapRadius = clamp(menuState.ngr.mapRadius, 4, 64)
	menuState.ngr.playerCount = clamp(menuState.ngr.playerCount, 2, 6)

	drawItemButton("< BACK", 0)
	drawItemButton("REQUEST NEW GAME", 1)
	drawItemButton(fmt.aprintf("MAP RADIUS: %d TILES", menuState.ngr.mapRadius), 2)
	drawItemButton(fmt.aprintf("PLAYERS: %d", menuState.ngr.playerCount), 3)
}


@(private="file")
menuNavigation :: proc(listLength: int) {
	if rl.IsKeyPressed(.UP) do menuState.index -= 1
	if rl.IsKeyPressed(.DOWN) do menuState.index += 1
	menuState.index = wrapClamp(menuState.index, 0, listLength - 1)
}

@(private="file")
drawItemButton :: proc(caption: string, offset: int, color := rl.BLACK) {
	bulletRadius := FONT_SIZE * .42
	bulletSpace := bulletRadius * 2

	origin := [2]f32 {
		UI_CORNER_PAD.x,
		f32(ui.windowSize.y) * .5 - FONT_SIZE * .5
	}
	indexDisplacement := offset - menuState.index
	vOffset := f32(indexDisplacement) * (FONT_SIZE + UI_SPACING)
	alpha := clamp(f32(1) - abs(f32(indexDisplacement)) * .25, .5, 1.0)

	color := color
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

@(private="file")
drawSelectorBullet :: proc(origin: [2]f32, radius: f32) {
	ray := rl.Vector2 { radius, 0 }
	v0 := origin + ray;
	v1 := origin + rl.Vector2Rotate(ray, 6.28 * .33)
	v2 := origin + rl.Vector2Rotate(ray, 6.28 * .66)
	rl.DrawTriangle(v2, v1, v0, rl.BLACK)
}

@(private="file")
wrapClamp :: proc(value: int, min: int, max: int) -> int {
	if value < min do return max
	else if value > max do return min
	else do return value
}
