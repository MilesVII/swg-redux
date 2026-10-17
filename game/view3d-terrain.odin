package game

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "hex"

TERRAIN_MIN_HEIGHT :: f32(.18)
WATER_HEIGHT :: f32(.11)
TERRAIN_FADE_S :: f32(.7)

// how much of a tile is drawn, through dithering
COVERAGE_OBSERVED :: f32(1)
COVERAGE_KNOWN :: f32(.45)
COVERAGE_UNKNOWN :: f32(.3)

// mountains are white above this height
SNOW_LINE :: TERRAIN_MIN_HEIGHT + f32(1.25)

@(private="file")
SNOW_COLOR :: [3]f32 { .92, .94, .97 }
@(private="file")
FOG_COLOR :: [3]f32 { .30, .31, .34 }
@(private="file")
GOLD_COLOR :: [3]f32 { 1, .80, .18 }

// everything a tile's geometry depends on
@(private="file")
CellLook :: struct {
	present: bool,
	height: f32,
	color: [3]u8,
	// walls below the snow line
	side: [3]u8,
	// 0 when the tile has no snow
	snowLine: f32,
	coverage: f32,
	gold: bool
}

@(private="file")
terrain: struct {
	shader: rl.Shader,
	material: rl.Material,
	mesh: rl.Mesh,
	meshLoaded: bool,

	groundShader: rl.Shader,
	groundNoise: [2]f32,

	// rebuilt when the client applies a new state
	builtVersion: int,
	radius: int,
	looks: []CellLook,
	fadeStart: []f32,
	maxHeight: f32
}

initTerrain3D :: proc() {
	terrain.shader = rl.LoadShader("shaders/terrain-vs.glsl", "shaders/terrain-fs.glsl")
	terrain.material = rl.LoadMaterialDefault()
	terrain.material.shader = terrain.shader
	terrain.groundShader = rl.LoadShader("shaders/ground-vs.glsl", "shaders/ground-fs.glsl")
	terrain.builtVersion = -1
}

deinitTerrain3D :: proc() {
	if terrain.meshLoaded do rl.UnloadMesh(terrain.mesh)
	rl.UnloadShader(terrain.shader)
	rl.UnloadShader(terrain.groundShader)
	delete(terrain.looks)
	delete(terrain.fadeStart)
}

// top of the tile as currently drawn, 0 off the map
terrainHeight3D :: proc(at: hex.Axial) -> f32 {
	if terrain.radius == 0 || !hex.isWithinGrid(at, terrain.radius) do return 0
	look := terrain.looks[hex.axialToIndex(at, terrain.radius)]
	return look.present ? look.height : 0
}

terrainMaxHeight3D :: proc() -> f32 {
	return terrain.maxHeight
}

syncTerrain3D :: proc() {
	if terrain.builtVersion == clientStateVersion do return
	terrain.builtVersion = clientStateVersion
	rebuildTerrain3D()
}

// `revealed` shows the whole map at game over, where cells keep their initial fog value
@(private="file")
lookOf :: proc(cell: hex.Cell(hex.GridCell), revealed: bool) -> CellLook {
	if !cell.visible do return {}
	value := cell.value
	if revealed do value.fog = .OBSERVED
	elevation := clamp(value.elevation, 0, 1)

	look := CellLook { present = true, gold = value.gold > 0 }
	switch value.fog {
		case .OBSERVED: look.coverage = COVERAGE_OBSERVED
		case .TERRAIN:  look.coverage = COVERAGE_KNOWN
		case .FOG:      look.coverage = COVERAGE_UNKNOWN
	}

	base := [3]f32 { f32(value.color.r), f32(value.color.g), f32(value.color.b) } / 255
	color: [3]f32
	switch {
		case value.fog == .FOG:
			look.height = TERRAIN_MIN_HEIGHT
			color = FOG_COLOR
		case value.color == rl.BLUE:
			look.height = WATER_HEIGHT
			color = base * (.55 + elevation * 1.4)
		case value.color == MOUNTAIN_COLOR:
			rise := max(elevation - .75, 0)
			look.height = TERRAIN_MIN_HEIGHT + .22 + rise * 8.5
			color = base * (.85 + rise * 1.5)
		case:
			rise := max(elevation - .25, 0)
			look.height = TERRAIN_MIN_HEIGHT + rise * .4
			color = base * (.62 + rise * .9)
	}

	look.side = toBytes(color)
	look.color = look.side
	if value.color == MOUNTAIN_COLOR && value.fog != .FOG && look.height > SNOW_LINE {
		look.snowLine = SNOW_LINE
		look.color = toBytes(SNOW_COLOR)
	}
	return look
}

@(private="file")
toBytes :: proc(color: [3]f32) -> [3]u8 {
	return {
		u8(clamp(color.r, 0, 1) * 255),
		u8(clamp(color.g, 0, 1) * 255),
		u8(clamp(color.b, 0, 1) * 255)
	}
}

