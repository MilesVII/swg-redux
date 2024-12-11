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
pointedCell: hex.Axial

ClientStatus :: enum {
	CONNECTING, LOBBY, WAITING, PLAYING, FINISH
}

ClientState :: struct {
	grid: GameGrid,
	serverSocket: net.TCP_Socket,
	status: ClientStatus
}

clientState := ClientState {
	status = .CONNECTING
}

client :: proc() {
	rl.InitWindow(WINDOW.x, WINDOW.y, "SWGRedux")
	defer rl.CloseWindow()

	rl.SetTargetFPS(240)

	me := connect()

	for !rl.WindowShouldClose() { // Detect window close button or ESC key
		updateIO()
		// update()
		draw()
	}
}

updateIO :: proc() {
	pointer = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

	if rl.IsKeyDown(rl.KeyboardKey.RIGHT) do camera.zoom += 0.1
	else if rl.IsKeyDown(rl.KeyboardKey.LEFT) do camera.zoom -= 0.1
	if camera.zoom < .1 do camera.zoom = .1
	
	pointedCell = hex.worldToAxial(pointer)
}

draw :: proc() {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.RAYWHITE)

	rl.BeginMode2D(camera)

	if clientState.status != .CONNECTING do drawGrid()

	rl.EndMode2D()

	rl.DrawText(fmt.ctprint(pointedCell), 0, 0, 8, rl.RED)
	rl.DrawText(fmt.ctprint(1.0 / rl.GetFrameTime()), 0, 8, 8, rl.RED)
}

drawGrid :: proc() {
	for cell in clientState.grid.cells {
		if cell.visible {
			vertesex := cell.vertesex;
			rl.DrawTriangleFan(&vertesex[0], 6, cell.value.color)
		}
	}
	
	// walkables := hex.findWalkableOutline(grid, pointedCell, 3)
	walkables, ok := hex.findPath(clientState.grid, {0, 0}, pointedCell)
	if ok {
		outline := hex.outline(walkables, .5)
		drawOutline(outline)
	}
}

drawOutline :: proc(outline: []hex.Line) {
	for line in outline {
		vx := line
		rl.DrawTriangleFan(&vx[0], 4, rl.BLACK)
	}
}

@(private)
connect :: proc() -> uuid.Identifier {
	context.random_generator = crypto.random_generator()
	clientState.serverSocket = networking.dial()
	me := uuid.generate_v4()

	startListening()

	joinMessage := GamePackage {
		message = Message.JOIN,
		me = me
	}
	networking.say(GamePackage, &joinMessage, clientState.serverSocket)

	return me
}

@(private)
startListening :: proc() {
	listener :: proc(t: ^thread.Thread) {
		onPackage :: proc(data: GamePackage) {
			fmt.printfln("server said %s", data.message)
			switch data.message {
				case .JOIN:
				case .UPDATE_GRID:
					clientState.grid = data.grid
				case .UPDATE_UNIT:
				case .SUBMIT:
			}
		}

		networking.listen(GamePackage, onPackage, clientState.serverSocket)
	}

	t := thread.create(listener)
	if t != nil {
		t.init_context = context
		t.user_index = 0
		thread.start(t)
	}
}

