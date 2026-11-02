package mapview

// looks at generated maps while tinkering with the generator:
//   odin build tools/mapview -out:build/mapview.exe
//   build/mapview                       a window, keys are listed in it
//   build/mapview --shot 7 map.png      renders seed 7 into a file
//   build/mapview --stats 200           fairness statistics over 200 seeds
// --radius N, --players N and --teams N apply to all three

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

import "../../game"
import "../../game/hex"

MAP_SIDE :: 900
PANEL :: 360

Setup :: struct {
	seed: i64,
	radius: int,
	players: int,
	teams: int,
	showRegions: bool,
	showCandidates: bool
}

Map :: struct {
	state: game.GameState,
	err: game.GameInitError,
	spawns: []hex.Axial,
	regions: []int,
	gold: []int,
	candidates: []int
}

generate :: proc(setup: Setup) -> Map {
	m: Map
	m.state, m.err = game.generateMap(setup.players, setup.radius, setup.seed, setup.teams)
	if m.err == .NO_SPAWNS do return m
	m.spawns = make([]hex.Axial, setup.players)
	for player, i in m.state.players do m.spawns[i] = player.units[0].position
	m.regions = game.goldRegions(m.state.grid, m.spawns)
	m.gold = make([]int, setup.players)
	m.candidates = make([]int, setup.players)
	for cell, index in m.state.grid.cells {
		region := m.regions[index]
		if region < 0 do continue
		if cell.value.gold > 0 do m.gold[region] += 1
		if game.goldCandidate(m.state.grid, index) do m.candidates[region] += 1
	}
	return m
}

release :: proc(m: Map) {
	game.deleteState(m.state)
	delete(m.spawns)
	delete(m.regions)
	delete(m.gold)
	delete(m.candidates)
}

tint :: proc(base, toward: rl.Color, amount: f32) -> rl.Color {
	mix :: proc(a, b: u8, t: f32) -> u8 { return u8(f32(a) + (f32(b) - f32(a)) * t) }
	return { mix(base.r, toward.r, amount), mix(base.g, toward.g, amount), mix(base.b, toward.b, amount), 255 }
}

draw :: proc(m: Map, setup: Setup) {
	rl.ClearBackground({ 24, 24, 28, 255 })
	camera := rl.Camera2D {
		offset = { MAP_SIDE / 2, MAP_SIDE / 2 },
		target = { 0, 0 },
		zoom = f32(MAP_SIDE) * .47 / f32(setup.radius + 1)
	}

	if m.err != .NO_SPAWNS {
		rl.BeginMode2D(camera)
		for cell, index in m.state.grid.cells {
			if !cell.visible do continue
			color := cell.value.color
			region := m.regions[index]
			if setup.showRegions && region >= 0 do color = tint(color, m.state.players[region].color, cell.value.mainArea ? .35 : .2)
			vx := cell.vertesex
			rl.DrawTriangleFan(&vx[0], 6, color)
			if cell.value.gold > 0 {
				gvx := hex.vertesex(cell.position.axial, .55)
				rl.DrawTriangleFan(&gvx[0], 6, rl.GOLD)
			} else if setup.showCandidates && game.goldCandidate(m.state.grid, index) {
				rl.DrawCircleV(cell.position.world, .15, { 0, 0, 0, 160 })
			}
		}
		for spawn, i in m.spawns {
			at := hex.axialToWorld(spawn)
			rl.DrawCircleV(at, .55, rl.BLACK)
			rl.DrawCircleV(at, .42, m.state.players[i].color)
		}
		rl.EndMode2D()
	}

	// the panel
	x: f32 = MAP_SIDE + 16
	y: f32 = 16
	line :: proc(x: ^f32, y: ^f32, text: string, color := rl.RAYWHITE) {
		rl.DrawText(strings.clone_to_cstring(text, context.temp_allocator), i32(x^), i32(y^), 18, color)
		y^ += 24
	}
	line(&x, &y, fmt.tprintf("SEED %d  RADIUS %d  PLAYERS %d  TEAMS OF %d", setup.seed, setup.radius, setup.players, setup.teams), rl.GOLD)
	switch m.err {
		case .OK:          line(&x, &y, "map OK", rl.GREEN)
		case .NO_SPAWNS:   line(&x, &y, "NO ROOM FOR SIX SPAWNS", rl.RED)
		case .UNFAIR_GOLD: line(&x, &y, "UNFAIR GOLD, a region fell short", rl.ORANGE)
	}
	y += 12
	if m.err != .NO_SPAWNS {
		quota := game.goldQuota(setup.radius, setup.players)
		line(&x, &y, fmt.tprintf("quota per region %d", quota))
		for count, i in m.gold {
			color := m.state.players[i].color
			line(&x, &y, fmt.tprintf("player %d: %d gold of %d candidates", i, count, m.candidates[i]), color)
		}
	}
	y += 12
	line(&x, &y, fmt.tprintf("flatten %.2f towards plains %.2f", game.CENTER_FLATTEN, game.PLAINS_ELEVATION), rl.GRAY)
	line(&x, &y, fmt.tprintf("gap %d, clearance %d, fair share %.2f", game.GOLD_CLUSTER_GAP, game.GOLD_SPAWN_CLEARANCE, game.GOLD_FAIR_SHARE), rl.GRAY)
	y += 12
	HINTS :: []string {
		"LEFT/RIGHT  seed",
		"SPACE       random seed",
		"UP/DOWN     radius",
		"1-6         players",
		"T           team size",
		"R           regions",
		"C           candidates",
		"S           screenshot",
		"ESC         quit"
	}
	for hint in HINTS do line(&x, &y, hint, rl.LIGHTGRAY)
}

