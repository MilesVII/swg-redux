package game

import "core:math"
import "core:math/rand"

import "hex"

// gold lies in the mountain tiles bordering the main walkable area, in small clusters:
// every player's region, the cells nearest to their spawn by walking, gets the same amount,
// and clusters are more frequent and bigger towards the middle of the map

// gold tiles on a map of radius 16, scaled with the map's area and split among the players
GOLD_PER_MAP_AT_16 :: 48
// a region that gets less than this share of its quota makes the map unfair
GOLD_FAIR_SHARE :: .75
// mountains this close to a spawn stay empty, nobody digs without moving first
GOLD_SPAWN_CLEARANCE :: 2
// empty tiles kept between clusters, relaxed when a region runs out of room
GOLD_CLUSTER_GAP :: 2
// the share of a cluster seed's weight that doesn't depend on its place on the map
GOLD_CORNER_WEIGHT :: .1

// gold tiles for each player's region
goldQuota :: proc(radius: int, players: int) -> int {
	area := f32(radius * radius) / 256
	return max(3, int(math.round(f32(GOLD_PER_MAP_AT_16) * area / f32(max(players, 1)))))
}

// 1 in the middle of the map, 0 at its rim
centerCloseness :: proc(at: hex.Axial, radius: int) -> f32 {
	return clamp(1 - f32(hex.distance(at, { 0, 0 })) / f32(radius), 0, 1)
}

// the region each cell belongs to: the index of the spawn nearest by walking, with mountains
// joining the region of their nearest walkable neighbour; -1 where no spawn reaches
goldRegions :: proc(grid: GameGrid, spawns: []hex.Axial, allocator := context.allocator) -> []int {
	regions := make([]int, len(grid.cells), allocator)
	best := make([]int, len(grid.cells), context.temp_allocator)
	distances := make([]int, len(grid.cells), context.temp_allocator)
	queue := make([dynamic]int, context.temp_allocator)
	for &r in regions do r = -1
	for &b in best do b = -1

	for spawn, six in spawns {
		for &d in distances do d = -1
		clear(&queue)
		start := hex.axialToIndex(spawn, grid.radius)
		distances[start] = 0
		append(&queue, start)
		for head := 0; head < len(queue); head += 1 {
			index := queue[head]
			cell := grid.cells[index]
			// mountains are reached but not crossed
			if !cell.value.mainArea && index != start do continue
			for nb in hex.AXIAL_NBS {
				next := cell.position.axial + nb
				if !hex.isWithinGrid(next, grid.radius) do continue
				nextIndex := hex.axialToIndex(next, grid.radius)
				if distances[nextIndex] >= 0 do continue
				distances[nextIndex] = distances[index] + 1
				append(&queue, nextIndex)
			}
		}
		for d, index in distances {
			if d < 0 do continue
			at := grid.cells[index].position.axial
			closer := best[index] < 0 || d < best[index]
			// ties go to the spawn nearer as the crow flies
			tie := d == best[index] && hex.distance(at, spawn) < hex.distance(at, spawns[regions[index]])
			if closer || tie {
				best[index] = d
				regions[index] = six
			}
		}
	}
	return regions
}

// mountain tiles that can be dug from the main area
goldCandidate :: proc(grid: GameGrid, index: int) -> bool {
	cell := grid.cells[index]
	if !cell.visible || cell.value.walkable || cell.value.color != MOUNTAIN_COLOR do return false
	for nb in hex.AXIAL_NBS {
		next := cell.position.axial + nb
		if hex.isWithinGrid(next, grid.radius) && grid.cells[hex.axialToIndex(next, grid.radius)].value.mainArea do return true
	}
	return false
}

// places the gold, using the context's random generator; returns the gold each region got
// and whether every region got a fair share
placeGold :: proc(grid: GameGrid, spawns: []hex.Axial, allocator := context.allocator) -> (placed: []int, fair: bool) {
	regions := goldRegions(grid, spawns, context.temp_allocator)
	quota := goldQuota(grid.radius, len(spawns))
	placed = make([]int, len(spawns), allocator)

	candidate := make([]bool, len(grid.cells), context.temp_allocator)
	for &cell, index in grid.cells {
		cell.value.gold = 0
		if !goldCandidate(grid, index) do continue
		near := false
		for spawn in spawns do if hex.distance(cell.position.axial, spawn) <= GOLD_SPAWN_CLEARANCE do near = true
		candidate[index] = !near
	}

	// a candidate is open while no gold lies within `gap` of it
	open :: proc(grid: GameGrid, candidate: []bool, index: int, gap: int) -> bool {
		if !candidate[index] || grid.cells[index].value.gold > 0 do return false
		at := grid.cells[index].position.axial
		for cell in grid.cells {
			if cell.value.gold > 0 && hex.distance(cell.position.axial, at) <= gap do return false
		}
		return true
	}

	// a seed's weight grows with its closeness to the middle of the map
	weight :: proc(grid: GameGrid, index: int) -> f32 {
		c := centerCloseness(grid.cells[index].position.axial, grid.radius)
		return GOLD_CORNER_WEIGHT + c * c
	}

	for gap := GOLD_CLUSTER_GAP; gap >= 0; gap -= 1 {
		for region in 0..<len(spawns) {
			for placed[region] < quota {
				total: f32 = 0
				for index in 0..<len(grid.cells) {
					if regions[index] == region && open(grid, candidate, index, gap) do total += weight(grid, index)
				}
				if total == 0 do break

				// the seed of the cluster
				pick := rand.float32() * total
				seed := -1
				for index in 0..<len(grid.cells) {
					if regions[index] != region || !open(grid, candidate, index, gap) do continue
					pick -= weight(grid, index)
					if pick <= 0 {
						seed = index
						break
					}
				}
				if seed < 0 do break

				// one to three tiles, bigger towards the middle
				closeness := centerCloseness(grid.cells[seed].position.axial, grid.radius)
				size := 1
				for _ in 0..<2 do if rand.float32() < closeness do size += 1

				cluster := make([dynamic]int, context.temp_allocator)
				append(&cluster, seed)
				grid.cells[seed].value.gold = 1
				placed[region] += 1
				grow: for len(cluster) < size && placed[region] < quota {
					for member in cluster {
						at := grid.cells[member].position.axial
						for nb in hex.AXIAL_NBS {
							next := at + nb
							if !hex.isWithinGrid(next, grid.radius) do continue
							nextIndex := hex.axialToIndex(next, grid.radius)
							if regions[nextIndex] != region || !candidate[nextIndex] || grid.cells[nextIndex].value.gold > 0 do continue
							grid.cells[nextIndex].value.gold = 1
							placed[region] += 1
							append(&cluster, nextIndex)
							continue grow
						}
					}
					break
				}
			}
		}
	}

	fair = true
	for count in placed do if count < goldFairMinimum(quota) do fair = false
	return placed, fair
}

// the least a region may hold, rounded down so tiny quotas forgive a missing tile
goldFairMinimum :: proc(quota: int) -> int {
	return int(f32(quota) * GOLD_FAIR_SHARE)
}
