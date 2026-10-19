package game

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "core:math"
import "core:math/rand"

import "hex"

@(private="file")
MAX_PARTICLES :: 12000
@(private="file")
MAX_LIGHTS :: 8
@(private="file")
WIND :: rl.Vector3 { .22, 0, -.08 }

@(private="file")
ParticleKind :: enum u8 {
	// soft and lit: smoke, dust
	SMOKE,
	// soft and self-lit: fireballs, flashes
	FIRE,
	// hard and lit: debris chunks
	DEBRIS,
	// hard and self-lit: sparks
	SPARK
}

@(private="file")
Particle :: struct {
	kind: ParticleKind,
	seed: u8,
	position: rl.Vector3,
	velocity: rl.Vector3,
	// seconds before it shows up
	delay: f32,
	age: f32,
	life: f32,
	size0: f32,
	size1: f32,
	color0: [3]f32,
	color1: [3]f32,
	opacity: f32,
	drag: f32,
	// upward acceleration, negative for gravity
	lift: f32,
	// lowest point, for things that bounce
	ground: f32
}

// keeps spitting smoke over a destroyed unit
@(private="file")
Emitter :: struct {
	position: rl.Vector3,
	age: f32,
	life: f32,
	accumulator: f32
}

@(private="file")
Light :: struct {
	position: rl.Vector3,
	age: f32,
	life: f32,
	power: f32
}

// incoming shell markers, from the start of a bonk until its impact
@(private="file")
Marker :: struct {
	at: hex.Axial,
	start: f32
}

// muzzle blasts of your units, a short small shockwave each
@(private="file")
MuzzleShock :: struct {
	position: rl.Vector3,
	start: f32
}
@(private="file")
MUZZLE_SHOCK_S :: f32(.55)

@(private="file")
fx: struct {
	shader: rl.Shader,
	muzzleShocks: [dynamic]MuzzleShock,
	particles: [dynamic]Particle,
	emitters: [dynamic]Emitter,
	lights: [dynamic]Light,
	markers: [dynamic]Marker
}

initFX3D :: proc() {
	fx.shader = rl.LoadShader("shaders/particle-vs.glsl", "shaders/particle-fs.glsl")
}

deinitFX3D :: proc() {
	rl.UnloadShader(fx.shader)
	delete(fx.particles)
	delete(fx.emitters)
	delete(fx.lights)
	delete(fx.markers)
	delete(fx.muzzleShocks)
}

explosionStart3D :: proc(bonk: Explosion) {
	append(&fx.markers, Marker { bonk.at, time3D })

	unitId, aim, isYours := findShooter(bonk)
	if !isYours do return
	muzzle, found := aimMuzzle3D(unitId, aim)
	if !found do return
	spawnMuzzleBlast(muzzle)
	append(&fx.muzzleShocks, MuzzleShock { muzzle, time3D })
	append(&fx.lights, Light { position = muzzle, life = .25, power = 1.2 })
}

// screen positions of the muzzle shockwaves for the post effects
muzzleShocks3D :: proc() -> []ScreenShock {
	result := make([dynamic]ScreenShock, context.temp_allocator)
	forward := rl.Vector3Normalize(camera3D.target - camera3D.position)
	for shock in fx.muzzleShocks {
		if rl.Vector3DotProduct(shock.position - camera3D.position, forward) <= 0 do continue
		progress := clamp((time3D - shock.start) / MUZZLE_SHOCK_S, 0, 1)
		append(&result, ScreenShock { rl.GetWorldToScreen(shock.position, camera3D), progress, .12, .6 })
	}
	return result[:]
}

