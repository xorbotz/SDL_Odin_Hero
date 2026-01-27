package main


import "core:fmt"
import "core:math"


import "core:mem"

move_spec :: struct {
	accel_scale: f32,
	friction:    f32,
}

sim_region :: struct {
	world:            ^World,
	Center:           world_chunk_position,
	Bounds:           rectangle2,
	UpdateBounds:     rectangle2,
	Entity_Count:     u32,
	Max_Entity_Count: u32,
	Entities:         []sim_entitiy,
	sim_entity_lut:   map[u32]int,
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
	result.Offset = (curChunk.Offset + Delta - final * world.ChunkSideM)
	return result

}
LoadEntityReference :: proc(SimRegion: ^sim_region, LowEntityIndex: u32) -> ^sim_entitiy {
	if (LowEntityIndex != 0) {


	}
	return nil
}
dummy :: proc() {}
BeginSim :: proc(
	SimAlloc: ^mem.Allocator,
	world: ^World,
	RegionCenter: world_chunk_position,
	Bounds: rectangle2,
) -> ^sim_region {


	MinChunkP := MapIntoChunkSpace(world, RegionCenter, Bounds.min)
	MaxChunkP := MapIntoChunkSpace(world, RegionCenter, Bounds.max)
	if !AreInSameChunk(&MinChunkP, &MaxChunkP) {
		dummy()
	}
	cSR := new(sim_region, SimAlloc^)
	//TODO maybe a recursive tree - or our own hastable
	cSR.sim_entity_lut = make(map[u32]int, cSR.Max_Entity_Count, SimAlloc^)

	//TODO IMPORTANT - CALC this
	safetyMeasure: f32 = 1.0

	cSR.world = world
	cSR.Center = RegionCenter
	cSR.UpdateBounds = Bounds
	cSR.Bounds = AddRadiusTo(cSR.UpdateBounds, safetyMeasure, safetyMeasure)
	cSR.Entity_Count = 0
	//TODO THINK ABOUT THIS SIZE
	cSR.Max_Entity_Count = 4096
	cSR.Entities = make_slice([]sim_entitiy, cSR.Max_Entity_Count, SimAlloc^)
	for cY in MinChunkP.ChunkY ..= MaxChunkP.ChunkY {
		for cX in MinChunkP.ChunkX ..= MaxChunkP.ChunkX {

			curChunk := Get_Chunk(world, u32(cX), u32(cY), 0, true)
			for cBlock := &curChunk.First_BLock_Entities; cBlock != nil; cBlock = cBlock.Next {
				for index in 0 ..< cBlock.Entity_Count {
					LowEntityIndex := cBlock.Entity_Index[index]
					Low := &GameState.low_entities[LowEntityIndex]
					if .NONSPATIAL not_in Low.Stored.attributes {
						SimSpaceP := GetSimSpaceP(cSR, Low)
						if isInRectangle(&cSR.Bounds, &SimSpaceP) {
							SimSpaceP += .5 * {Low.Stored.width, Low.Stored.height}
							AddEntity(cSR, LowEntityIndex, Low, &SimSpaceP)
						}
					}
				}
			}


		}
	}
	for &Entity, index in cSR.Entities {
		if u32(index) > cSR.Entity_Count {
			break
		}
		sim_idx, ok := cSR.sim_entity_lut[Entity.targetIndex]
		if ok {
			Entity.targetTemp = &cSR.Entities[sim_idx]
		} else {
			Entity.targetIndex = 0
			Entity.targetTemp = nil
		}


	}


	return cSR
}
sim_entity_flag :: enum {
	COLLIDES,
	NONSPATIAL,
}
sim_entity_flags :: bit_set[sim_entity_flag;u32]

