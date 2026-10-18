package game

import rl "vendor:raylib"

import "core:math"
import "core:fmt"
import "core:strings"

import "hex"
import "ui"
import "utils"

UNIT_FADE_S :: f32(.5)
// world units per second along the path
UNIT_SPEED :: f32(3)
UNIT_MIN_MOVE_S :: f32(.35)

// drop-in models, looked up as assets/models/<type>.<extension>
// authored in hex units (neighbor centers are 1 apart), base at the origin, facing +Z
@(private="file")
MODEL_NAMES := [GameUnitType]string { .TONK = "tonk", .GUN = "gun", .MCV = "mcv" }
@(private="file")
MODEL_EXTENSIONS := [?]string { "glb", "gltf", "obj", "iqm", "m3d" }

// placeholder shapes made of boxes: offset, size, tilt around X in degrees
@(private="file")
Box :: struct {
	offset: rl.Vector3,
	size: rl.Vector3,
	tilt: f32
}
@(private="file")
UNIT_BOXES := [GameUnitType][]Box {
	.TONK = {
		{ { 0, .09, 0 }, { .46, .16, .60 }, 0 },
		{ { 0, .23, -.03 }, { .28, .12, .30 }, 0 },
		{ { 0, .23, .26 }, { .07, .07, .34 }, 0 },
	},
	.GUN = {
		{ { 0, .07, 0 }, { .52, .12, .52 }, 0 },
		{ { 0, .19, 0 }, { .24, .14, .24 }, 0 },
		{ { 0, .32, .12 }, { .09, .09, .52 }, -38 },
	},
	.MCV = {
		{ { 0, .13, 0 }, { .52, .22, .66 }, 0 },
		{ { 0, .32, .16 }, { .36, .18, .24 }, 0 },
		{ { .12, .40, -.18 }, { .05, .30, .05 }, 0 },
	},
}
// how far gold marks float above the unit's base
@(private="file")
UNIT_HEIGHT := [GameUnitType]f32 { .TONK = .39, .GUN = .58, .MCV = .67 }
// placeholder boxes are authored a bit small
@(private="file")
BOX_SCALE :: f32(1.15)

@(private="file")
UnitVisual :: struct {
	type: GameUnitType,
	color: rl.Color,
	gold: int,
	cell: hex.Axial,
	// route of the current move through cell centers at tile height, ends where the unit stands
	path: [dynamic]rl.Vector3,
	pathLength: f32,
	moveStart: f32,
	moveDuration: f32,
	// facing once the move is over
	heading: f32,
	fadeStart: f32,
	fadingOut: bool,
	seen: bool
}

@(private="file")
units: struct {
	shader: rl.Shader,
	material: rl.Material,
	cube: rl.Mesh,
	models: [GameUnitType]Maybe(rl.Model),
	// keyed by player index and unit id
	visuals: map[[2]int]UnitVisual
}

initUnits3D :: proc() {
	units.shader = rl.LoadShader("shaders/unit-vs.glsl", "shaders/unit-fs.glsl")
	units.material = rl.LoadMaterialDefault()
	units.material.shader = units.shader
	units.cube = rl.GenMeshCube(1, 1, 1)

	for name, type in MODEL_NAMES {
		for extension in MODEL_EXTENSIONS {
			path := strings.clone_to_cstring(fmt.tprintf("assets/models/%s.%s", name, extension), context.temp_allocator)
			if !rl.FileExists(path) do continue
			model := rl.LoadModel(path)
			if !rl.IsModelValid(model) do continue
			for i in 0..<model.materialCount do model.materials[i].shader = units.shader
			units.models[type] = model
			break
		}
	}
}

deinitUnits3D :: proc() {
	for model in units.models {
		if m, ok := model.?; ok {
			// the shader is ours, don't let UnloadModel take it
			for i in 0..<m.materialCount do m.materials[i].shader = {}
			rl.UnloadModel(m)
		}
	}
	rl.UnloadMesh(units.cube)
	rl.UnloadShader(units.shader)
	for _, v in units.visuals do delete(v.path)
	delete(units.visuals)
}

@(private="file")
easeInOut :: proc(t: f32) -> f32 {
	return t * t * (3 - 2 * t)
}

@(private="file")
Pose :: struct {
	position: rl.Vector3,
	heading: f32,
	pitch: f32
}

@(private="file")
flatLength :: proc(v: rl.Vector3) -> f32 {
	return math.sqrt(v.x * v.x + v.z * v.z)
}

// point `distance` along the path; heights change in a smooth ramp around each tile border
@(private="file")
pointOnPath :: proc(path: []rl.Vector3, distance: f32) -> rl.Vector3 {
	if len(path) == 0 do return {}
	travelled := f32(0)
	for i in 0..<len(path) - 1 {
		a := path[i]
		b := path[i + 1]
		length := flatLength(b - a)
		if distance <= travelled + length || i == len(path) - 2 {
			u := length > 1e-5 ? clamp((distance - travelled) / length, 0, 1) : 1
			ramp := clamp((u - .3) / .4, 0, 1)
			ramp = ramp * ramp * (3 - 2 * ramp)
			return { a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * ramp, a.z + (b.z - a.z) * u }
		}
		travelled += length
	}
	return path[len(path) - 1]
}

