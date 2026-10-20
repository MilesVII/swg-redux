package game

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "core:math"

import "hex"
import "utils"

// keeps marks off the tile they lie on
@(private="file")
OVERLAY_LIFT :: f32(.025)
// marks hidden behind terrain still show this much
@(private="file")
XRAY_ALPHA :: f32(.28)

@(private="file")
withAlpha :: proc(color: rl.Color, alpha: f32) -> rl.Color {
	color := color
	color.a = u8(f32(color.a) * clamp(alpha, 0, 1))
	return color
}

@(private="file")
quad :: proc(a, b, c, d: rl.Vector3) {
	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.Vertex3f(c.x, c.y, c.z)
	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(c.x, c.y, c.z)
	rlgl.Vertex3f(d.x, d.y, d.z)
}

@(private="file")
lift :: proc(p: rl.Vector2, height: f32) -> rl.Vector3 {
	return { p.x, height, p.y }
}

overlayCellBorder3D :: proc(at: hex.Axial, thickness: f32, color: rl.Color, scale := f32(1)) {
	height := terrainHeight3D(at) + OVERLAY_LIFT
	inner := hex.vertesex(at, scale * (1 - thickness))
	outer := hex.vertesex(at, scale)

	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for k in 0..<6 {
		n := (k + 1) % 6
		quad(lift(inner[k], height), lift(outer[k], height), lift(outer[n], height), lift(inner[n], height))
	}
	rlgl.End()
}

// border around a set of cells, each edge at the height of the cell inside
@(private="file")
overlayArea3D :: proc(cells: []hex.Axial, color: rl.Color) {
	inside := make(map[hex.Axial]bool, len(cells), context.temp_allocator)
	for cell in cells do inside[cell] = true

	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for cell in cells {
		center := hex.axialToWorld(cell)
		height := terrainHeight3D(cell) + OVERLAY_LIFT
		inner := hex.vertesex(cell, .92)
		outer := hex.vertesex(cell, 1.12)
		for k in 0..<6 {
			n := (k + 1) % 6
			middle := (inner[k] + inner[n]) * .5
			neighbor := hex.worldToAxial(center + (middle - center) * 2 / .92)
			if neighbor in inside do continue
			quad(lift(inner[k], height), lift(outer[k], height), lift(outer[n], height), lift(inner[n], height))
		}
	}
	rlgl.End()
}

// dashed ribbon following the ground, marching from the unit to the target
@(private="file")
overlayPath3D :: proc(path: hex.Path, color: rl.Color) {
	if len(path) < 2 do return

	// paths run from the target back to the unit
	points := make([]rl.Vector2, len(path), context.temp_allocator)
	for cell, i in path do points[len(path) - 1 - i] = hex.axialToWorld(cell)
	points[0] = points[0] + (points[1] - points[0]) * .35

	STEP :: f32(.05)
	DASH :: f32(.32)
	WIDTH :: f32(.06)
	travelled := f32(0)

	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for i in 0..<len(points) - 1 {
		a := points[i]
		b := points[i + 1]
		length := rl.Vector2Length(b - a)
		if length < 1e-4 do continue
		direction := (b - a) / length
		side := rl.Vector2 { -direction.y, direction.x } * WIDTH

		for s := f32(0); s < length; s += STEP {
			e := min(s + STEP, length)
			phase := math.mod((travelled + s) / DASH - utils.flicker, 1)
			if phase < 0 do phase += 1
			if phase > .55 do continue

			p0 := a + direction * s
			p1 := a + direction * e
			h0 := terrainHeight3D(hex.worldToAxial(p0)) + OVERLAY_LIFT * 2
			h1 := terrainHeight3D(hex.worldToAxial(p1)) + OVERLAY_LIFT * 2
			quad(lift(p0 - side, h0), lift(p1 - side, h1), lift(p1 + side, h1), lift(p0 + side, h0))
		}
		travelled += length
	}
	rlgl.End()
}

// dashed range border following the tiles, each dash on the higher of the two tiles it runs between
@(private="file")
overlayRing3D :: proc(ring: OverlayRing, color: rl.Color) {
	WIDTH :: f32(.05)
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for edge in hex.rangeBoundary(ring.center, ring.radius, context.temp_allocator) {
		height := max(terrainHeight3D(edge.inside), terrainHeight3D(edge.outside)) + OVERLAY_LIFT * 2
		along := edge.b - edge.a
		side := rl.Vector2Normalize({ -along.y, along.x }) * WIDTH * .5
		for dash in RING_DASHES {
			p0 := edge.a + along * dash[0]
			p1 := edge.a + along * dash[1]
			quad(lift(p0 - side, height), lift(p1 - side, height), lift(p1 + side, height), lift(p0 + side, height))
		}
	}
	rlgl.End()
}