sim_entitiy :: struct {
	StorageIndex: u32,
	Updateable:   bool,
	attributes:   sim_entity_flags,
	Pos:          Vector2,
	dir:          u32,
	moving:       bool,
	z:            f32,
	dZ:           f32,
	type:         entity_type,
	dP:           Vector2,
	HitPointMax:  i32,
	width:        f32,
	height:       f32,
	targetIndex:  u32,
	targetTemp:   ^sim_entitiy,
}
AddEntity_Bare :: proc(SimRegion: ^sim_region) -> (^sim_entitiy, int) {
	Entity: ^sim_entitiy
	Index := -1
	if SimRegion.Entity_Count < SimRegion.Max_Entity_Count {
		Entity = &SimRegion.Entities[SimRegion.Entity_Count]
		Index = int(SimRegion.Entity_Count)
		SimRegion.Entity_Count += 1

	}
	return Entity, Index
}
AddEntity_wLow :: proc(
	SimRegion: ^sim_region,
	LowEntityIndex: u32,
	Entity: ^low_entity,
	simP: ^Vector2,
) -> ^sim_entitiy {
	Dest, Index := AddEntity(SimRegion)
	if Dest != nil {
		Dest^ = Entity.Stored
		Dest.StorageIndex = LowEntityIndex
		SimRegion.sim_entity_lut[LowEntityIndex] = Index
		if simP != nil {
			Dest.Pos = simP^
			Dest.Updateable = isInRectangle(&SimRegion.UpdateBounds, &Dest.Pos)
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
null_pos :: proc() -> world_chunk_position {
	r: world_chunk_position
	r.ChunkX = i32(max(u32))
	return r
}

EndSim :: proc(SimAlloc: ^mem.Allocator, region: ^sim_region, game_s: ^game_state) {
	for &curEntity, index in region.Entities {
		if u32(index) == region.Entity_Count {
			break

		}
		storedEnt := &game_s.low_entities[curEntity.StorageIndex]
		//TODO CHECK IF THIS ACTUALLY WORKS
		curEntity.Pos -= .5 * {curEntity.width, curEntity.height}
		storedEnt.Stored = curEntity
		NewP :=
			MapIntoChunkSpace(region.world, region.Center, curEntity.Pos) if .NONSPATIAL not_in curEntity.attributes else null_pos()
		ChangeEntityLocation(
			GameState,
			region.world,
			curEntity.StorageIndex,
			&storedEnt.chunk_position,
			&NewP,
		)

		// Do player check right here and update the world camera - todotomorrow

	}

	if game_s.Camera_Following_Entity_Index in region.sim_entity_lut {
		region.world.camera_pos =
			game_s.low_entities[game_s.Camera_Following_Entity_Index].chunk_position
		//UpdateWorldPos(GameState.world)
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
AddRadiusTo :: #force_inline proc(r: rectangle2, w, h: f32) -> rectangle2 {
	res := r
	res.min -= Vector2{w, h}
	res.max += Vector2{w, h}
	return res

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
//TODO Add a movespec struct
MoveEntity :: proc(
	SimRegion: ^sim_region,
	Entity: ^sim_entitiy,
	dt: f32,
	ddP: Vector2,
	moveSpec: move_spec,
) {
	//TODO Don't move apron entities just collisons
	assert(.NONSPATIAL not_in Entity.attributes, "Trying to move non-spatial entity")
	ddPlayer := ddP * moveSpec.accel_scale //m/s^2
	ddPlayer += moveSpec.friction * Entity.dP
	PlayerDelta := dt * Entity.dP + .5 * ddPlayer * dt * dt
	NewPlayer := Entity.Pos + PlayerDelta

	Entity.dP = ddPlayer * dt + Entity.dP

	P1 := Entity.Pos //GameState.Player_Position
	tLowest: f32 = 1
	r: Vector2 = {0, 0}
	if .COLLIDES in Entity.attributes {
		//TODO Spacial Partition
		for i in 0 ..< 4 {
			if tLowest == 0 {
				break
			}
			for TestEntity, index in SimRegion.Entities {
				if u32(index) == SimRegion.Entity_Count {
					break
				}
				if TestEntity.StorageIndex == Entity.StorageIndex {
					continue
				}
				if .COLLIDES in TestEntity.attributes && .NONSPATIAL not_in Entity.attributes {

					Diam: Vector2
					Diam.x = TestEntity.width + Entity.width
					Diam.y = TestEntity.height + Entity.height
					/*minCorner: Vector2 = {-1 * Entity.width, -1 * Entity.height - .005}
						maxCorner: Vector2 = {TestEntity.width + .005, TestEntity.height + .005}*/
					minCorner := -.5 * Diam
					maxCorner := .5 * Diam //+ {.1, .1}
					dist := Entity.Pos - TestEntity.Pos

					//					fmt.println("Distance: ", dist.x, dist.y, "Dir:", PlayerDelta.x, PlayerDelta.y)

					if (math.sign(dist.x) != math.sign(PlayerDelta.x) &&
						   math.abs(PlayerDelta.x) > 0) {
						if TestWall(
							minCorner.x, // - .5 * world.PlayerW,
							dist.x,
							dist.y,
							PlayerDelta.x,
							PlayerDelta.y,
							&tLowest,
							minCorner.y, // - Diam.y,
							maxCorner.y,
						) {
							r.x = 1
							r.y = 0
							fmt.println("Min X")
						}

					}
					if (math.sign(dist.x) != math.sign(PlayerDelta.x) &&
						   math.abs(PlayerDelta.x) > 0) {
						if TestWall(
							maxCorner.x, // + .5 * world.PlayerW,
							dist.x,
							dist.y,
							PlayerDelta.x,
							PlayerDelta.y,
							&tLowest,
							minCorner.y, // - Diam.y,
							maxCorner.y,
						) {
							r.x = -1
							r.y = 0

							fmt.println("Max X")
						}
					}

					if (math.sign(dist.y) != math.sign(PlayerDelta.y) &&
						   math.abs(PlayerDelta.y) > 0) {
						if TestWall(
							minCorner.y, // + world.PlayerH, //- world.PlayerH,
							dist.y,
							dist.x,
							PlayerDelta.y,
							PlayerDelta.x,
							&tLowest,
							minCorner.x, //- .5 * world.PlayerW,
							maxCorner.x, //+ .5 * world.PlayerW,
						) {
							r.y = 1
							r.x = 0
							fmt.println("Min Y")
						}
					}

					if (math.sign(dist.y) != math.sign(PlayerDelta.y) &&
						   math.abs(PlayerDelta.y) > 0) {
						if TestWall(
							maxCorner.y, // - world.PlayerH,
							dist.y,
							dist.x,
							PlayerDelta.y,
							PlayerDelta.x,
							&tLowest,
							minCorner.x, // - .5 * Diam.x,
							maxCorner.x, //+ .5 * Diam.y,
						) {
							r.y = -1
							r.x = 0
							fmt.println("Max Y")
						}
					}


					//}
				}
			}
			if tLowest != 1 {

				tEpsilon: f32 = 1

				Entity.Pos += tEpsilon * tLowest * PlayerDelta
				Entity.dP = Entity.dP - 1 * dot(Entity.dP, r) * r
				PlayerDelta = PlayerDelta - 1 * dot(PlayerDelta, r) * r
				PlayerDelta *= (1 - tLowest)

			} else {
				Entity.Pos += .9 * tLowest * PlayerDelta
				break
			}
			tLowest = 1
		}


		if Entity.dP.x < 0 {
			Entity.dir = 1
		} else {

			Entity.dir = 2
		}
		if (ddP.x != 0 || ddP.y != 0) {
			Entity.moving = true
		} else {
			Entity.moving = false
		}


	} else {

		Entity.Pos += .9 * PlayerDelta
	}
}