// flash and a puff of smoke where a shell leaves the barrel
@(private="file")
spawnMuzzleBlast :: proc(at: rl.Vector3) {
	for _ in 0..<2 {
		emit({
			kind = .FIRE, position = at,
			life = randRange(.06, .1), size0 = .16, size1 = .3,
			color0 = { 1, .95, .75 }, color1 = { 1, .6, .2 }, opacity = 1
		})
	}
	for _ in 0..<12 {
		direction := randomUp(.1, 1)
		gray := randRange(.42, .58)
		emit({
			kind = .SMOKE, position = at + direction * .05,
			velocity = direction * randRange(.4, 1.3),
			delay = randRange(0, .08),
			life = randRange(1, 1.8), size0 = randRange(.06, .1), size1 = randRange(.3, .45),
			color0 = { gray, gray * .97, gray * .92 }, color1 = { .62, .61, .6 }, opacity = .75,
			drag = 2.6, lift = .25
		})
	}
	for _ in 0..<6 {
		emit({
			kind = .SPARK, position = at,
			velocity = randomUp(.1, .8) * randRange(1.5, 3),
			life = randRange(.15, .3), size0 = .03, size1 = .015,
			color0 = { 1, .9, .6 }, color1 = { 1, .5, .15 }, opacity = 1,
			drag = 2, lift = -4, ground = at.y - 1
		})
	}
}

explosionImpact3D :: proc(bonk: Explosion) {
	for i := len(fx.markers) - 1; i >= 0; i -= 1 {
		if fx.markers[i].at == bonk.at {
			ordered_remove(&fx.markers, i)
			break
		}
	}

	at := cellTop3D(bonk.at)
	spawnExplosion(at, bonk.lethal)
	append(&fx.lights, Light {
		position = at + { 0, .6, 0 },
		life = bonk.lethal ? .9 : .6,
		power = bonk.lethal ? 3.2 : 2.2
	})
	if bonk.lethal do append(&fx.emitters, Emitter { position = at, life = 6.5 })
}

// a hex closing in on the target until the shell lands
drawExplosionMarkers3D :: proc(alphaScale: f32) {
	for marker in fx.markers {
		progress := clamp((time3D - marker.start) / EXPLOSION_HATTRICK_S, 0, 1)
		color := rl.Color { 255, u8(200 * (1 - progress)), 40, u8(255 * alphaScale) }
		overlayCellBorder3D(marker.at, .14, color, 1.8 - progress * .8)
	}
}

@(private="file")
randRange :: proc(lo, hi: f32) -> f32 {
	return lo + rand.float32() * (hi - lo)
}

// random direction in the upper hemisphere, `flatness` 0 points anywhere up, 1 hugs the ground
@(private="file")
randomUp :: proc(minUp: f32, maxUp: f32) -> rl.Vector3 {
	angle := rand.float32() * math.TAU
	up := randRange(minUp, maxUp)
	side := math.sqrt(max(1 - up * up, 0))
	return { math.cos(angle) * side, up, math.sin(angle) * side }
}

@(private="file")
emit :: proc(p: Particle) {
	if len(fx.particles) >= MAX_PARTICLES do return
	p := p
	p.seed = u8(rand.int31_max(16))
	append(&fx.particles, p)
}

