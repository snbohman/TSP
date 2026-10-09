package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// (n-1)! orderings get checked, so 11 points is still interactive
maxBrute :: 12
pointRadius :: 5
loadPoints :: 10

Tour :: struct {
	order:  [dynamic]int, // city indices in visiting order
	length: f32,
}

State :: struct {
	points:  [dynamic]rl.Vector2,
	best:    Tour,
	dragIdx: int, // -1 when nothing is being dragged
	dirty:   bool, // points changed, tour needs recomputing
	solveMs: f64,
    iterations: int,
}

// Each line is "x,y". Lines that fail to parse (e.g. a header) are skipped.
loadCsv :: proc(path: string, maxPoints: int) -> (pts: [dynamic]rl.Vector2) {
	cPath := strings.clone_to_cstring(path, context.temp_allocator)
	raw := rl.LoadFileText(cPath)
	if raw == nil { return }
	defer rl.UnloadFileText(raw)

	text := string(cstring(raw))
	for line in strings.split_lines_iterator(&text) {
        if len(pts) >= maxPoints { break }

		cols := strings.split(line, ",", context.temp_allocator)
		if len(cols) < 2 {
			continue
		}

		x, okX := strconv.parse_f32(strings.trim_space(cols[0]))
		y, okY := strconv.parse_f32(strings.trim_space(cols[1]))
		if okX && okY {
			append(&pts, 20 + 7*rl.Vector2{x, y})
		}
	}

	return
}

precomputeDist :: proc(pts: []rl.Vector2) -> []f32 {
    n := len(pts)
    dist := make([]f32, n * n)

    for i in 0 ..< n {
        for j in 0 ..< n {
            dist[i * n + j] = rl.Vector2Distance(pts[i], pts[j])
        }
    }

    return dist
}

// Recursively tries every ordering of perm[depth:]. perm[0] stays fixed as the start.
// length is the distance of the path built so far (perm[0..depth-1]).
bruteForce :: proc(dist: []f32, perm: []int, depth: int, length: f32, best: ^Tour, iterations: ^int) {
	n := len(perm)

	// all cities placed: close the loop back to the start and compare
	if depth == n {
		iterations^ += 1

		total := length + dist[perm[n - 1] * n + perm[0]]
		if total < best.length {
			best.length = total
			copy(best.order[:], perm)
		}
		return
	}

	// try each remaining city at this position by swapping it in
	for i in depth ..< n {
		perm[depth], perm[i] = perm[i], perm[depth]       // swap slots d. & i

		step := dist[perm[depth - 1] * n + perm[depth]]
		bruteForce(dist, perm, depth + 1, length + step, best, iterations)

        perm[depth], perm[i] = perm[i], perm[depth] // undo the swap
	}
}

// Index of the point under the mouse, or -1
pickPoint :: proc(pts: []rl.Vector2, mouse: rl.Vector2) -> int {
	for p, i in pts {
		if rl.Vector2Distance(p, mouse) <= pointRadius + 4 {
			return i
		}
	}
	return -1
}

// Sets up the buffers bruteForce expects. Requires len(pts) >= 1.
solve :: proc(pts: []rl.Vector2) -> (best: Tour, iterations: int) {
	n := len(pts)
	best = Tour {
		order  = make([dynamic]int, n), // copy() needs the slots to exist
		length = max(f32), // so the first tour always wins
	}

	dist := precomputeDist(pts)
	defer delete(dist)

	perm := make([]int, n)
	defer delete(perm)
	for i in 0 ..< n {
		perm[i] = i
	}

	bruteForce(dist, perm, 1, 0, &best, &iterations)
	return
}

update :: proc(s: ^State) {
	mouse := rl.GetMousePosition()

	// press: grab a point, or add a new one on empty space
	if rl.IsMouseButtonPressed(.LEFT) {
		s.dragIdx = pickPoint(s.points[:], mouse)
		if s.dragIdx < 0 {
			append(&s.points, mouse)
			s.dirty = true
		}
	}

	if rl.IsMouseButtonReleased(.LEFT) {
		s.dragIdx = -1
	}

	if s.dragIdx >= 0 && rl.IsMouseButtonDown(.LEFT) {
		s.points[s.dragIdx] = mouse
		s.dirty = true
	}

	// right click removes a point
	if rl.IsMouseButtonPressed(.RIGHT) {
		idx := pickPoint(s.points[:], mouse)
		if idx >= 0 {
			ordered_remove(&s.points, idx)
			s.dirty = true
		}
	}

	// re-solve only when something changed
	if s.dirty {
        defer s.dirty = false;
		delete(s.best.order)
		s.best, s.iterations = {}, 0

        n := len(s.points)
		if n >= 1 && len(s.points) <= maxBrute {
			start := rl.GetTime()
            s.best, s.iterations = solve(s.points[:])
			s.solveMs = (rl.GetTime() - start) * 1000
		}
	}
}

draw :: proc(s: ^State) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	// tour edges, the modulo closes the loop back to the first city
	n := len(s.best.order)
	for i in 0 ..< n {
		a := s.points[s.best.order[i]]
		b := s.points[s.best.order[(i + 1) % n]]
		rl.DrawLineEx(a, b, 2, rl.GRAY)
	}

	// points, the start city is red
	for p, i in s.points {
		rl.DrawCircleV(p, pointRadius, rl.BLACK)
	}

	if len(s.points) > maxBrute {
        msg := fmt.ctprintf("points [%d] > max [%d]", len(s.points), maxBrute)
		rl.DrawText(msg, 10, 10, 18, rl.RED)
	} else {
        msg := fmt.ctprintf("%d# : [%.1fm, %.2fms]", len(s.points), s.best.length, s.solveMs)
		rl.DrawText(msg, 10, 10, 18, rl.DARKGRAY)
	}
}

main :: proc() {
	s := State {
		dragIdx = -1,
		dirty   = true,
	}

	if len(os.args) > 1 {
		s.points = loadCsv(os.args[1], loadPoints)
	}

	rl.SetConfigFlags({.MSAA_4X_HINT})
	rl.InitWindow(1000, 700, "TSP brute force")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		update(&s)
		draw(&s)
		free_all(context.temp_allocator)
	}
}
