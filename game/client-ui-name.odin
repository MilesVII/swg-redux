package game

import rl "vendor:raylib"

import "core:fmt"
import "core:strings"

import "ui"
import "utils"

// asks for a player name when neither the command line nor config.toml provided one

@(private="file")
PROMPT_WIDTH :: f32(360)
@(private="file")
PROMPT_ROW :: FONT_SIZE + UI_SPACING * 1.5
@(private="file")
HINT_COLOR :: rl.Color { 150, 150, 150, 255 }

@(private="file")
namePrompt: struct {
	// uppercase letters and digits only, at most a badge long
	text: [utils.BADGE_SIZE]u8,
	length: int
}

@(private="file")
acceptedCharacter :: proc(r: rune) -> (u8, bool) {
	switch r {
		case 'A'..='Z', '0'..='9': return u8(r), true
		case 'a'..='z': return u8(r - 'a' + 'A'), true
	}
	return 0, false
}

// asks before leaving a running game for the lobby, keys are handled in handleClientHotkeys
@(private)
drawLeavePrompt :: proc() {
	windowSize := ui.windowSizeF()
	height := PROMPT_ROW * 2 + UI_SPACING * 3
	box := rl.Rectangle {
		f32(int((windowSize.x - PROMPT_WIDTH) * .5)),
		f32(int((windowSize.y - height) * .5)),
		PROMPT_WIDTH,
		height
	}
	rl.DrawRectangleRec(box, { 0, 0, 0, 200 })
	rl.DrawRectangleLinesEx(box, 1, rl.WHITE)

	x := box.x + UI_SPACING * 2
	y := box.y + UI_SPACING
	rl.DrawTextEx(vcrFont, "LEAVE THE GAME?", { x, y + (PROMPT_ROW - FONT_SIZE) * .5 }, FONT_SIZE, FONT_SPACING, rl.YELLOW)
	y += PROMPT_ROW + UI_SPACING
	rl.DrawTextEx(vcrFont, "ENTER TO LEAVE, ESC TO STAY", { x, y + (PROMPT_ROW - FONT_SIZE) * .5 }, FONT_SIZE, FONT_SPACING, HINT_COLOR)
}

// input and drawing, called with the HUD while the client waits for a name
@(private)
drawNamePrompt :: proc() {
	for {
		r := rl.GetCharPressed()
		if r == 0 do break
		c, ok := acceptedCharacter(r)
		if !ok || namePrompt.length >= len(namePrompt.text) do continue
		namePrompt.text[namePrompt.length] = c
		namePrompt.length += 1
		rl.PlaySound(buttonSound)
	}
	if (rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE)) && namePrompt.length > 0 {
		namePrompt.length -= 1
		rl.PlaySound(buttonSound)
	}
	if (rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER)) && namePrompt.length > 0 {
		rl.PlaySound(menuSound)
		clientState.name = strings.clone(string(namePrompt.text[:namePrompt.length]))
		postponeGenericAction(startClientSession)
	}

	windowSize := ui.windowSizeF()
	height := PROMPT_ROW * 3 + UI_SPACING * 4
	box := rl.Rectangle {
		f32(int((windowSize.x - PROMPT_WIDTH) * .5)),
		f32(int((windowSize.y - height) * .5)),
		PROMPT_WIDTH,
		height
	}
	rl.DrawRectangleRec(box, { 0, 0, 0, 200 })
	rl.DrawRectangleLinesEx(box, 1, rl.WHITE)

	x := box.x + UI_SPACING * 2
	y := box.y + UI_SPACING
	text :: proc(x, y: f32, caption: cstring, color: rl.Color) {
		rl.DrawTextEx(vcrFont, caption, { x, y + (PROMPT_ROW - FONT_SIZE) * .5 }, FONT_SIZE, FONT_SPACING, color)
	}

	text(x, y, "ENTER YOUR NAME", rl.YELLOW)
	y += PROMPT_ROW + UI_SPACING

	field := rl.Rectangle { x - UI_SPACING, y, PROMPT_WIDTH - UI_SPACING * 2, PROMPT_ROW }
	rl.DrawRectangleRec(field, { 255, 255, 255, 25 })
	rl.DrawRectangleLinesEx(field, 1, rl.WHITE)
	name := fmt.ctprintf("%s", string(namePrompt.text[:namePrompt.length]))
	text(x, y, name, rl.WHITE)
	// blinking caret after the text
	if utils.flicker < .5 {
		width := rl.MeasureTextEx(vcrFont, name, FONT_SIZE, FONT_SPACING).x
		caretX := x + width + (namePrompt.length > 0 ? FONT_SPACING * 2 : 0)
		rl.DrawRectangleRec({ caretX, y + (PROMPT_ROW - FONT_SIZE) * .5, 2, FONT_SIZE }, rl.WHITE)
	}
	y += PROMPT_ROW + UI_SPACING

	text(x, y, "A-Z 0-9, ENTER TO CONFIRM", HINT_COLOR)
}
