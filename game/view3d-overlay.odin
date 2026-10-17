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

// straight line for direct fire, a dashed ballistic arc for indirect
@(private="file")
overlayShot3D :: proc(from: hex.Axial, to: hex.Axial, color: rl.Color, indirekt: bool) {
	a := cellTop3D(from) + { 0, .3, 0 }
	b := cellTop3D(to) + { 0, .06, 0 }
	distance := rl.Vector3Length(b - a)
	segments := indirekt ? 48 : 1
	apex := .8 + distance * .3

	point :: proc(a, b: rl.Vector3, t: f32, apex: f32, indirekt: bool) -> rl.Vector3 {
		p := a + (b - a) * t
		if indirekt do p.y += 4 * apex * t * (1 - t)
		return p
	}

	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for i in 0..<segments {
		t0 := f32(i) / f32(segments)
		t1 := f32(i + 1) / f32(segments)
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
