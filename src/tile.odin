package main
MaxChunk: u32 : 256


world_chunk_position :: struct {
	ChunkX: i32,
	ChunkY: i32,
	ChunkZ: i32,
	Offset: Vector2,
}
world_chunk :: struct {
	ChunkX:               u32,
	ChunkY:               u32,
	ChunkZ:               u32,
	TileX:                u32,
	TileY:                u32,
	NextinHash:           ^world_chunk,
	First_BLock_Entities: world_entity_block,
}
world_entity_block :: struct {
	Entity_Count: u32,
	Entity_Index: [16]u32,
	Next:         ^world_entity_block,
}

World_Map :: struct {
	TileSideM: f32,
	//TODO possibly change this to pointers if tile_chunk continues to have an array
	// of entities as it is wasting lots of space
}
World :: struct {
	worldchunks:     [4096]world_chunk,
	Upperleftstartx: f32,
	Upperleftstarty: f32,
	LowerLeftStartX: f32,
	LowerLeftStartY: f32,
	TileSidePixels:  f32,
	TileSideM:       f32,
	MapWidth:        i32,
	MetersToPixels:  f32,
	ChunkShift:      u32,
	ChunkDim:        u32,
	ChunkX:          u32,
	ChunkY:          u32,
	ChunkSideM:      Vector2,
	Window_Pos:      global_position,
	camera_pos:      world_chunk_position,
	PlayerW:         f32,
	PlayerH:         f32,
	oneMinPH:        f32,
	FirstFree:       ^world_entity_block,
}

hash_point :: #force_inline proc(ChunkX, ChunkY, ChunkZ: u32) -> u32 {
	return ChunkX * 19 + ChunkY * 7 + ChunkZ * 3
}