@(private="file")
moving :: proc(v: UnitVisual) -> bool {
	return len(v.path) > 1 && time3D - v.moveStart < v.moveDuration
}

// where the unit is and how it's oriented, following the slope while it moves
@(private="file")
poseOf :: proc(v: UnitVisual) -> Pose {
	if len(v.path) == 0 do return {}
	if !moving(v) do return { v.path[len(v.path) - 1], v.heading, 0 }

	t := clamp((time3D - v.moveStart) / v.moveDuration, 0, 1)
	distance := v.pathLength * easeInOut(t)
	position := pointOnPath(v.path[:], distance)

	// direction from a little behind to a little ahead, which also rounds the corners
	LOOK :: f32(.14)
	ahead := pointOnPath(v.path[:], min(distance + LOOK, v.pathLength))
	behind := pointOnPath(v.path[:], max(distance - LOOK, 0))
	direction := ahead - behind
	flat := flatLength(direction)
	if flat < 1e-4 do return { position, v.heading, 0 }
	return { position, math.atan2(direction.x, direction.z), math.atan2(direction.y, flat) }
}

// starts a move from wherever the unit is now to the center of `to`
@(private="file")
startMove :: proc(v: ^UnitVisual, to: hex.Axial) {
	start := poseOf(v^).position
	from := v.cell
	clear(&v.path)
	append(&v.path, start)

	cells, found := hex.findPath(clientState.game.grid, from, to, context.temp_allocator)
	if found {
		// paths run from the target back to the start, which is where the unit already is
		for i := len(cells) - 2; i >= 0; i -= 1 do append(&v.path, cellTop3D(cells[i]))
	} else {
		append(&v.path, cellTop3D(to))
	}

	v.pathLength = 0
	for i in 0..<len(v.path) - 1 do v.pathLength += flatLength(v.path[i + 1] - v.path[i])
	v.moveStart = time3D
	v.moveDuration = max(v.pathLength / UNIT_SPEED, UNIT_MIN_MOVE_S)

	last := v.path[len(v.path) - 1] - v.path[len(v.path) - 2]
	if flatLength(last) > 1e-3 do v.heading = math.atan2(last.x, last.z)
}

@(private="file")
coverageOf :: proc(v: UnitVisual) -> f32 {
	t := clamp((time3D - v.fadeStart) / UNIT_FADE_S, 0, 1)
	return v.fadingOut ? 1 - t : t
}

// follows the shown state: new units fade in, gone ones fade out, moved ones slide
syncUnits3D :: proc() {
	for _, &v in units.visuals do v.seen = false

	for player, pix in clientState.game.players {
		for unit in player.units {
			key := [2]int { pix, unit.id }
			target := cellTop3D(unit.position)

			v, exists := &units.visuals[key]
			if !exists {
				center := rl.Vector2 { 0, 0 } - hex.axialToWorld(unit.position)
				path := make([dynamic]rl.Vector3)
				append(&path, target)
				units.visuals[key] = UnitVisual {
					type = unit.type,
					color = player.color,
					gold = unit.gold,
					cell = unit.position,
					path = path,
					moveStart = -1000,
					// face the middle of the map until the first move
					heading = math.atan2(center.x, center.y),
					fadeStart = time3D,
					seen = true
				}
				continue
			}

			v.seen = true
			v.type = unit.type
			v.color = player.color
			v.gold = unit.gold
			if v.fadingOut {
				// came back before it was gone, fade in from where it was
				coverage := coverageOf(v^)
				v.fadingOut = false
				v.fadeStart = time3D - coverage * UNIT_FADE_S
			}
			if v.cell != unit.position {
				startMove(v, unit.position)
				v.cell = unit.position
			} else if !moving(v^) && abs(v.path[len(v.path) - 1].y - target.y) > 1e-4 {
				// the tile under it changed height
				clear(&v.path)
				append(&v.path, target)
			}
		}
	}

	gone := make([dynamic][2]int, context.temp_allocator)
	for key, &v in units.visuals {
		if !v.seen && !v.fadingOut {
			v.fadingOut = true
			v.fadeStart = time3D
		}
		if v.fadingOut && time3D - v.fadeStart >= UNIT_FADE_S do append(&gone, key)
	}
	for key in gone {
		delete(units.visuals[key].path)
		delete_key(&units.visuals, key)
	}
}

@(private="file")
setUnitUniforms :: proc(coverage: f32, glow: f32) {
	coverage := coverage
	glow := glow
	rl.SetShaderValue(units.shader, rl.GetShaderLocation(units.shader, "coverage"), &coverage, .FLOAT)
	rl.SetShaderValue(units.shader, rl.GetShaderLocation(units.shader, "glow"), &glow, .FLOAT)
}

