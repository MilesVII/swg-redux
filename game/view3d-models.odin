package game

import rl "vendor:raylib"

import "core:os"
import "core:strings"
import "core:strconv"
import "core:math"

// geometry of an .obj file, converted to game axes but not scaled yet
ObjGeometry :: struct {
	// three floats per vertex, three vertices per triangle
	positions: [dynamic]f32,
	normals: [dynamic]f32,
	min: rl.Vector3,
	max: rl.Vector3
}

// .obj files are Z-up and X-forward, the game is Y-up and Z-forward, both right handed
@(private="file")
toGameAxes :: proc(x, y, z: f32) -> rl.Vector3 {
	return { y, z, x }
}

deleteObjGeometry :: proc(g: ^ObjGeometry) {
	delete(g.positions)
	delete(g.normals)
	g^ = {}
}

// reads positions, normals and faces of every object in the file; materials and uvs are ignored
// polygons are ear clipped, faces without normals get flat ones
loadObjGeometry :: proc(path: string) -> (geometry: ObjGeometry, ok: bool) {
	data, readErr := os.read_entire_file(path, context.allocator)
	if readErr != nil do return {}, false
	defer delete(data)

	positions := make([dynamic]rl.Vector3, context.temp_allocator)
	normals := make([dynamic]rl.Vector3, context.temp_allocator)
	geometry.min = { max(f32), max(f32), max(f32) }
	geometry.max = { min(f32), min(f32), min(f32) }

	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) == 0 do continue

		switch fields[0] {
			case "v", "vn":
				if len(fields) < 4 do continue
				x, _ := strconv.parse_f32(fields[1])
				y, _ := strconv.parse_f32(fields[2])
				z, _ := strconv.parse_f32(fields[3])
				if fields[0] == "v" do append(&positions, toGameAxes(x, y, z))
				else do append(&normals, toGameAxes(x, y, z))
			case "f":
				corners := make([dynamic]rl.Vector3, context.temp_allocator)
				cornerNormals := make([dynamic]rl.Vector3, context.temp_allocator)
				allHaveNormals := true
				for corner in fields[1:] {
					parts := strings.split(corner, "/", context.temp_allocator)
					index, indexOk := objIndex(parts[0], len(positions))
					if !indexOk do continue
					append(&corners, positions[index])
					normalIndex, normalOk := -1, false
					if len(parts) >= 3 && len(parts[2]) > 0 do normalIndex, normalOk = objIndex(parts[2], len(normals))
					if normalOk do append(&cornerNormals, normals[normalIndex])
					else do allHaveNormals = false
				}
				if len(corners) < 3 do continue

				flat := polygonNormal(corners[:])
				for triangle in earClip(corners[:], flat) {
					for k in triangle {
						p := corners[k]
						n := allHaveNormals ? rl.Vector3Normalize(cornerNormals[k]) : flat
						append(&geometry.positions, p.x, p.y, p.z)
						append(&geometry.normals, n.x, n.y, n.z)
						geometry.min = { min(geometry.min.x, p.x), min(geometry.min.y, p.y), min(geometry.min.z, p.z) }
						geometry.max = { max(geometry.max.x, p.x), max(geometry.max.y, p.y), max(geometry.max.z, p.z) }
					}
				}
		}
	}
	return geometry, len(geometry.positions) > 0
}

// 1-based, negative counts from the end
@(private="file")
objIndex :: proc(field: string, count: int) -> (int, bool) {
	value, ok := strconv.parse_int(field)
	if !ok || value == 0 do return 0, false
	index := value > 0 ? value - 1 : count + value
	return index, index >= 0 && index < count
}

// Newell's method, follows the counter-clockwise winding of .obj faces
@(private="file")
polygonNormal :: proc(points: []rl.Vector3) -> rl.Vector3 {
	n: rl.Vector3
	for p, i in points {
		q := points[(i + 1) % len(points)]
		n.x += (p.y - q.y) * (p.z + q.z)
		n.y += (p.z - q.z) * (p.x + q.x)
		n.z += (p.x - q.x) * (p.y + q.y)
	}
	length := rl.Vector3Length(n)
	return length > 1e-9 ? n / length : { 0, 1, 0 }
}

// triangles of a possibly concave polygon, as indices into `points`
@(private="file")
earClip :: proc(points: []rl.Vector3, normal: rl.Vector3) -> [][3]int {
	triangles := make([dynamic][3]int, context.temp_allocator)
	remaining := make([dynamic]int, len(points), context.temp_allocator)
	for i in 0..<len(points) do remaining[i] = i

	sameSide :: proc(a, b, p, normal: rl.Vector3) -> bool {
		return rl.Vector3DotProduct(rl.Vector3CrossProduct(b - a, p - a), normal) >= -1e-9
	}

	for len(remaining) > 3 {
		count := len(remaining)
		clipped := false
		for i in 0..<count {
			ia := remaining[(i + count - 1) % count]
			ib := remaining[i]
			ic := remaining[(i + 1) % count]
			a, b, c := points[ia], points[ib], points[ic]
			// skip reflex and degenerate corners
			if rl.Vector3DotProduct(rl.Vector3CrossProduct(b - a, c - b), normal) <= 1e-9 do continue

			contains := false
			for other in remaining {
				if other == ia || other == ib || other == ic do continue
				p := points[other]
				if sameSide(a, b, p, normal) && sameSide(b, c, p, normal) && sameSide(c, a, p, normal) {
					contains = true
					break
				}
			}
			if contains do continue

			append(&triangles, [3]int { ia, ib, ic })
			ordered_remove(&remaining, i)
			clipped = true
			break
		}
		if !clipped {
			// not a simple polygon, fall back to a fan
			for i in 1..<len(remaining) - 1 do append(&triangles, [3]int { remaining[0], remaining[i], remaining[i + 1] })
			return triangles[:]
		}
	}
	append(&triangles, [3]int { remaining[0], remaining[1], remaining[2] })
	return triangles[:]
}

scaleObjGeometry :: proc(g: ^ObjGeometry, scale: f32) {
	for &value in g.positions do value *= scale
	g.min *= scale
	g.max *= scale
}

// uploads to the GPU, the CPU side stays with the geometry
uploadObjGeometry :: proc(g: ObjGeometry) -> rl.Mesh {
	count := len(g.positions) / 3
	mesh := rl.Mesh {
		vertexCount = i32(count),
		triangleCount = i32(count / 3),
		vertices = raw_data(g.positions),
		normals = raw_data(g.normals),
	}
	rl.UploadMesh(&mesh, false)
	// owned by Odin's allocator, raylib must not free them
	mesh.vertices = nil
	mesh.normals = nil
	return mesh
}

// largest distance from the vertical axis, used to fit a model into its hex
horizontalExtent :: proc(g: ObjGeometry) -> f32 {
	extent := f32(0)
	for i := 0; i < len(g.positions); i += 3 {
		extent = max(extent, math.sqrt(g.positions[i] * g.positions[i] + g.positions[i + 2] * g.positions[i + 2]))
	}
	return extent
}
