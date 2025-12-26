package main
MaxChunk: u32 : 256


tile_chunk_position :: struct {
	AbsTileX: i32,
	AbsTileY: i32,
	AbsTileZ: i32,
	Offset:   Vector2,
}
tile_chunk :: struct {
	ChunkX:               u32,
	ChunkY:               u32,
	ChunkZ:               u32,
	TileX:                u32,
	TileY:                u32,
	Tiles:                [^]u32,
	NextinHash:           ^tile_chunk,
	First_BLock_Entities: tile_entity_block,
}
tile_entity_block :: struct {
	Entity_Count: u32,
	Entity_Index: [16]dormant_entity,
	Next:         ^tile_entity_block,
}

Tile_Map :: struct {
	TileSideM:  f32,
	tile_chunk: [4096]tile_chunk,
}

hash_point :: #force_inline proc(ChunkX, ChunkY, ChunkZ: u32) -> u32 {
	return ChunkX * 19 + ChunkY * 7 + ChunkZ * 3
}