@(private="file")
drawShape :: proc(type: GameUnitType, pose: Pose, scale: f32, color: rl.Color, coverage: f32, glow: f32) {
	setUnitUniforms(coverage, glow)
	position := pose.position
	// nose up when climbing: positive pitch tilts +Z towards +Y
	placement := rl.MatrixTranslate(position.x, position.y, position.z) *
		rl.MatrixRotateY(pose.heading) *
		rl.MatrixRotateX(-pose.pitch) *
		rl.MatrixScale(scale, scale, scale)

	if model, ok := units.models[type].?; ok {
		for i in 0..<model.meshCount {
			material := model.materials[model.meshMaterial[i]]
			material.maps[rl.MaterialMapIndex.ALBEDO].color = color
			rl.DrawMesh(model.meshes[i], material, placement * model.transform)
		}
		return
	}

	material := units.material
	material.maps[rl.MaterialMapIndex.ALBEDO].color = color
	placement = placement * rl.MatrixScale(BOX_SCALE, BOX_SCALE, BOX_SCALE)
	for box in UNIT_BOXES[type] {
		transform := placement *
			rl.MatrixTranslate(box.offset.x, box.offset.y, box.offset.z) *
			rl.MatrixRotateX(box.tilt * rl.DEG2RAD) *
			rl.MatrixScale(box.size.x, box.size.y, box.size.z)
		rl.DrawMesh(units.cube, material, transform)
	}
}

// slots of the bars above units: gold for MCVs, hit points for TONKs
@(private="file")
BAR_CAPACITY := [GameUnitType]int { .TONK = 2, .GUN = 0, .MCV = 3 }
@(private="file")
BAR_COLOR := [GameUnitType]rl.Color { .TONK = rl.RED, .GUN = rl.BLANK, .MCV = rl.GOLD }

// screen space bars above units, drawn with the HUD
drawUnitBars3D :: proc() {
	SEGMENT_WIDTH :: f32(11)
	SEGMENT_HEIGHT :: f32(5)
	GAP :: f32(2)
	PADDING :: f32(2)

	forward := rl.Vector3Normalize(camera3D.target - camera3D.position)
	for _, v in units.visuals {
		capacity := BAR_CAPACITY[v.type]
		if capacity == 0 do continue
		coverage := coverageOf(v)
		if coverage <= 0 do continue

		pose := poseOf(v)
		anchor := pose.position + { 0, UNIT_HEIGHT[v.type] + .12, 0 }
		if rl.Vector3DotProduct(anchor - camera3D.position, forward) <= 0 do continue
		screen := rl.GetWorldToScreen(anchor, camera3D)

		width := f32(capacity) * SEGMENT_WIDTH + f32(capacity - 1) * GAP
		x := math.round(screen.x - width * .5)
		y := math.round(screen.y - SEGMENT_HEIGHT)
		alpha := u8(255 * coverage)

		rl.DrawRectangleRec(
			{ x - PADDING, y - PADDING, width + PADDING * 2, SEGMENT_HEIGHT + PADDING * 2 },
			{ 0, 0, 0, u8(190 * coverage) }
		)
		filled := BAR_COLOR[v.type]
		filled.a = alpha
		empty := rl.Color { 70, 70, 70, alpha }
		for i in 0..<capacity {
			segment := rl.Rectangle { x + f32(i) * (SEGMENT_WIDTH + GAP), y, SEGMENT_WIDTH, SEGMENT_HEIGHT }
			rl.DrawRectangleRec(segment, i < v.gold ? filled : empty)
		}
	}
}

drawUnits3D :: proc() {
	setLightUniforms3D(units.shader)

	for _, v in units.visuals {
		coverage := coverageOf(v)
		if coverage <= 0 do continue
		pose := poseOf(v)
		hovered := v.cell == ui.pointedCell && !v.fadingOut
		drawShape(v.type, pose, hovered ? 1.12 : 1, v.color, coverage, 0)
	}

	// units that orders will build
	pulse := (math.sin(utils.flicker * utils.TAU) + 1) * .5
	for command in overlays {
		ghost, isGhost := command.(OverlayGhost)
		if !isGhost do continue
		drawShape(ghost.type, { cellTop3D(ghost.at), 0, 0 }, 1, ghost.color, .25 + pulse * .2, .3)
	}
}

// cells of your own units that still wait for orders
unitsAwaitingOrders3D :: proc() -> []hex.Axial {
	result := make([dynamic]hex.Axial, context.temp_allocator)
	if clientState.status != .PLAYING || clientState.myPix >= len(clientState.game.players) do return result[:]
	for unit in clientState.game.players[clientState.myPix].units {
		if !(unit.id in clientState.orders) do append(&result, unit.position)
	}
	return result[:]
}