@(private="file")
sameLook :: proc(a, b: CellLook) -> bool {
	return a.present == b.present &&
		abs(a.height - b.height) < 1e-4 &&
		a.color == b.color &&
		a.side == b.side &&
		a.snowLine == b.snowLine &&
		a.coverage == b.coverage &&
		a.gold == b.gold
}

// non-indexed vertex streams for one terrain mesh
@(private="file")
TerrainBuilder :: struct {
	positions: [dynamic]f32,
	normals: [dynamic]f32,
	colors: [dynamic]u8,
	fades: [dynamic]f32,
	extras: [dynamic]f32,
	others: [dynamic]f32,

	// per emitted cell
	start: f32,
	coverage: f32,
	fadeOut: bool,
	other: f32
}

@(private="file")
vertex :: proc(b: ^TerrainBuilder, p: rl.Vector3, n: rl.Vector3, color: [3]u8, rim: f32) {
	append(&b.positions, p.x, p.y, p.z)
	append(&b.normals, n.x, n.y, n.z)
	append(&b.colors, color.r, color.g, color.b, 255)
	append(&b.fades, b.start, b.coverage)
	append(&b.extras, rim, b.fadeOut ? f32(1) : f32(0))
	append(&b.others, b.other, 0, 0, 0)
}

// emits a triangle wound counter-clockwise around `n`
@(private="file")
triangle :: proc(
	b: ^TerrainBuilder,
	p0, p1, p2: rl.Vector3,
	n: rl.Vector3,
	color: [3]u8,
	rims := [3]f32 { 0, 0, 0 }
) {
	if rl.Vector3DotProduct(rl.Vector3CrossProduct(p1 - p0, p2 - p0), n) >= 0 {
		vertex(b, p0, n, color, rims[0])
		vertex(b, p1, n, color, rims[1])
		vertex(b, p2, n, color, rims[2])
	} else {
		vertex(b, p0, n, color, rims[0])
		vertex(b, p2, n, color, rims[2])
		vertex(b, p1, n, color, rims[1])
	}
}

// hex prism from `bottomOf(edge)` up to `top`, walls are skipped where the neighbor is as tall
@(private="file")
prism :: proc(
	b: ^TerrainBuilder,
	at: hex.Axial,
	scale: f32,
	bottom: f32,
	top: f32,
	color: [3]u8,
	side: [3]u8,
	snowLine: f32,
	neighbors: []CellLook,
	outlined: bool
) {
	center := hex.axialToWorld(at)
	corners := hex.vertesex(at, scale)
	up := rl.Vector3 { 0, 1, 0 }
	c3 := rl.Vector3 { center.x, top, center.y }

	for k in 0..<6 {
		a := corners[k]
		z := corners[(k + 1) % 6]
		a3 := rl.Vector3 { a.x, top, a.y }
		z3 := rl.Vector3 { z.x, top, z.y }
		rim := outlined ? f32(1) : 0
		triangle(b, c3, a3, z3, up, color, { 0, rim, rim })

		wallBottom := bottom
		if neighbors != nil {
			middle := (a + z) * .5
			neighbor := hex.worldToAxial(center + (middle - center) * 2)
			wallBottom = 0
			if hex.isWithinGrid(neighbor, terrain.radius) {
				look := neighbors[hex.axialToIndex(neighbor, terrain.radius)]
				if look.present do wallBottom = look.height
			}
		}
		if wallBottom >= top - 1e-4 do continue

		outward := rl.Vector3Normalize({ (a.x + z.x) * .5 - center.x, 0, (a.y + z.y) * .5 - center.y })
		wall :: proc(b: ^TerrainBuilder, a, z: rl.Vector2, from, to: f32, outward: rl.Vector3, color: [3]u8) {
			if to <= from do return
			at := rl.Vector3 { a.x, to, a.y }
			zt := rl.Vector3 { z.x, to, z.y }
			ab := rl.Vector3 { a.x, from, a.y }
			zb := rl.Vector3 { z.x, from, z.y }
			triangle(b, at, zt, zb, outward, color)
			triangle(b, at, zb, ab, outward, color)
		}
		if snowLine > 0 {
			split := clamp(snowLine, wallBottom, top)
			wall(b, a, z, wallBottom, split, outward, side)
			wall(b, a, z, split, top, outward, color)
		} else {
			wall(b, a, z, wallBottom, top, outward, side)
		}
	}
}

@(private="file")
emitCell :: proc(b: ^TerrainBuilder, at: hex.Axial, look: CellLook, neighbors: []CellLook) {
	prism(b, at, 1, 0, look.height, look.color, look.side, look.snowLine, neighbors, true)
	if look.gold {
		goldColor := GOLD_COLOR * 255
		gold := [3]u8 { u8(goldColor.r), u8(goldColor.g), u8(goldColor.b) }
		prism(b, at, .42, look.height, look.height + .09, gold, gold, 0, nil, false)
	}
}

