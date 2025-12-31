package main

import "core:simd/x86"

import "core:slice"

import "core:encoding/endian"
import "core:fmt"
import "core:math"
import "core:os"

import "core:mem"

sim_region :: struct {
	world:            ^World,
	Center:           world_chunk_position,
	Bounds:           rectangle2,
	Entity_Count:     u32,
	Max_Entity_Count: u32,
	Entities:         []sim_entitiy,
}


VectorFloor :: #force_inline proc(V1, V2: Vector2) -> Vector2 {
	Result: Vector2
	Result.x = math.floor(V1.x / V2.x)
	Result.y = math.floor(V1.y / V2.y)
	return Result
}
MapIntoChunkSpace :: proc(
	world: ^World,
	curChunk: world_chunk_position,
	Delta: Vector2,
) -> world_chunk_position {
	final := VectorFloor(curChunk.Offset + Delta, world.ChunkSideM)
	result: world_chunk_position
	result.ChunkX = curChunk.ChunkX + i32(final.x)
	result.ChunkY = curChunk.ChunkY + i32(final.y)
	result.ChunkZ = 0
	return result

}
BeginSim :: proc(
	SimAlloc: ^mem.Allocator,
	world: ^World,
	RegionCenter: world_chunk_position,
	Bounds: rectangle2,
) -> ^sim_region {


	MinChunkP := MapIntoChunkSpace(world, RegionCenter, Bounds.min)
	MaxChunkP := MapIntoChunkSpace(world, RegionCenter, Bounds.max)
	cSR := new(sim_region, SimAlloc^)

	cSR.world = world
	cSR.Center = RegionCenter
	cSR.Bounds = Bounds
	cSR.Entity_Count = 0
	//TODO THINK ABOUT THIS SIZE
	cSR.Max_Entity_Count = 4096
	cSR.Entities = make([]sim_entitiy, cSR.Max_Entity_Count)
	for cY in MinChunkP.ChunkY ..= MaxChunkP.ChunkY {
		for cX in MinChunkP.ChunkX ..= MaxChunkP.ChunkX {

			curChunk := Get_Chunk(world, u32(cX), u32(cY), 0, true)
			for cBlock := &curChunk.First_BLock_Entities; cBlock != nil; cBlock = cBlock.Next {
				for index in 0 ..< cBlock.Entity_Count {
					LowEntityIndex := cBlock.Entity_Index[index]
					Low := &GameState.low_entities[LowEntityIndex]
					SimSpaceP := GetSimSpaceP(cSR, Low)
					if isInRectangle(&cSR.Bounds, &SimSpaceP) {
						AddEntity(cSR, Low, &SimSpaceP)}
				}
			}


		}
	}
	S: ^sim_region
	return S
}
sim_entitiy :: struct {
	StorageIndex: u32,
	Pos:          Vector2,
	dir:          u32,
	z:            f32,
	dZ:           f32,
}
AddEntity_Bare :: proc(SimRegion: ^sim_region) -> ^sim_entitiy {
	Entity: ^sim_entitiy
	if SimRegion.Entity_Count < SimRegion.Max_Entity_Count {
		Entity = &SimRegion.Entities[SimRegion.Entity_Count]
		SimRegion.Entity_Count += 1

	}
	return Entity
}
AddEntity_wLow :: proc(
	SimRegion: ^sim_region,
	Entity: ^low_entity,
	simP: ^Vector2,
) -> ^sim_entitiy {
	Dest := AddEntity(SimRegion)
	if Dest != nil {
		if simP != nil {
			Dest.Pos = simP^
		} else {
			Dest.Pos = GetSimSpaceP(SimRegion, Entity)
		}
		return Dest

	}
	return Dest
}
AddEntity :: proc {
	AddEntity_Bare,
	AddEntity_wLow,
}
GetSimSpaceP :: #force_inline proc(SimRegion: ^sim_region, Stored: ^low_entity) -> Vector2 {
	return Subtract_W(SimRegion.world, &SimRegion.Center, &Stored.chunk_position)
}

EndSim :: proc(SimAlloc: ^mem.Allocator, region: ^sim_region, game_s: ^game_state) {
	for curEntity in region.Entities {
		storedEnt := &game_s.low_entities[curEntity.StorageIndex]
		NewP := MapIntoChunkSpace(region.world, region.Center, curEntity.Pos)
		ChangeEntityLocation(
			region.world,
			curEntity.StorageIndex,
			&storedEnt.chunk_position,
			&NewP,
		)
		// Do player check right here and update the world camera - todotomorrow
		UpdateWorldPos(GameState.world)

	}
	free_all(SimAlloc^)
}
StoreEntity :: proc(entity: sim_entitiy) {}
rectangle2 :: struct {
	min: Vector2,
	max: Vector2,
}
RectCenterDim :: #force_inline proc(Center: Vector2, Dim: Vector2) -> rectangle2 {

	result: rectangle2
	result.min = Center - Dim
	result.max = Center + Dim
	return result
}
RectDim :: #force_inline proc(bottom_left: Vector2, Dim: Vector2) -> rectangle2 {

	result: rectangle2
	result.min = bottom_left
	result.max = result.min + Dim
	return result
}
//TODO inline?
isInRectangle :: #force_inline proc(Bounds: ^rectangle2, Pos: ^Vector2) -> bool {
	return(
		Bounds.min.x <= Pos.x &&
		Bounds.min.y <= Pos.y &&
		Bounds.max.x >= Pos.x &&
		Bounds.max.y >= Pos.y \
	)
}
