package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// (n-1)! orderings get checked, so 11 points is still interactive
maxBrute :: 11
pointRadius :: 10

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
}

// Each line is "x,y". Lines that fail to parse (e.g. a header) are skipped.
loadCsv :: proc(path: string) -> (pts: [dynamic]rl.Vector2) {
	cPath := strings.clone_to_cstring(path, context.temp_allocator)
	raw := rl.LoadFileText(cPath)
	if raw == nil { return }
	defer rl.UnloadFileText(raw)

	text := string(cstring(raw))
	for line in strings.split_lines_iterator(&text) {
		cols := strings.split(line, ",", context.temp_allocator)
		if len(cols) < 2 {
			continue
		}

		x, okX := strconv.parse_f32(strings.trim_space(cols[0]))
		y, okY := strconv.parse_f32(strings.trim_space(cols[1]))
		if okX && okY {
			append(&pts, rl.Vector2{x, y})
		}
	}

	return
}

// Rearranges a into the next lexicographic permutation.
// Returns false once the last permutation has been passed.
nextPermutation :: proc(a: []int) -> bool {
	// find the rightmost position that can still be increased
	i := len(a) - 2
	for i >= 0 && a[i] >= a[i + 1] {
		i -= 1
	} if i < 0 {
		return false
	}

	// swap it with the smallest larger value to its right
	j := len(a) - 1
	for a[j] <= a[i] {
		j -= 1
	}
	a[i], a[j] = a[j], a[i]

	// the tail is now descending, reverse it to get the smallest tail
	slice.reverse(a[i + 1:])
	return true
}

bruteForce :: proc(pts: []rl.Vector2) -> Tour {
	n := len(pts)
	best := Tour {
		order  = make([dynamic]int, n),
		length = max(f32),
	}

	// precompute all pairwise distances once
	dist := make([]f32, n * n)
	defer delete(dist)
	for i in 0 ..< n {
		for j in 0 ..< n {
			dist[i * n + j] = rl.Vector2Distance(pts[i], pts[j])
		}
	}

	// start with the identity ordering 0,1,2,...
	perm := make([]int, n)
	defer delete(perm)
	for i in 0 ..< n {
		perm[i] = i
	}

	// trivial cases have nothing to permute
	if n < 3 {
		copy(best.order[:], perm)
		best.length = n == 2 ? 2 * dist[1] : 0
		return best
	}

	// City 0 stays first, only the rest is permuted.
	// A tour is a cycle, so fixing the start loses nothing.
	for {
		// closing edge back to the start, then every edge along the path
		total := dist[perm[n - 1] * n + perm[0]]
		for i in 0 ..< n - 1 {
			total += dist[perm[i] * n + perm[i + 1]]
		}

		if total < best.length {
			best.length = total
			copy(best.order[:], perm)
		}

		if !nextPermutation(perm[1:]) {
			break
		}
	}
	return best
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
		delete(s.best.order)
		s.best = {}

		if len(s.points) <= maxBrute {
			start := rl.GetTime()
			s.best = bruteForce(s.points[:])
			s.solveMs = (rl.GetTime() - start) * 1000
		}
		s.dirty = false
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
		rl.DrawLineEx(a, b, 2, rl.SKYBLUE)
	}

	// points, the start city is red
	for p, i in s.points {
		color := i == 0 ? rl.RED : rl.DARKBLUE
		rl.DrawCircleV(p, pointRadius, color)
		rl.DrawText(fmt.ctprintf("%d", i), i32(p.x) + 12, i32(p.y) - 20, 16, rl.DARKGRAY)
	}

	rl.DrawText("LMB: add / drag    RMB: remove", 10, 10, 18, rl.DARKGRAY)

	if len(s.points) > maxBrute {
		msg := fmt.ctprintf("%d points: too many for brute force (max %d)", len(s.points), maxBrute)
		rl.DrawText(msg, 10, 34, 18, rl.RED)
	} else {
		msg := fmt.ctprintf("n=%d  length=%.1f  solved in %.2f ms", len(s.points), s.best.length, s.solveMs)
		rl.DrawText(msg, 10, 34, 18, rl.DARKGRAY)
	}
}

main :: proc() {
	s := State {
		dragIdx = -1,
		dirty   = true,
	}

	if len(os.args) > 1 {
		s.points = loadCsv(os.args[1])
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