@(private="file")
spawnExplosion :: proc(at: rl.Vector3, lethal: bool) {
	scale := lethal ? f32(1.35) : 1
	count :: proc(n: int, scale: f32) -> int { return int(f32(n) * scale) }

	// flash
	for _ in 0..<2 {
		emit({
			kind = .FIRE, position = at + { 0, .25, 0 },
			life = randRange(.1, .18), size0 = .9 * scale, size1 = 1.6 * scale,
			color0 = { 1, .97, .85 }, color1 = { 1, .62, .25 }, opacity = 1
		})
	}
	// fireball
	for _ in 0..<count(22, scale) {
		direction := randomUp(.15, 1)
		emit({
			kind = .FIRE, position = at + direction * .1 + { 0, .1, 0 },
			velocity = direction * randRange(1.2, 3.4) * scale,
			life = randRange(.45, 1), size0 = randRange(.22, .36), size1 = randRange(.55, .9) * scale,
			color0 = { 1, .9, .5 }, color1 = { .5, .14, .04 }, opacity = 1,
			drag = 4.5, lift = .7
		})
	}
	// smoke billowing out
	for _ in 0..<count(40, scale) {
		direction := randomUp(.25, 1)
		gray := randRange(.18, .36)
		emit({
			kind = .SMOKE, position = at + direction * .15 + { 0, .1, 0 },
			velocity = direction * randRange(.4, 1.8) * scale,
			delay = randRange(0, .25),
			life = randRange(2.6, 4.8), size0 = randRange(.2, .4), size1 = randRange(.7, 2) * scale,
			color0 = { gray * 1.15, gray, gray * .82 }, color1 = { .5 + gray * .3, .48 + gray * .3, .46 + gray * .3 }, opacity = .85,
			drag = 1.7, lift = .3
		})
	}
	// a column rising from the middle
	for i in 0..<count(14, scale) {
		emit({
			kind = .SMOKE, position = at + { randRange(-.1, .1), .2, randRange(-.1, .1) },
			velocity = { randRange(-.2, .2), randRange(1.4, 2.6) * scale, randRange(-.2, .2) },
			delay = f32(i) * .03,
			life = randRange(3, 5), size0 = .3, size1 = randRange(.9, 1.5) * scale,
			color0 = { .16, .14, .12 }, color1 = { .45, .44, .43 }, opacity = .9,
			drag = 1.1, lift = .25
		})
	}
	// dust ring along the ground
	for _ in 0..<count(24, scale) {
		direction := randomUp(.02, .12)
		emit({
			kind = .SMOKE, position = at + direction * .2 + { 0, .05, 0 },
			velocity = direction * randRange(2.2, 3.6) * scale,
			life = randRange(1.6, 2.7), size0 = randRange(.2, .3), size1 = randRange(.8, 1.1) * scale,
			color0 = { .55, .47, .36 }, color1 = { .62, .58, .52 }, opacity = .7,
			drag = 3.6, lift = .06
		})
	}
	// debris
	for _ in 0..<count(16, scale) {
		direction := randomUp(.35, 1)
		emit({
			kind = .DEBRIS, position = at + { 0, .1, 0 },
			velocity = direction * randRange(2, 4.6),
			life = randRange(1, 1.7), size0 = randRange(.05, .09), size1 = .05,
			color0 = { .13, .11, .1 }, color1 = { .1, .09, .08 }, opacity = 1,
			drag = .3, lift = -9, ground = at.y
		})
	}
	// sparks
	for _ in 0..<count(14, scale) {
		direction := randomUp(.2, 1)
		emit({
			kind = .SPARK, position = at + { 0, .15, 0 },
			velocity = direction * randRange(3, 6.5),
			life = randRange(.3, .65), size0 = .045, size1 = .02,
			color0 = { 1, .9, .55 }, color1 = { 1, .45, .12 }, opacity = 1,
			drag = 1.2, lift = -6, ground = at.y
		})
	}
}

updateFX3D :: proc(dt: f32) {
	for i := len(fx.emitters) - 1; i >= 0; i -= 1 {
		e := &fx.emitters[i]
		e.age += dt
		if e.age >= e.life {
			unordered_remove(&fx.emitters, i)
			continue
		}
		strength := 1 - e.age / e.life
		e.accumulator += dt * 10 * strength
		for e.accumulator >= 1 {
			e.accumulator -= 1
			emit({
				kind = .SMOKE, position = e.position + { randRange(-.15, .15), .15, randRange(-.15, .15) },
				velocity = { randRange(-.15, .15), randRange(.5, .9), randRange(-.15, .15) },
				life = randRange(2.2, 3.4), size0 = .15, size1 = randRange(.6, .9),
				color0 = { .1, .09, .08 }, color1 = { .32, .31, .3 }, opacity = .8 * strength + .2,
				drag = .8, lift = .25
			})
			if rand.float32() < .35 * strength {
				emit({
					kind = .FIRE, position = e.position + { randRange(-.12, .12), .12, randRange(-.12, .12) },
					velocity = { 0, randRange(.4, .7), 0 },
					life = randRange(.25, .45), size0 = .12, size1 = .22,
					color0 = { 1, .7, .3 }, color1 = { .6, .2, .05 }, opacity = 1,
					drag = 1
				})
			}
		}
	}

	for i := len(fx.particles) - 1; i >= 0; i -= 1 {
		p := &fx.particles[i]
		if p.delay > 0 {
			p.delay -= dt
			continue
		}
		p.age += dt
		if p.age >= p.life {
			unordered_remove(&fx.particles, i)
			continue
		}

		p.velocity.y += p.lift * dt
		p.velocity *= math.exp(-p.drag * dt)
		if p.kind == .SMOKE do p.velocity += WIND * dt
		p.position += p.velocity * dt

		if (p.kind == .DEBRIS || p.kind == .SPARK) && p.position.y < p.ground {
			p.position.y = p.ground
			p.velocity.y = -p.velocity.y * .3
			p.velocity.x *= .5
			p.velocity.z *= .5
		}
	}

	for i := len(fx.muzzleShocks) - 1; i >= 0; i -= 1 {
		if time3D - fx.muzzleShocks[i].start >= MUZZLE_SHOCK_S do unordered_remove(&fx.muzzleShocks, i)
	}

	for i := len(fx.lights) - 1; i >= 0; i -= 1 {
		fx.lights[i].age += dt
		if fx.lights[i].age >= fx.lights[i].life do unordered_remove(&fx.lights, i)
	}
}

