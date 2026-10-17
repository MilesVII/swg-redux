package game

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "core:math"

import "ui"
import "hex"

// perspective renderer: hex prisms, unit models, particle explosions
VIEW_3D := ClientView {
	name = "3D",
	init = init3D,
	deinit = deinit3D,
	update = update3D,
	scene = scene3D,
	focus = proc(at: hex.Axial) {
		world := hex.axialToWorld(at)
		orbit.focus = { world.x, FOCUS_HEIGHT, world.y }
	},
	toScreen = proc(at: hex.Axial) -> rl.Vector2 {
		return rl.GetWorldToScreen(cellTop3D(at), camera3D)
	},
	onExplosionStart = explosionStart3D,
	onExplosionImpact = explosionImpact3D,
	settings = settings3D,
}

// "true isometric" elevation: atan(1 / sqrt(2))
DEFAULT_PITCH :: f32(35.264)
DEFAULT_FOV :: f32(30)
// half of the visible height around the focus point, in world units
DEFAULT_EXTENT :: f32(8)
@(private="file")
FOCUS_HEIGHT :: f32(.3)
@(private="file")
PITCH_RANGE :: [2]f32 { 10, 89 }
@(private="file")
FOV_RANGE :: [2]f32 { 4, 90 }
@(private="file")
EXTENT_RANGE :: [2]f32 { 1.5, 40 }
@(private="file")
ORBIT_SPEED :: f32(100) // degrees per second
@(private="file")
TILT_SPEED :: f32(45)

@(private="file")
Orbit :: struct {
	focus: rl.Vector3,
	// degrees
	yaw: f32,
	pitch: f32,
	fov: f32,
	extent: f32
}

@(private="file")
orbit := Orbit {
	pitch = DEFAULT_PITCH,
	fov = DEFAULT_FOV,
	extent = DEFAULT_EXTENT
}

@(private)
camera3D: rl.Camera3D
// shader clock, seconds
@(private)
time3D: f32
// size of a dithering cell in pixels
@(private)
ditherScale := f32(2)
@(private)
SUN_DIRECTION := rl.Vector3 { -0.42, 0.82, 0.38 }

// where the cursor ray hits the terrain
@(private="file")
pointer3D: rl.Vector3
@(private="file")
pointerHit: bool

@(private="file")
init3D :: proc() {
	SUN_DIRECTION = rl.Vector3Normalize(SUN_DIRECTION)
	initTerrain3D()
	initUnits3D()
	initFX3D()
	updateCamera3D()
}

@(private="file")
deinit3D :: proc() {
	deinitTerrain3D()
	deinitUnits3D()
	deinitFX3D()
}

@(private="file")
orbitDistance :: proc() -> f32 {
	return orbit.extent / math.tan(orbit.fov * rl.DEG2RAD * .5)
}

@(private="file")
updateCamera3D :: proc() {
	pitch := orbit.pitch * rl.DEG2RAD
	yaw := orbit.yaw * rl.DEG2RAD
	offset := rl.Vector3 {
		math.cos(pitch) * math.sin(yaw),
		math.sin(pitch),
		math.cos(pitch) * math.cos(yaw)
	} * orbitDistance()

	camera3D = rl.Camera3D {
		position = orbit.focus + offset,
		target = orbit.focus,
		up = { 0, 1, 0 },
		fovy = orbit.fov,
		projection = .PERSPECTIVE
	}
}

@(private="file")
update3D :: proc(cameraLocked: bool, inputBlocked: bool) {
	time3D = f32(rl.GetTime())
	dt := rl.GetFrameTime()

	pick3D()

	if !cameraLocked && !inputBlocked {
		yaw := orbit.yaw * rl.DEG2RAD
		// on the ground plane, away from the camera and to its right
		forward := rl.Vector3 { -math.sin(yaw), 0, -math.cos(yaw) }
		right := rl.Vector3 { math.cos(yaw), 0, -math.sin(yaw) }

		move := rl.Vector3 {}
		if rl.IsKeyDown(.W) do move += forward
		if rl.IsKeyDown(.S) do move -= forward
		if rl.IsKeyDown(.D) do move += right
		if rl.IsKeyDown(.A) do move -= right
		if rl.Vector3Length(move) > 0 {
			orbit.focus += rl.Vector3Normalize(move) * orbit.extent * 1.4 * dt
		}

		if rl.IsKeyDown(.Q) do orbit.yaw -= ORBIT_SPEED * dt
		if rl.IsKeyDown(.E) do orbit.yaw += ORBIT_SPEED * dt
		if rl.IsKeyDown(.R) do orbit.pitch += TILT_SPEED * dt
		if rl.IsKeyDown(.F) do orbit.pitch -= TILT_SPEED * dt
		if rl.IsKeyDown(.MINUS) || rl.IsKeyDown(.KP_SUBTRACT) do zoom3D(-1.5 * dt)
		if rl.IsKeyDown(.EQUAL) || rl.IsKeyDown(.KP_ADD) do zoom3D(1.5 * dt)

		wheel := rl.GetMouseWheelMove()
		if wheel != 0 do zoom3D(wheel * .1)

		mouseDelta := rl.GetMouseDelta()
		if rl.IsMouseButtonDown(.LEFT) {
			worldPerPixel := orbit.extent * 2 / f32(ui.windowSize.y)
			sinPitch := math.sin(orbit.pitch * rl.DEG2RAD)
			orbit.focus -= right * mouseDelta.x * worldPerPixel
			orbit.focus += forward * mouseDelta.y * worldPerPixel / sinPitch
		}
		if rl.IsMouseButtonDown(.RIGHT) {
			orbit.yaw -= mouseDelta.x * .3
			orbit.pitch += mouseDelta.y * .2
		}

		if rl.IsKeyPressed(.HOME) do resetOrbit()
	}

	orbit.pitch = clamp(orbit.pitch, PITCH_RANGE[0], PITCH_RANGE[1])
	orbit.fov = clamp(orbit.fov, FOV_RANGE[0], FOV_RANGE[1])
	orbit.extent = clamp(orbit.extent, EXTENT_RANGE[0], EXTENT_RANGE[1])
	orbit.yaw = math.mod(orbit.yaw + 360, 360)

	// keep the focus over the map
	limit := f32(max(clientState.game.grid.radius, 4))
	flat := rl.Vector2 { orbit.focus.x, orbit.focus.z }
	if rl.Vector2Length(flat) > limit do flat = rl.Vector2Normalize(flat) * limit
	orbit.focus = { flat.x, FOCUS_HEIGHT, flat.y }

	updateCamera3D()
}