stats :: proc(setup: Setup, seeds: int) {
	ok, noSpawns, unfair := 0, 0, 0
	worstRatio: f32 = 1
	sumRatio: f32 = 0
	totalGold := 0
	// what the old generator would have given: every tile of the band below the mountains
	oldBand := 0
	for seed in 1..=seeds {
		setup := setup
		setup.seed = i64(seed)
		m := generate(setup)
		defer release(m)
		switch m.err {
			case .NO_SPAWNS: noSpawns += 1; continue
			case .UNFAIR_GOLD: unfair += 1; continue
			case .OK: ok += 1
		}
		lo, hi := max(int), 0
		for cell in m.state.grid.cells {
			if cell.visible && hex.heightLevel(hex.elevation(cell.position.world, setup.seed), game.HEIGHTS) == 7 do oldBand += 1
		}
		for count in m.gold {
			lo = min(lo, count)
			hi = max(hi, count)
			totalGold += count
		}
		ratio := hi > 0 ? f32(lo) / f32(hi) : 1
		worstRatio = min(worstRatio, ratio)
		sumRatio += ratio
	}
	fmt.printfln("radius %d, %d players in teams of %d, %d seeds", setup.radius, setup.players, setup.teams, seeds)
	fmt.printfln("  ok %d, no spawns %d, unfair gold %d", ok, noSpawns, unfair)
	if ok > 0 {
		fmt.printfln("  quota %d, gold per player on average %.1f", game.goldQuota(setup.radius, setup.players), f32(totalGold) / f32(ok * setup.players))
		fmt.printfln("  poorest/richest region: worst %.2f, average %.2f", worstRatio, sumRatio / f32(ok))
		fmt.printfln("  the old band would have held %.1f gold tiles per map", f32(oldBand) / f32(ok))
	}
}

main :: proc() {
	setup := Setup { seed = 1, radius = 16, players = 2, teams = 1, showRegions = true }
	shot := ""
	statsSeeds := 0
	number :: proc(text: string) -> int {
		value, _ := strconv.parse_int(text)
		return value
	}
	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		next :: proc(args: []string, i: ^int) -> string {
			i^ += 1
			return i^ < len(args) ? args[i^] : ""
		}
		switch args[i] {
			case "--radius":  setup.radius = number(next(args, &i))
			case "--players": setup.players = number(next(args, &i))
			case "--teams":   setup.teams = number(next(args, &i))
			case "--stats":   statsSeeds = number(next(args, &i))
			case "--shot":
				setup.seed = i64(number(next(args, &i)))
				shot = next(args, &i)
			case: fmt.printfln("unknown argument %s", args[i])
		}
	}
	setup.players = clamp(setup.players, 1, 6)
	setup.teams = max(setup.teams, 1)
	setup.radius = clamp(setup.radius, 3, 40)

	if statsSeeds > 0 {
		stats(setup, statsSeeds)
		return
	}

	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(MAP_SIDE + PANEL, MAP_SIDE, "swg map view")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	m := generate(setup)
	frames := 0
	for !rl.WindowShouldClose() {
		changed := false
		if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT) { setup.seed += 1; changed = true }
		if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressedRepeat(.LEFT) { setup.seed = max(setup.seed - 1, 0); changed = true }
		if rl.IsKeyPressed(.SPACE) { setup.seed = i64(rl.GetRandomValue(0, 1 << 30)); changed = true }
		if rl.IsKeyPressed(.UP) { setup.radius = min(setup.radius + 1, 40); changed = true }
		if rl.IsKeyPressed(.DOWN) { setup.radius = max(setup.radius - 1, 3); changed = true }
		PLAYER_KEYS :: []rl.KeyboardKey { .ONE, .TWO, .THREE, .FOUR, .FIVE, .SIX }
		for key, count in PLAYER_KEYS {
			if rl.IsKeyPressed(key) { setup.players = count + 1; changed = true }
		}
		if rl.IsKeyPressed(.T) {
			setup.teams = setup.teams == 1 ? 2 : (setup.teams == 2 ? 3 : 1)
			changed = true
		}
		if rl.IsKeyPressed(.R) do setup.showRegions = !setup.showRegions
		if rl.IsKeyPressed(.C) do setup.showCandidates = !setup.showCandidates
		if changed {
			release(m)
			m = generate(setup)
		}

		rl.BeginDrawing()
		draw(m, setup)
		rl.EndDrawing()
		if rl.IsKeyPressed(.S) do rl.TakeScreenshot(fmt.ctprintf("map-%d.png", setup.seed))
		// the first frames aren't on screen yet
		if shot != "" && rl.GetFrameTime() > 0 && frames > 3 {
			rl.TakeScreenshot(strings.clone_to_cstring(shot, context.temp_allocator))
			break
		}
		frames += 1
		free_all(context.temp_allocator)
	}
	release(m)
}