@(private="file")
rebuildTerrain3D :: proc() {
	grid := clientState.game.grid
	now := time3D

	if grid.radius != terrain.radius || len(terrain.looks) != len(grid.cells) {
		delete(terrain.looks)
		delete(terrain.fadeStart)
		terrain.radius = grid.radius
		terrain.looks = make([]CellLook, len(grid.cells))
		terrain.fadeStart = make([]f32, len(grid.cells))
	}

	previous := terrain.looks
	looks := make([]CellLook, len(grid.cells))
	defer {
		delete(previous)
		terrain.looks = looks
	}

	terrain.maxHeight = 0
	revealed := clientState.status == .FINISH
	for cell, i in grid.cells {
		looks[i] = lookOf(cell, revealed)
		if looks[i].present do terrain.maxHeight = max(terrain.maxHeight, looks[i].height + .1)
	}

	b: TerrainBuilder
	defer {
		delete(b.positions)
		delete(b.normals)
		delete(b.colors)
		delete(b.fades)
		delete(b.extras)
		delete(b.others)
	}

	for cell, i in grid.cells {
		old := previous[i]
		new := looks[i]
		at := cell.position.axial

		if sameLook(old, new) {
			if !new.present do continue
			b.start = terrain.fadeStart[i]
			b.coverage = new.coverage
			b.fadeOut = false
			b.other = 0
			emitCell(&b, at, new, looks)
			continue
		}

		if old.present {
			b.start = now
			b.coverage = old.coverage
			b.fadeOut = true
			b.other = new.present ? new.coverage : 0
			emitCell(&b, at, old, previous)
		}
		if new.present {
			b.start = now
			b.coverage = new.coverage
			b.fadeOut = false
			b.other = 0
			emitCell(&b, at, new, looks)
			terrain.fadeStart[i] = now
		}
	}

	if terrain.meshLoaded {
		rl.UnloadMesh(terrain.mesh)
		terrain.meshLoaded = false
	}
	vertexCount := len(b.positions) / 3
	if vertexCount == 0 do return

	mesh := rl.Mesh {
		vertexCount = i32(vertexCount),
		triangleCount = i32(vertexCount / 3),
		vertices = raw_data(b.positions),
		normals = raw_data(b.normals),
		colors = raw_data(b.colors),
		texcoords = raw_data(b.fades),
		texcoords2 = raw_data(b.extras),
		tangents = raw_data(b.others),
	}
	rl.UploadMesh(&mesh, false)
	// the arrays belong to Odin's allocator, raylib must not free them
	mesh.vertices = nil
	mesh.normals = nil
	mesh.colors = nil
	mesh.texcoords = nil
	mesh.texcoords2 = nil
	mesh.tangents = nil
	terrain.mesh = mesh
	terrain.meshLoaded = true
}

// light uniforms shared by the terrain, unit and particle shaders
setLightUniforms3D :: proc(shader: rl.Shader) {
	lights, count := activeLights3D()
	sun := SUN_DIRECTION
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "sunDirection"), &sun, .VEC3)
	rl.SetShaderValueV(shader, rl.GetShaderLocation(shader, "lights"), &lights, .VEC4, 8)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "lightCount"), &count, .INT)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "ditherScale"), &ditherScale, .FLOAT)
}

drawTerrain3D :: proc() {
	if !terrain.meshLoaded do return

	shader := terrain.shader
	fade := TERRAIN_FADE_S
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "time"), &time3D, .FLOAT)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "fadeDuration"), &fade, .FLOAT)
	setLightUniforms3D(shader)

	rl.DrawMesh(terrain.mesh, terrain.material, rl.Matrix(1))
}

// the 2D client's backdrop as a ground plane under and around the map
drawGround3D :: proc() {
	shader := terrain.groundShader
	terrain.groundNoise += rl.GetFrameTime() * hex.BASIS_Y * 1.2
	radius := f32(max(terrain.radius, 8))
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "noiseOffset"), &terrain.groundNoise, .VEC2)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "mapRadius"), &radius, .FLOAT)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "ditherScale"), &ditherScale, .FLOAT)

	size := radius + 16
	y := f32(-.01)
	rl.BeginShaderMode(shader)
	rlgl.DisableBackfaceCulling()
	rlgl.Begin(rlgl.QUADS)
		rlgl.Color4ub(255, 255, 255, 255)
		rlgl.Vertex3f(-size, y, -size)
		rlgl.Vertex3f(-size, y, size)
		rlgl.Vertex3f(size, y, size)
		rlgl.Vertex3f(size, y, -size)
	rlgl.End()
	rl.EndShaderMode()
	rlgl.EnableBackfaceCulling()
}