exportSettings3D :: proc(s: ^ClientSettings) {
	s.fov = orbit.fov
	s.tilt = orbit.pitch
	s.dither = ditherScale
}

importSettings3D :: proc(s: ClientSettings) {
	orbit.fov = clamp(s.fov, FOV_RANGE[0], FOV_RANGE[1])
	orbit.pitch = clamp(s.tilt, PITCH_RANGE[0], PITCH_RANGE[1])
	ditherScale = clamp(f32(int(s.dither + .5)), 1, 4)
}

@(private="file")
resetOrbit :: proc() {
	orbit.yaw = 0
	orbit.pitch = DEFAULT_PITCH
	orbit.fov = DEFAULT_FOV
	orbit.extent = DEFAULT_EXTENT
}

// positive amount zooms in, towards the point under the cursor
@(private="file")
zoom3D :: proc(amount: f32) {
	previous := orbit.extent
	orbit.extent = clamp(orbit.extent * (1 - amount), EXTENT_RANGE[0], EXTENT_RANGE[1])
	if pointerHit {
		k := 1 - orbit.extent / previous
		orbit.focus.x += (pointer3D.x - orbit.focus.x) * k
		orbit.focus.z += (pointer3D.z - orbit.focus.z) * k
	}
}

// marches the cursor ray through the prisms, so walls of tall tiles can be pointed at
@(private="file")
pick3D :: proc() {
	ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), camera3D)
	pointerHit = false
	if ray.direction.y >= -1e-4 do return

	top := terrainMaxHeight3D() + .05
	tStart := max((top - ray.position.y) / ray.direction.y, 0)
	tEnd := (0 - ray.position.y) / ray.direction.y
	STEP :: f32(.03)

	for t := tStart; t <= tEnd; t += STEP {
		p := ray.position + ray.direction * t
		cell := hex.worldToAxial({ p.x, p.z })
		if p.y <= terrainHeight3D(cell) {
			ui.pointedCell = cell
			pointer3D = p
			pointerHit = true
			return
		}
	}

	p := ray.position + ray.direction * tEnd
	ui.pointedCell = hex.worldToAxial({ p.x, p.z })
	pointer3D = p
	pointerHit = true
}

// center of a tile's top face
@(private)
cellTop3D :: proc(at: hex.Axial) -> rl.Vector3 {
	world := hex.axialToWorld(at)
	return { world.x, terrainHeight3D(at), world.y }
}

@(private="file")
scene3D :: proc() {
	dt := rl.GetFrameTime()
	time3D = f32(rl.GetTime())

	rl.ClearBackground({ 10, 10, 12, 255 })

	syncTerrain3D()
	syncUnits3D()
	updateFX3D(dt)

	rl.BeginMode3D(camera3D)
	// raylib's fixed clip planes waste depth precision at narrow fields of view
	distance := orbitDistance()
	aspect := f32(ui.windowSize.x) / f32(max(ui.windowSize.y, 1))
	near := max(distance * .05, .05)
	far := distance * 3 + f32(clientState.game.grid.radius) * 3 + 60
	rlgl.SetMatrixProjection(rl.MatrixPerspective(orbit.fov * rl.DEG2RAD, aspect, near, far))

	drawGround3D()
	if clientState.status != .CONNECTING {
		drawTerrain3D()
		drawUnits3D()
		drawOverlays3D()
		drawFX3D()
	}
	rl.EndMode3D()
}

@(private="file")
settings3D :: proc(layout: ^SettingsLayout) {
	settingsSlider(layout, "FOV", &orbit.fov, FOV_RANGE[0], FOV_RANGE[1], .DEGREES)
	settingsSlider(layout, "TILT [R F]", &orbit.pitch, PITCH_RANGE[0], PITCH_RANGE[1], .DEGREES)
	settingsSlider(layout, "DITHER", &ditherScale, 1, 4, .PLAIN)
	ditherScale = math.round(ditherScale)
	if settingsButton(layout, "RESET VIEW [HOME]") do resetOrbit()
	settingsLabel(layout, "ORBIT [Q E] ZOOM [- =]")
}
