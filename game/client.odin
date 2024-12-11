package game

import rl "vendor:raylib"
import "hex"
import "core:fmt"
import "core:net"
import "core:thread"
import "core:encoding/uuid"
import "core:crypto"
import "utils"
import "networking"


WINDOW :: [2]i32 {640, 480}

camera := rl.Camera2D {
	offset = rl.Vector2 {f32(WINDOW.x) / 2, f32(WINDOW.y) / 2},
	target = rl.Vector2 {0, 0},
	rotation = 0.0,
	zoom = 20.0,
}
pointer: rl.Vector2
serverSocket: net.TCP_Socket

client :: proc() {
	rl.InitWindow(WINDOW.x, WINDOW.y, "SWGRedux")
	defer rl.CloseWindow()

	// rl.SetConfigFlags(rl.ConfigFlags{rl.ConfigFlag.MSAA_4X_HINT})
	rl.SetTargetFPS(240)

	me := connect()

	for !rl.WindowShouldClose() { // Detect window close button or ESC key
		updateIO()
		// update()
		// draw()
	}
}

updateIO :: proc() {
	pointer = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

	if rl.IsKeyDown(rl.KeyboardKey.RIGHT) do camera.zoom += 0.1
	else if rl.IsKeyDown(rl.KeyboardKey.LEFT) do camera.zoom -= 0.1
	if camera.zoom < .1 do camera.zoom = .1
}

// draw :: proc() {
// 	rl.BeginDrawing()
// 	defer rl.EndDrawing()

// 	rl.ClearBackground(rl.RAYWHITE)
	
// 	rl.BeginMode2D(camera)

// 	pointedCell := hex.worldToAxial(pointer)

// 	for cell in grid.cells {
// 		if cell.visible {
// 			vertesex := cell.vertesex;
// 			rl.DrawTriangleFan(&vertesex[0], 6, cell.value.color)
// 		}
// 	}
	
// 	// walkables := hex.findWalkableOutline(grid, pointedCell, 3)
// 	walkables, ok := hex.findPath(grid, {0, 0}, pointedCell)
// 	if ok {
// 		outline := hex.outline(walkables, .5)
// 		drawOutline(outline)
// 	}

// 	rl.EndMode2D()

// 	rl.DrawText(fmt.ctprint(pointedCell), 0, 0, 8, rl.RED)
// 	rl.DrawText(fmt.ctprint(1.0 / rl.GetFrameTime()), 0, 8, 8, rl.RED)
// }

// drawOutline :: proc(outline: []hex.Line) {
// 	for line in outline {
// 		vx := line
// 		rl.DrawTriangleFan(&vx[0], 4, rl.BLACK)
// 	}
// }

@(private)
onPackage :: proc(data: GamePackage) {
	switch data.message {
		case .JOIN:
		case .UPDATE_GRID:
		case .UPDATE_UNIT:
		case .SUBMIT:
	}
}

@(private)
connect :: proc() -> uuid.Identifier {
	context.random_generator = crypto.random_generator()
	serverSocket := networking.dial()
	me := uuid.generate_v4()

	startListening()

	joinMessage := GamePackage {
		message = Message.JOIN,
		me = me
	}
	networking.say(GamePackage, &joinMessage, serverSocket)

	return me
}

@(private)
startListening :: proc() {
	listener :: proc(t: ^thread.Thread) {
		onPackage :: proc(data: GamePackage) {
			fmt.printfln("server said %s", data.message)
			switch data.message {
				case .JOIN:
					onJoin(data.me)
				case .UPDATE_GRID:
				case .UPDATE_UNIT:
				case .SUBMIT:
			}
		}

		networking.listen(GamePackage, onPackage, serverSocket)
	}

	t := thread.create(listener)
	if t != nil {
		t.init_context = context
		t.user_index = 0
		thread.start(t)
	}
}

