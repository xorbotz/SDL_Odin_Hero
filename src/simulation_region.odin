package main


import "core:slice"

import "core:encoding/endian"
import "core:fmt"
import "core:math"
import "core:os"

import "core:mem"

sim_region :: struct {
	Entity_Count:     u32,
	Max_Entity_Count: u32,
	Entities:         [^]hf_entity,
}


BeginSim :: proc(Bounds: rectangle2) -> ^sim_region {

}
EndSim :: proc(region: ^sim_region) {
	for e_index: u32 = 0; e_index < region.Entity_Count; e_index += 1 {
		curEntity := region.Entities[e_index]
		StoreEntity(curEntity)
	}

}
StoreEntity :: proc(entity: hf_entity) {}
rectangle2 :: struct {
	min: Vector2,
	max: Vector2,
}

RectDim :: proc(bottom_left: Vector2, Dim: Vector2) -> rectangle2 {

	result: rectangle2
	result.min = bottom_left
	result.max = result.min + Dim
	return result
}