// straight line for direct fire, a dashed ballistic arc for indirect,
// both starting about a tile away so they don't cut through the shooter
@(private="file")
overlayShot3D :: proc(from: hex.Axial, to: hex.Axial, color: rl.Color, indirekt: bool) {
	START_OFFSET :: f32(.9)
	// direct fire stops at the target's edge like in 2D, shells land in its middle
	END_OFFSET :: f32(.5)

	a := cellTop3D(from) + { 0, .3, 0 }
	b := cellTop3D(to) + { 0, .06, 0 }
	distance := rl.Vector3Length(b - a)
	segments := indirekt ? 48 : 1
	apex := .8 + distance * .3

	// the arc is linear on the ground, so a share of the ground distance is a share of the curve;
	// adjacent targets keep at least half of their line
	flat := rl.Vector2Length({ b.x - a.x, b.z - a.z })
	start := flat > 1e-4 ? min(START_OFFSET / flat, .5) : 0
	end := indirekt || flat <= 1e-4 ? f32(1) : max(1 - END_OFFSET / flat, start + .1)

	point :: proc(a, b: rl.Vector3, t: f32, apex: f32, indirekt: bool) -> rl.Vector3 {
		p := a + (b - a) * t
		if indirekt do p.y += 4 * apex * t * (1 - t)
		return p
	}

	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for i in 0..<segments {
		t0 := start + (end - start) * f32(i) / f32(segments)
		t1 := start + (end - start) * f32(i + 1) / f32(segments)
		if indirekt {
			phase := math.mod(t0 * 10 - utils.flicker, 1)
			if phase < 0 do phase += 1
			if phase > .6 do continue
		}
		p0 := point(a, b, t0, apex, indirekt)
		p1 := point(a, b, t1, apex, indirekt)
		middle := (p0 + p1) * .5
		side := rl.Vector3Normalize(rl.Vector3CrossProduct(p1 - p0, camera3D.position - middle)) * .05
		quad(p0 - side, p1 - side, p1 + side, p0 + side)
	}
	rlgl.End()
}

@(private="file")
overlayPass :: proc(alpha: f32) {
	cell, hovering := hoverCell.?
	if hovering do overlayCellBorder3D(cell, .2, withAlpha(rl.WHITE, alpha))

	// your units without orders, pulsing like in 2D
	pulse := (math.sin(utils.flicker * utils.TAU) + 1) * .5
	for at in unitsAwaitingOrders3D() {
		overlayCellBorder3D(at, .2, withAlpha(rl.YELLOW, pulse * alpha))
	}

	for command in overlays {
		switch c in command {
			case OverlayCell:
				overlayCellBorder3D(c.at, c.thickness, withAlpha(c.color, alpha))
			case OverlayArea:
				overlayArea3D(c.cells, withAlpha(c.color, alpha))
			case OverlayPath:
				overlayPath3D(c.path, withAlpha(c.color, alpha))
			case OverlayShot:
				overlayShot3D(c.from, c.to, withAlpha(c.color, alpha), c.indirekt)
			case OverlayGhost:
				// drawn with the units
			case OverlayRing:
				overlayRing3D(c, withAlpha(c.color, alpha))
		}
	}

	drawExplosionMarkers3D(alpha)
}

drawOverlays3D :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.DisableDepthMask()

	overlayPass(1)
	rlgl.DrawRenderBatchActive()

	rlgl.DisableDepthTest()
	overlayPass(XRAY_ALPHA)
	rlgl.DrawRenderBatchActive()

	rlgl.EnableDepthTest()
	rlgl.EnableDepthMask()
	rlgl.EnableBackfaceCulling()
}

// counter-battery signs read like HUD marks: drawn last, over terrain, units and smoke
drawCounterBatterySigns3D :: proc() {
	if len(counterBatterySigns) == 0 do return
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.DisableDepthTest()
	rl.SetShaderValue(ditherShader, rl.GetShaderLocation(ditherShader, "ditherScale"), &ditherScale, .FLOAT)
	rl.BeginShaderMode(ditherShader)
	rlgl.Begin(rlgl.TRIANGLES)
	for sign in counterBatterySigns {
		q := counterBatteryQuad(sign)
		height := terrainHeight3D(sign.at) + OVERLAY_LIFT * 2
		rlgl.Color4ub(255, 40, 30, u8(255 * counterBatteryCoverage(sign)))
		for i in ([]int { 0, 1, 2, 0, 2, 3 }) do rlgl.Vertex3f(q[i].x, height, q[i].y)
	}
	rlgl.End()
	rl.EndShaderMode()
	rlgl.EnableDepthTest()
	rlgl.EnableBackfaceCulling()
}

// a tile one beyond the map's north-eastern corner, the two top sectors flanking
// the north vertex in red: north is -Z, up the screen in 2D and away from the default orbit
drawCompass3D :: proc() {
	radius := clientState.game.grid.radius
	if radius == 0 do return
	at := hex.Axial { radius + 2, -(radius + 2) }
	center := hex.axialToWorld(at)
	corners := hex.vertesex(at)
	top := TERRAIN_MIN_HEIGHT
	TOP_COLOR :: rl.Color { 44, 44, 48, 255 }
	WALL_COLOR :: rl.Color { 26, 26, 30, 255 }
	NEEDLE_COLOR :: rl.Color { 230, 40, 30, 255 }
	// corner 2 points north, see hex.vertesexRaw
	NORTH_CORNER :: 2

	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.Begin(rlgl.TRIANGLES)
	for k in 0..<6 {
		a := corners[k]
		b := corners[(k + 1) % 6]
		needle := k == NORTH_CORNER - 1 || k == NORTH_CORNER
		color := needle ? NEEDLE_COLOR : TOP_COLOR
		rlgl.Color4ub(color.r, color.g, color.b, color.a)
		for p in ([3]rl.Vector2 { center, a, b }) do rlgl.Vertex3f(p.x, top, p.y)

		rlgl.Color4ub(WALL_COLOR.r, WALL_COLOR.g, WALL_COLOR.b, WALL_COLOR.a)
		quad(lift(a, top), lift(b, top), lift(b, 0), lift(a, 0))
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
}
