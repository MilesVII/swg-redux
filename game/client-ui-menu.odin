
package game

import "ui"
import "utils"
import "networking"

import "core:fmt"
import "core:math"
import "core:net"
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
	animationOffset: f32,
	sessions: [dynamic]GameSession,
	lobbyAddress: net.Address
}

menuState: MenuState = {
	ngr = {
		mapRadius = 16,
		playerCount = 2,
		mapSeed = -1
	}
}

drawMenu :: proc() {
	menuState.animationOffset = decay(menuState.animationOffset, 6, rl.GetFrameTime())
	switch menuState.status {
		case .MAIN: drawMain()
		case .NEW_GAME: drawNGRMenu()
	}
}

@(private="file")
drawMain :: proc() {
	// two fixed items, then sessions or the placeholder
	menuNavigation(2 + max(1, len(menuState.sessions)))

	if rl.IsKeyPressed(.ENTER) {
		rl.PlaySound(menuSound)
		setNotice("")
		switch menuState.index {
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
			case:
				sessionIndex := menuState.index - 2
				if sessionIndex < 0 || sessionIndex >= len(menuState.sessions) do break
				joinLobbyGame(menuState.sessions[sessionIndex].port)
		}
	}

	drawItemButton("REQUEST A NEW GAME", 0, menuState.ngrSent ? rl.GRAY : rl.WHITE)
	drawItemButton("REFRESH SESSION LIST", 1)
	for session, i in menuState.sessions {
		drawItemButton(
			fmt.tprintf(
				"R%d P%d%s %s%s%s",
				session.config.mapRadius,
				session.config.playerCount,
				session.config.turnSeconds > 0 ? fmt.tprintf(" T%s", formatTurnTime(session.config.turnSeconds)) : "",
				session.config.name,
				session.yours ? " [YOURS]" : "",
				session.full ? " [IN PROGRESS]" : ""
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
	menuNavigation(5)

	if rl.IsKeyPressed(.ENTER) {
		rl.PlaySound(menuSound)
		switch menuState.index {
			case 0:
				// go back
				menuState.status = .MAIN
			case 1:
				if menuState.ngrSent do break
				// request a new game
				setNotice("")
				message := networking.MessageHeader {
					message = .ORDERS,
				}

				networking.say(
					clientState.serverSocket,
					&message,
					encode(menuState.ngr)
				)
				menuState.ngrSent = true
				menuState.status = .MAIN
		}
	}

	left := checkRepeatedInput(.LEFT, .A)
	rite := checkRepeatedInput(.RIGHT, .D)
	switch menuState.index {
		case 2:
			if left do menuState.ngr.mapRadius -= 1
			if rite do menuState.ngr.mapRadius += 1
		case 3:
			if left do menuState.ngr.playerCount -= 1
			if rite do menuState.ngr.playerCount += 1
		case 4:
			if left do menuState.ngr.turnSeconds -= NGR_TURN_STEP
			if rite do menuState.ngr.turnSeconds += NGR_TURN_STEP
	}

	if left || rite do rl.PlaySound(buttonSound)

	menuState.ngr.mapRadius = clamp(menuState.ngr.mapRadius, NGR_RADIUS_RANGE[0], NGR_RADIUS_RANGE[1])
	menuState.ngr.playerCount = clamp(menuState.ngr.playerCount, NGR_PLAYERS_RANGE[0], NGR_PLAYERS_RANGE[1])
	menuState.ngr.turnSeconds = clamp(menuState.ngr.turnSeconds, NGR_TURN_RANGE[0], NGR_TURN_RANGE[1])

	drawItemButton("< BACK", 0)
	drawItemButton("REQUEST NEW GAME", 1)
	drawItemButton(fmt.tprintf("MAP RADIUS: %d TILES", menuState.ngr.mapRadius), 2)
	drawItemButton(fmt.tprintf("PLAYERS: %d", menuState.ngr.playerCount), 3)
	turn := menuState.ngr.turnSeconds
	drawItemButton(fmt.tprintf("TURN TIMER: %s", turn > 0 ? formatTurnTime(turn) : "OFF"), 4)
}

// minutes and seconds
formatTurnTime :: proc(seconds: int) -> string {
	return fmt.tprintf("%d:%02d", seconds / 60, seconds % 60)
}


@(private="file")
menuNavigation :: proc(listLength: int) {
	startIndex := menuState.index

	if checkRepeatedInput(.UP, .W) {
		rl.PlaySound(buttonSound)
		menuState.index -= 1
	}
	if checkRepeatedInput(.DOWN, .S) {
		rl.PlaySound(buttonSound)
		menuState.index += 1
	}
	menuState.index = wrapClamp(menuState.index, 0, listLength - 1)

	menuState.animationOffset += f32(startIndex - menuState.index)
}

@(private="file")
drawItemButton :: proc(caption: string, offset: int, color := rl.WHITE) {
	bulletRadius := FONT_SIZE * .42
	bulletSpace := bulletRadius * 2

	origin := [2]f32 {
		UI_CORNER_PAD.x,
		f32(ui.windowSize.y) * .5 - FONT_SIZE * .5
	}
	lineH := FONT_SIZE + UI_SPACING
	indexDisplacement := f32(offset - menuState.index)
	vOffset := (indexDisplacement - menuState.animationOffset) * lineH
	alpha := clamp(f32(1) - abs(indexDisplacement) * .25, .5, 1.0)

	color := color
	color.a = u8(255 * alpha)

	if offset == menuState.index {
		drawSelectorBullet(
			origin + {
				bulletRadius,
				FONT_SIZE * .5 - menuState.animationOffset * lineH
			},
			bulletRadius
		)
	}
	rl.DrawTextEx(
		vcrFont,
		strings.clone_to_cstring(caption, context.temp_allocator),
		origin + { bulletSpace + UI_SPACING, vOffset },
		FONT_SIZE,
		FONT_SPACING,
		color
	)
}

@(private="file")
drawSelectorBullet :: proc(origin: [2]f32, radius: f32) {
	ray := rl.Vector2 { radius, 0 }
	v0 := origin + ray
	v1 := origin + rl.Vector2Rotate(ray, utils.TAU * .33)
	v2 := origin + rl.Vector2Rotate(ray, utils.TAU * .66)
	rl.DrawTriangle(v2, v1, v0, rl.WHITE)
}

@(private="file")
wrapClamp :: proc(value: int, min: int, max: int) -> int {
	if value < min do return max
	else if value > max do return min
	else do return value
}

@(private="file")
decay :: proc(value: f32, decay: f32, dt: f32) -> f32 {
	return value * math.exp_f32(-decay * dt)
}

@(private="file")
checkRepeatedInput :: proc(keys: ..rl.KeyboardKey) -> bool {
	for key in keys {
		if rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key) do return true
	}
	return false
}

// session names are heap strings owned by the list
clearSessions :: proc() {
	for session in menuState.sessions do delete(session.config.name)
	clear(&menuState.sessions)
}
