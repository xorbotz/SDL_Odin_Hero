
package main
import "core:math"

Vector2 :: [2]f32
dot :: proc(a: Vector2, b: Vector2) -> f32 {
	//	fmt.println("ax bx ay, by: ", a.x, b.x, a.y, b.y)
	return a.x * b.x + a.y * b.y
}

V2LengthSq :: #force_inline proc(A: Vector2) -> f32 {
	return dot(A, A)
}

V2Length :: #force_inline proc(A: Vector2) -> f32 {
	return math.sqrt(V2LengthSq(A))
}
