package game

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "ui"
import "hex"
import "shaded"

// the original top-down renderer
VIEW_2D := ClientView {
	name = "2D",
	update = update2D,
	scene = scene2D,
	focus = focus2D,
	toScreen = toScreen2D,
}

@(private="file")
update2D :: proc(cameraLocked: bool, inputBlocked: bool) {
	ui.update2DCamera(cameraLocked || inputBlocked)
}

@(private="file")
focus2D :: proc(at: hex.Axial) {
	ui.camera.target = hex.axialToWorld(at)
}

@(private="file")
toScreen2D :: proc(at: hex.Axial) -> rl.Vector2 {
	return rl.GetWorldToScreen2D(hex.axialToWorld(at), ui.camera)
}

@(private="file")
scene2D :: proc() {
	rl.BeginMode2D(ui.camera)
	defer rl.EndMode2D()

	drawBackground2D()
	if !showsGame() do return

	ui.drawGrid(clientState.game.grid)

	// scrap: a dark MCV silhouette
	for cell in clientState.game.grid.cells {
		if !cell.visible || !cell.value.scrap do continue
		ui.drawTriangle(cell.position.axial, true, SCRAP_COLOR_2D, .7)
		ui.drawTriangle(cell.position.axial, false, SCRAP_COLOR_2D, .7)
	}

	cell, hovering := hoverCell.?
	if hovering do ui.drawCellBorder(cell, .2, rl.WHITE)

	for &player, pix in clientState.game.players {
		for &unit in player.units {
			ordered := unit.id in clientState.orders
			highlight := canPlanOrders() && pix == clientState.myPix && !ordered
			drawUnit(
				unit.position,
				unit.type,
				unit.gold,
				player.color,
				highlight,
				unit.hidden
			)
		}
	}

	if clientUpdateAnimationsPending {
		for bonk in clientState.explosions {
			if bonk.elapsedTime == 0 do continue
			ui.drawExplosion(bonk.at, bonk.elapsedTime / (EXPLOSION_HATTRICK_S * 2.0), &sweepShader)
		}
	}

	drawOverlays2D()
	drawCounterBatterySigns2D()
}

@(private="file")
drawBackground2D :: proc() {
	rl.ClearBackground(rl.RAYWHITE)
	shaded.updateBackgroundShader(&backgroundShader, ui.camera.offset, ui.camera.zoom)
	rl.BeginShaderMode(backgroundShader.shader)

	from := rl.GetScreenToWorld2D([2]f32 {0, 0}, ui.camera)
	to := rl.GetScreenToWorld2D(ui.windowSizeF(), ui.camera)

	rl.DrawRectanglePro(
		rl.Rectangle {
			x = from.x,
			y = from.y,
			width = to.x - from.x,
			height = to.y - from.y
		},
		rl.Vector2 {0, 0},
		0,
		rl.WHITE
	)
	rl.EndShaderMode()
}

@(private="file")
SCRAP_COLOR_2D :: rl.Color { 40, 40, 44, 255 }

@(private="file")
drawCounterBatterySigns2D :: proc() {
	if len(counterBatterySigns) == 0 do return
	scale := f32(2)
	rl.SetShaderValue(ditherShader, rl.GetShaderLocation(ditherShader, "ditherScale"), &scale, .FLOAT)
	rl.BeginShaderMode(ditherShader)
	rlgl.DisableBackfaceCulling()
	rlgl.Begin(rlgl.TRIANGLES)
	for sign in counterBatterySigns {
		q := counterBatteryQuad(sign)
		rlgl.Color4ub(255, 40, 30, u8(255 * counterBatteryCoverage(sign)))
		for i in ([]int { 0, 1, 2, 0, 2, 3 }) do rlgl.Vertex2f(q[i].x, q[i].y)
	}
	rlgl.End()
	rlgl.EnableBackfaceCulling()
	rl.EndShaderMode()
}

@(private="file")
drawOverlays2D :: proc() {
	for command in overlays {
		switch c in command {
			case OverlayCell:
				ui.drawCellBorder(c.at, c.thickness, c.color)
			case OverlayArea:
				ui.drawOutline(hex.outline(c.cells, allocator = context.temp_allocator), c.color)
			case OverlayPath:
				if len(c.path) > 2 do ui.drawPath(c.path, .12, c.color, &stripeShader)
			case OverlayShot:
				ui.drawHexLine(c.from, c.to, .12, c.color, c.indirekt ? 1.5 : 0.5)
			case OverlayGhost:
				// the build target border is enough in 2D
			case OverlayRing:
				for edge in hex.rangeBoundary(c.center, c.radius, context.temp_allocator) {
					for dash in RING_DASHES {
						ui.drawLine(edge.a + (edge.b - edge.a) * dash[0], edge.a + (edge.b - edge.a) * dash[1], .07, c.color)
					}
				}
		}
	}
}