// up to eight lights as position and intensity for the shaders
activeLights3D :: proc() -> ([MAX_LIGHTS][4]f32, i32) {
	result: [MAX_LIGHTS][4]f32
	count := 0
	for light in fx.lights {
		if count >= MAX_LIGHTS do break
		t := light.age / light.life
		result[count] = { light.position.x, light.position.y, light.position.z, light.power * (1 - t) * (1 - t) }
		count += 1
	}
	return result, i32(count)
}

@(private="file")
opacityOf :: proc(p: Particle, t: f32) -> f32 {
	switch p.kind {
		case .SMOKE:
			fadeIn := clamp(t / .06, 0, 1)
			fadeOut := 1 - clamp((t - .25) / .75, 0, 1)
			return p.opacity * fadeIn * fadeOut * fadeOut
		case .FIRE:
			return p.opacity * math.pow(1 - t, 1.2)
		case .DEBRIS, .SPARK:
			return p.opacity * (1 - clamp((t - .8) / .2, 0, 1))
	}
	return 0
}

drawFX3D :: proc() {
	forward := rl.Vector3Normalize(camera3D.target - camera3D.position)
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, camera3D.up))
	up := rl.Vector3CrossProduct(right, forward)

	shader := fx.shader
	setLightUniforms3D(shader)
	rlgl.DisableBackfaceCulling()

	for kind in ParticleKind {
		emissive := f32(kind == .FIRE || kind == .SPARK ? 1 : 0)
		hard := f32(kind == .DEBRIS || kind == .SPARK ? 1 : 0)
		rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "emissive"), &emissive, .FLOAT)
		rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "hardShape"), &hard, .FLOAT)

		rl.BeginShaderMode(shader)
		rlgl.Begin(rlgl.QUADS)
		for p in fx.particles {
			if p.kind != kind || p.delay > 0 do continue
			t := p.age / p.life
			opacity := opacityOf(p, t)
			if opacity <= .01 do continue

			growth := 1 - (1 - t) * (1 - t)
			size := p.size0 + (p.size1 - p.size0) * growth
			mix := clamp(t / .7, 0, 1)
			color := p.color0 + (p.color1 - p.color0) * mix
			r := right * size
			u := up * size
			seed := f32(p.seed) * 4

			rlgl.Color4ub(u8(clamp(color.r, 0, 1) * 255), u8(clamp(color.g, 0, 1) * 255), u8(clamp(color.b, 0, 1) * 255), u8(clamp(opacity, 0, 1) * 255))
			corner :: proc(position: rl.Vector3, u: f32, v: f32, seed: f32) {
				rlgl.TexCoord2f(u + seed, v)
				rlgl.Vertex3f(position.x, position.y, position.z)
			}
			corner(p.position - r + u, -1, 1, seed)
			corner(p.position - r - u, -1, -1, seed)
			corner(p.position + r - u, 1, -1, seed)
			corner(p.position + r + u, 1, 1, seed)
		}
		rlgl.End()
		rl.EndShaderMode()
	}

	rlgl.EnableBackfaceCulling()
}
