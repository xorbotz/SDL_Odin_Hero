package main
import "core:slice"

import "core:encoding/endian"
import "core:fmt"
import "core:math"
import "core:os"

import "core:mem"

TURNOFF :: #config(TURNOFF, false)
DEBUG :: #config(DEBUG, false)

debug_mode: bool = true
Game_Mem: ^game_memory
GameState: ^game_state

windowSizey: u32 : 9
windowSizex: u32 : 17

//TODO Move to math file

ChangeEntityLocation :: #force_inline proc(
	GameState: ^game_state,
	world: ^World,
	LowEntityIndex: u32,
	OldP, NewP: ^world_chunk_position,
) {
	//fmt.print("justcommit")
	if OldP != nil && AreInSameChunk(OldP, NewP) {
		GameState.low_entities[LowEntityIndex].chunk_position.Offset = NewP.Offset

	} else {
		if (OldP != nil) {
			curChunk: ^world_chunk = Get_Chunk(
				world,
				u32(OldP.ChunkX),
				u32(OldP.ChunkY),
				u32(OldP.ChunkZ),
				true,
			)
			assert(curChunk != nil)

			FirstBlock := &curChunk.First_BLock_Entities
			outer: for block: ^world_entity_block = FirstBlock; block != nil; block = block.Next {
				//TODO SIMD THIS, maybe store this as a binary tree etc
				for value, index in block.Entity_Index {
					if u32(index) == block.Entity_Count {
						break
					}
					if value == LowEntityIndex {
						FirstBlock.Entity_Count -= 1
						block.Entity_Index[index] =
							FirstBlock.Entity_Index[FirstBlock.Entity_Count]
						if FirstBlock.Entity_Count == 0 {
							if FirstBlock.Next != nil {
								temp := FirstBlock.Next
								FirstBlock^ = FirstBlock.Next^
								temp.Next = world.FirstFree
								world.FirstFree = temp

							}
						}
						break outer
					}


				}

			}
		}


		if (NewP != nil) {
			curChunk: ^world_chunk = Get_Chunk(
				world,
				u32(NewP.ChunkX),
				u32(NewP.ChunkY),
				u32(NewP.ChunkZ),
				true,
			)
			Block: ^world_entity_block = &curChunk.First_BLock_Entities
			if Block.Entity_Count == len(Block.Entity_Index) {
				OldBlock := world.FirstFree
				if OldBlock != nil {
					world.FirstFree = OldBlock.Next
				} else {
					OldBlock = new(world_entity_block, GameMemory.PermanentStorageAlloc)
				}
				OldBlock^ = Block^
				Block.Next = OldBlock
				Block.Entity_Count = 0

			}
			Block.Entity_Index[Block.Entity_Count] = LowEntityIndex
			Block.Entity_Count += 1

			GameState.low_entities[LowEntityIndex].Stored.attributes -= {.NONSPATIAL}
		} else {

			GameState.low_entities[LowEntityIndex].Stored.attributes += {.NONSPATIAL}
		}

	}
}

AreInSameChunk :: #force_inline proc(OldP, NewP: ^world_chunk_position) -> bool {
	return OldP.ChunkX == NewP.ChunkX && OldP.ChunkY == NewP.ChunkY && OldP.ChunkZ == NewP.ChunkZ
}

TestWall :: proc(
	Wall: f32,
	RelTarget: f32,
	RelFixed: f32,
	PlayerDeltTarget: f32,
	PlayerDeltaFixed: f32,
	tMin: ^f32,
	minFixed: f32,
	maxFixed: f32,
) -> bool {


	if PlayerDeltTarget != 0 {
		tResult := -1 * (RelTarget - Wall) / PlayerDeltTarget
		Y := RelFixed + tResult * PlayerDeltaFixed
		if (tResult >= 0 && tMin^ > tResult) {
			if (false || (Y > minFixed && Y < maxFixed)) {

				tMin^ = tResult
				fmt.println("Updating Tmin: ", Wall, RelTarget, PlayerDeltTarget, tMin^)

				return true
			}
		}

	}

	return false
}
Subtract_W :: #force_inline proc(world: ^World, p1, p2: ^world_chunk_position) -> Vector2 {
	result: Vector2
	result.x = f32(p2.ChunkX - p1.ChunkX) * world.ChunkSideM.x + (p2.Offset.x - p1.Offset.x)

	result.y = f32(p2.ChunkY - p1.ChunkY) * world.ChunkSideM.y + (p2.Offset.y - p1.Offset.y)
	return result
}
SubTile :: proc(world: ^World, p1, p2: ^global_position) -> Vector2 {
	x :=
		(f32(p2.AbsTileX) - f32(p1.AbsTileX)) * world.TileSideM + p2.TileOffSet.x - p1.TileOffSet.x
	y :=
		(f32(p2.AbsTileY) - f32(p1.AbsTileY)) * world.TileSideM + p2.TileOffSet.y - p1.TileOffSet.y

	dist: Vector2
	dist.x = x
	dist.y = y
	return dist

}
Max :: proc(a, b: $T) -> T {
	if a < b {
		return b
	}
	return a
}
Min :: proc(a, b: $T) -> T {
	if a < b {
		return a
	}
	return b
}
Vector2 :: [2]f32
dot :: proc(a: Vector2, b: Vector2) -> f32 {
	//	fmt.println("ax bx ay, by: ", a.x, b.x, a.y, b.y)
	return a.x * b.x + a.y * b.y
}


bmp :: struct {
	FileType:  u16,
	FileSize:  u32,
	somename:  u16,
	somename2: u16,
	Offset:    u32,
	width:     i32,
	height:    i32,
	Planes:    u16,
	bpp:       u16,
}
game_memory :: struct {
	isInit:                bool,
	arenaInit:             bool,
	Permanentstoragesize:  u64,
	PermanentStorage:      rawptr,
	Transientstoragesize:  u64,
	Transientstorage:      rawptr,
	PermanentStorageAlloc: mem.Allocator,
}
entity :: struct {
	residence: entity_res,
	dormant:   ^low_entity,
	high:      ^hf_entity,
}

entity_res :: enum {
	HIGH,
	LOW,
	DORMANT,
}

entity_type :: enum {
	NULL,
	HERO,
	WALL,
	MONSTER,
	PROJECTILE,
}
direction :: enum {
	UP,
	DOWN,
	LEFT,
	RIGHT,
}
hf_entity :: struct {
	pc:                bool,
	exists:            bool,
	type:              entity_type,
	pos:               Vector2,
	dPos:              Vector2,
	ddPos:             Vector2,
	dir:               u32,
	width:             f32,
	height:            f32,
	moving:            bool,
	facing:            direction,
	Left:              bool,
	Right:             bool,
	dorm_entity_index: u32,
}
low_entity_chunk_ref :: struct {
	TileChunk:    ^world_chunk,
	IndexInChunk: u32,
}
//TODO currently i have some silly casey code that has invalid positions and a flag and that seems redundant
low_entity :: struct {
	Stored:         sim_entitiy,
	chunk_position: world_chunk_position,
}


getEntity :: proc(GameState: ^game_state, index: u32) -> entity {
	e: entity
	e.dormant = &GameState.low_entities[index]
	e.high = &GameState.high_entities[index] //nil
	return e
}
addWall :: proc(GameState: ^game_state, ChunkX, ChunkY, ChunkZ, Xshift, Yshift: u32) -> u32 {
	EI := addEntity(GameState)
	GameState.low_entities[EI].chunk_position.ChunkX = i32(ChunkX)
	GameState.low_entities[EI].chunk_position.ChunkY = i32(ChunkY)
	GameState.low_entities[EI].chunk_position.ChunkZ = i32(ChunkZ)

	GameState.low_entities[EI].chunk_position.Offset = {
		f32(Xshift) * GameState.world.TileSideM,
		f32(Yshift) * GameState.world.TileSideM,
	}
	GameState.low_entities[EI].Stored.height = GameState.world.TileSideM
	GameState.low_entities[EI].Stored.width = GameState.low_entities[EI].Stored.height
	GameState.low_entities[EI].Stored.attributes += {.COLLIDES}
	ChangeEntityLocation(
		GameState,
		GameState.world,
		EI,
		nil,
		&GameState.low_entities[EI].chunk_position,
	)
	return EI


}
when (TURNOFF) {
	addMonster :: proc(GameState: ^game_state, AbsTileX, AbsTileY, AbsTileZ: u32) -> u32 {
		EI := addEntity(GameState)
		GameState.low_entities[EI].Stored.position.AbsTileX = AbsTileX
		GameState.low_entities[EI].Stored.position.AbsTileY = AbsTileY
		GameState.low_entities[EI].Stored.position.AbsTileZ = AbsTileZ
		GameState.low_entities[EI].chunk_position = To_Chunk_Pos(
			&GameState.low_entities[EI].Stored.position,
			GameState.world,
		)
		GameState.low_entities[EI].Stored.height = .5
		GameState.low_entities[EI].Stored.width = 1.0
		GameState.low_entities[EI].Stored.attributes += {.COLLIDES}
		return EI


	}
}
addEntity :: proc(GameState: ^game_state) -> u32 {
	fmt.println("Adding Entity", GameState.entityCount)
	assert(GameState.entityCount < len(GameState.low_entities) - 1)
	eC := GameState.entityCount
	GameState.low_entities[GameState.entityCount] = {}
	GameState.entityCount += 1
	return eC
}


thread_context :: struct {
	temp: i32,
}

global_position :: struct {
	AbsTileX:   u32,
	AbsTileY:   u32,
	AbsTileZ:   u32,
	TileOffSet: Vector2,
	Left:       bool,
	Right:      bool,
	moving:     bool,
}
Get_Chunk :: #force_inline proc(
	world: ^World,
	ChunkX, ChunkY, ChunkZ: u32,
	create: bool,
) -> ^world_chunk {
	/*	assert(ChunkX > MaxChunk)
	assert(ChunkY > MaxChunk)
	assert(ChunkZ > MaxChunk)

	assert(ChunkX < max(u32) - MaxChunk)
	assert(ChunkY < max(u32) - MaxChunk)
	assert(ChunkZ < max(u32) - MaxChunk)*/
	HashValue := hash_point(ChunkX, ChunkY, ChunkZ)
	HashSlot := HashValue & (len(world.worldchunks) - 1)

	cur_Chunk := &world.worldchunks[HashSlot]


	for true {

		if cur_Chunk.ChunkX == ChunkX && cur_Chunk.ChunkY == ChunkY && cur_Chunk.ChunkZ == ChunkZ {
			break
		} else if create && cur_Chunk.ChunkX != 0 && cur_Chunk.NextinHash == nil {
			fmt.println("Collision")
			cur_Chunk.NextinHash = Alloc_Chunk_C(world, ChunkX, ChunkY, ChunkZ)

			return cur_Chunk.NextinHash
		} else if create && cur_Chunk.ChunkX == 0 {
			//TODO Currently this does nothing
			cur_Chunk^ = Alloc_Chunk_C(world, ChunkX, ChunkY, ChunkZ)^
			return cur_Chunk
		}
		cur_Chunk = cur_Chunk.NextinHash


	}

	//	map1 := world.chunks[chunk_p.ChunkY * world.ChunkX + chunk_p.ChunkX]
	//	return map1

	return cur_Chunk
}
Alloc_Chunk_C :: proc(world: ^World, ChunkX, ChunkY, ChunkZ: u32) -> ^world_chunk {

	mapn := new(world_chunk, GameMemory.PermanentStorageAlloc)
	mapn.ChunkX = ChunkX
	mapn.ChunkY = ChunkY
	mapn.ChunkZ = ChunkZ
	mapn.NextinHash = nil


	mappoint: ^[32][32]u32 = new([32][32]u32, GameMemory.PermanentStorageAlloc)

	when (TURNOFF) {
		if false {
			for i := 0; i < 32; i += 1 {
				for j := 0; j < 32; j += 1 {
					if i == 0 || i == 31 {
					} else if j == 0 || j == 31 {


						addWall(
							GameState,
							ChunkX * world.ChunkDim + u32(j),
							ChunkY * world.ChunkDim + u32(i),
							0,
						)

					} else if i % 3 == 0 && j % 5 == 0 {


						addWall(
							GameState,
							ChunkX * world.ChunkDim + u32(j),
							ChunkY * world.ChunkDim + u32(i),
							0,
						)
					} else if (i == 3 && j == 6) || (i == 3 && j == 7) {

						addWall(
							GameState,
							ChunkX * world.ChunkDim + u32(j),
							ChunkY * world.ChunkDim + u32(i),
							0,
						)

					} else {
					}

				}
			}
			//	mapn.Tiles = ([^]u32)(mappoint) //(raw_data(&Tilemap))
			addWall(
				GameState,
				ChunkX * world.ChunkDim + u32(0),
				ChunkY * world.ChunkDim + u32(0),
				0,
			)}
	}


	return mapn

}
Alloc_Chunk :: proc() -> ^Map {
	mapn := new(Map, GameMemory.PermanentStorageAlloc)


	mappoint: ^[32][32]i32 = new([32][32]i32, GameMemory.PermanentStorageAlloc)


	for i := 0; i < 32; i += 1 {
		for j := 0; j < 32; j += 1 {
			if i == 0 || i == 31 {
				mappoint^[i][j] = 1
			} else if j == 0 || j == 31 {

				mappoint^[i][j] = 1
			} else if i % 3 == 0 && j % 5 == 0 {

				mappoint^[i][j] = 1
			} else if (i == 3 && j == 6) || (i == 3 && j == 7) {
				mappoint^[i][j] = 1

			} else {
				mappoint^[i][j] = 0
			}

		}
	}
	mappoint^[31][9] = 0
	mappoint^[31][10] = 0
	mappoint^[0][9] = 0
	mappoint^[0][10] = 0
	mappoint^[9][0] = 0
	mappoint^[12][0] = 0
	mappoint^[11][0] = 0
	mappoint^[10][0] = 0
	mappoint^[9][31] = 0
	mappoint^[10][31] = 0
	mappoint^[11][31] = 0
	mappoint^[12][31] = 0

	mapn.Tilemap = ([^]i32)(mappoint) //(raw_data(&Tilemap))
	return mapn

}
To_Chunk_Pos :: #force_inline proc(
	Player_Position: ^global_position,
	world: ^World,
) -> world_chunk_position {
	res: world_chunk_position
	res.ChunkX = i32(Player_Position.AbsTileX >> world.ChunkShift)
	res.ChunkY = i32(Player_Position.AbsTileY >> world.ChunkShift)
	res.ChunkZ = 0
	res.Offset = Player_Position.TileOffSet
	return res

}

UpdateWorldPos :: #force_inline proc(world: ^World) {


	world.camera_pos = GameState.low_entities[GameState.Player_low_index].chunk_position


}
Recon_Position :: #force_inline proc(Player_Position: ^global_position, world: ^World) {


	if Player_Position.TileOffSet.x < 0 {
		Player_Position.AbsTileX -= 1
		Player_Position.TileOffSet.x = world.TileSideM + Player_Position.TileOffSet.x

	} else if Player_Position.TileOffSet.x > world.TileSideM {
		Player_Position.AbsTileX += 1
		Player_Position.TileOffSet.x -= world.TileSideM

	}
	if Player_Position.TileOffSet.y < 0 {
		Player_Position.AbsTileY -= 1
		Player_Position.TileOffSet.y = world.TileSideM + Player_Position.TileOffSet.y

	} else if Player_Position.TileOffSet.y > world.TileSideM {
		Player_Position.AbsTileY += 1
		Player_Position.TileOffSet.y -= world.TileSideM

	}

}

game_state :: struct {
	world:                         ^World,
	arena:                         mem_arena,
	Player_Position:               global_position,
	Player_low_index:              u32,
	Camera_Following_Entity_Index: u32,
	backGroundData:                []u8,
	backGroundBmap:                ^bmp,
	playerBmap:                    ^bmp,
	playerData:                    []u8,
	count:                         u64,
	Speed:                         uint,
	dPlayer:                       Vector2, //TODO MOVE TO hf_entity
	entityCount:                   u32,
	entity_residence:              [256]entity_res,
	high_entities:                 [256]hf_entity,
	low_entities:                  [10000]low_entity,
	sim_arena:                     mem.Arena,
	sim_alloc:                     mem.Allocator,
	Max_Sim_Ent:                   u32,
	controllers:                   [5]controll,
}

controll :: struct {
	EntIndex: u32,
	ddP:      Vector2,
	aButton:  bool,
}

Map :: struct {
	countx:   i32,
	county:   i32,
	MapWidth: i32,
	Tilemap:  [^]i32,
}

game_button_state :: struct {
	HalfTransitionCount: int,
	EndedDown:           bool,
}


game_pad :: struct {
	Up:        game_button_state,
	Down:      game_button_state,
	Left:      game_button_state,
	Right:     game_button_state,
	Action1:   game_button_state,
	Action2:   game_button_state,
	Action3:   game_button_state,
	Action4:   game_button_state,
	LShoulder: game_button_state,
	RShoulder: game_button_state,
	Start:     game_button_state,
}

//TODO I should change this...
Buttons :: union {
	[9]game_button_state,
	game_pad,
}

game_controller_input :: struct {
	isConnected: bool,
	IsAnalgo:    bool,
	StickFramex: f32,
	StickFramey: f32,
	gamepad:     game_pad,
	padButtons:  union {
		[9]game_button_state,
		game_pad,
	},
}

game_input :: struct {
	MouseButton: [2]game_button_state,
	MouseX:      f32,
	MouseY:      f32,
	Controllers: [5]game_controller_input,
	dtForFrame:  f32,
}

game_offscreen_buffer :: struct {
	memory:               rawptr,
	Height, Width, Pitch: i32,
}


DrawRect :: proc(
	Buffer: ^game_offscreen_buffer,
	fminX: f32,
	fminY: f32,
	fmaxX: f32,
	fmaxY: f32,
	R: f32,
	G: f32,
	B: f32,
) {
	minX: i32 = i32(math.round_f32(fminX))
	maxX: i32 = i32(math.round_f32(fmaxX))
	minY: i32 = i32(math.round_f32(fminY))
	maxY: i32 = i32(math.round_f32(fmaxY))

	if minX < 0 {
		minX = 0
	}; if minY < 0 {
		maxY = maxY + minY
		minY = 0
	}; if maxX > Buffer.Width {
		maxX = Buffer.Width
	}; if maxY > Buffer.Height {
		maxY = Buffer.Height
	}

	Blue := math.round_f32(255 * B)
	Green := math.round_f32(255 * G)
	Red := math.round_f32(255 * R)
	final: u32 = (cast(u32)Red) << 16 | (cast(u32)Green) << 8 | cast(u32)Blue


	Color: u32 = 0xffff00ff

	Rowz: [^]u8 = cast([^]u8)Buffer.memory
	Pitch := Buffer.Pitch
	for y: i32 = minY; y < maxY; y += 1 {
		Pixel: [^]u32 = cast([^]u32)Rowz
		for x: i32 = minX; x < maxX; x += 1 {
			Pixel[(y * Pitch) + x] = final
		}
	}

}

loadBMP :: proc(filename: string) -> ([]u8, ^bmp) {

	file_handle, error := os.open(filename)
	if error == nil {
		file_size, _ := os.file_size(file_handle)
		file_data, file_ok := os.read_entire_file_from_filename(
			filename,
			GameMemory.PermanentStorageAlloc,
		) //os.read_entire_file_from_handle(file_handle)

		if file_ok {

			os.close(file_handle)

		} else {
			//TODO this might be necessary assert(1==0)
			panic("FILE NOTE FOUND CRASHING")
		}
		bmap := new(bmp, GameMemory.PermanentStorageAlloc)
		bmap.FileType = endian.unchecked_get_u16be(file_data[0:2]) //u16(test[0]) // << 8 + u16(test[1])
		bmap.FileSize = endian.unchecked_get_u32le(file_data[2:6])
		bmap.Offset = endian.unchecked_get_u32le(file_data[10:14])
		bmap.width, _ = endian.get_i32(file_data[18:22], .Little)
		bmap.height, _ = endian.get_i32(file_data[22:26], .Little)
		bmap.bpp = endian.unchecked_get_u16le(file_data[28:30])


		//, bitmapHeader.Offset)
		source := file_data[bmap.Offset:]
		sourceL := len(source)

		bmpdata := make([]u8, sourceL, GameMemory.PermanentStorageAlloc)
		copy_slice(bmpdata, source)
		//bmpdata = file_data[bmap.Offset:]
		bmpdPtr := new([]u8, GameMemory.PermanentStorageAlloc)
		bmpdPtr = &bmpdata

		//bmpdata^ = tmp
		fmt.println("len bmpData:", len(bmpdata), "len ptr deref: ", len(bmpdPtr^))
		return bmpdata, bmap


	} else {
		fmt.println("Couldn't Load File")}
	return nil, nil

}


RenderBmp :: proc(
	img: ^bmp,
	imgData: []u8,
	Buffer: ^game_offscreen_buffer,
	world: ^World,
	Left1: i32,
	Top: i32,
	Width: i32,
	Height: i32,
	StartX: i32,
	StartY: i32,
	entIndex: int,
) {

	Left := Left1
	if Left > Buffer.Width {
		Left = Buffer.Width
	}
	Rowz: [^]u8 = cast([^]u8)Buffer.memory
	Pitch := Buffer.Pitch
	test := slice.reinterpret([]u32, imgData)
	Bottom := Top + Height
	Right := Left + Width


	if Top >= 0 && Bottom <= Buffer.Height {
		for y: i32 = 0; y < Bottom - Top; y += 1 { 	//img.height; y += 1 {
			Pixel: [^]u32 = cast([^]u32)Rowz
			for x: i32 = 0; x < Right - Left; x += 1 { 	//img.width; x += 1 {
				//TODO FIX FOR GOING LEFT!!!!!!
				temp := test[(y + StartY) * img.width + x + StartX]
				destT := Pixel[((i32(Bottom) - y) * Pitch) + x + i32(Left)]
				sB := f32(temp & 0xFF)
				sG := f32((temp >> 8) & 0xFF)
				sR := f32((temp >> 16) & 0xFF)

				dB := f32(destT & 0xFF)
				dG := f32((destT >> 8) & 0xFF)
				dR := f32((destT >> 16) & 0xFF)

				sA := f32(((temp >> 24) & 0xFF)) / 255.0
				fB := sB //(1 - sA) * dB + sA * sB
				fG := sG //(1 - sA) * dG + sA * sG
				fR := sR //(1 - sA) * dR + sA * sR

				//fmt.println(sA, "Sa")
				//final: u32 = (cast(u32)fR) << 24 | (cast(u32)fG) << 16 | cast(u32)fB << 8


				if !GameState.high_entities[entIndex].Left {
					//	if test[(y + StartY) * img.width + x + StartX] >> 24 > 128 {


					if test[(y + StartY) * img.width + x + StartX] >> 24 > 128 {
						Pixel[((i32(Bottom) - y) * Pitch) + Left + x] =
							test[(y + StartY) * img.width + x + StartX]
					}
				} else {

					if test[(y + StartY) * img.width + x + StartX] >> 24 > 128 {
						Pixel[((i32(Bottom) - y) * Pitch) + Right - x] =
							test[(y + StartY) * img.width + x + StartX]
					}
				}

			}
		}
	} else {
		fmt.println("Not rendering")
	}


}


RenderBckgrnd :: proc(
	img: ^bmp,
	imgData: []u8,
	Buffer: ^game_offscreen_buffer,
	world: ^World,
	GameState: ^game_state,
) {

	Left := i32(world.Upperleftstartx)
	Top := i32(world.Upperleftstarty)
	Rowz: [^]u8 = cast([^]u8)Buffer.memory
	Pitch := Buffer.Pitch
	test := slice.reinterpret([]u32, imgData)

	for y: i32 = 0; y < img.height; y += 1 {
		Pixel: [^]u32 = cast([^]u32)Rowz
		for x: i32 = 0; x < img.width; x += 1 {
			Pixel[((i32(world.LowerLeftStartY) - y) * Pitch) + x + i32(world.Upperleftstartx)] =
				test[y * img.width + x] //& 0x004F4F4F
		}
	}


}


RenderPlayer :: proc(Buffer: ^game_offscreen_buffer, PlayerX: i32, PlayerY: i32) {
	SpriteW: i32 = 10
	Color: u32 = 0xFFFFFFFF
	Left: i32 = PlayerX
	Right: i32 = Left + SpriteW
	Top := PlayerY
	Bottom: i32 = Top + SpriteW
	Rowz: [^]u8 = cast([^]u8)Buffer.memory
	Pitch := Buffer.Pitch
	if Top >= 0 && Top + SpriteW < Buffer.Height {
		for y: i32 = Top; y <= Bottom + 1; y += 1 {
			Pixel: [^]u32 = cast([^]u32)Rowz
			for x: i32 = Left; x <= Right; x += 1 {
				Pixel[(y * Pitch) + x] = Color
			}
		}
	}
}

RenderWeirdGradient :: proc(Buffer: ^game_offscreen_buffer, GameState: ^game_state) {

	/*
Rowz: [^]u8 = cast([^]u8)Buffer.memory
//Rowz:^u8 = cast(^u8)Bitmapmemory
Pitch := Buffer.Pitch
//Pitch:=4*width
for y: i32 = 0; y < Buffer.Height; y += 1 {
    Pixel: [^]u32 = cast([^]u32)Rowz
    for x: i32 = 0; x < Buffer.Width; x += 1 {
        Blue := u8(GameState.Blue) * cast(u8)(x + GameState.offsetX)
        Green := u8(GameState.Green) * cast(u8)(y + GameState.offsetY)

        Red: u8 = u8(GameState.Red) * cast(u8)(y + GameState.offsetY)
        // (cast(u32)Red<<8|
        final: u32 = (cast(u32)Red) << 16 | (cast(u32)Green) << 8 | cast(u32)Blue
        Pixel[(y * Pitch) + x] = final
    }
    //    Rowz = mem.ptr_offset(Rowz,Pitch)
}
*/
}

game_output_sound_buffer :: struct {
	SamplesPerSecond: u32,
	SampleCount:      u32,
	SampleOut:        [^]i32,
	ToneHz:           u32,
}

GameOutputSound :: proc(SoundBuffer: ^game_output_sound_buffer, ToneHz: u32) {
	if !debug_mode {
		Soundlevel: i16 = 600
		SquareWavePeriod: u32 = 48000 / ToneHz
		for SampleIndex: u32 = 0; SampleIndex < SoundBuffer.SampleCount; SampleIndex += 1 {
			SampleValue: i16 =
				((u32(SampleIndex) / cast(u32)SquareWavePeriod / 2) % 2) == 0 ? Soundlevel : -1 * Soundlevel
			temp := cast(i32)SampleValue
			temp = temp << 16
			temp2 := i32(i32(SampleValue) & 0b00000000000000001111111111111111)
			final := temp | temp2
			SoundBuffer.SampleOut[SampleIndex] = final
		}
	}
}

HandleInput :: proc(
	GameState: ^game_state,
	index: int,
	Input1: ^game_controller_input,
	Height: i32,
	Width: i32,
	dtForFrame: f32,
	world: ^World,
	entIndex: u32,
) {
	controll := &GameState.controllers[index]

	if Input1.isConnected {
		if (Input1.IsAnalgo) {
		} else {
		}
		//This is the digital part of the analog stick... can handle a bunch of ways

		ddPlayer: Vector2
		ddPlayer.x = 0
		ddPlayer.y = 0
		controll.ddP = {0, 0}


		switch buttons in Input1.padButtons {
		case game_pad:
			if buttons.Down.EndedDown {
				controll.ddP.y = -1.0
			}
			if buttons.Left.EndedDown {

				controll.ddP.x = -1.0

			} else {

				//GameState.Player_Position.moving = false
			}
			if buttons.Up.EndedDown {

				controll.ddP.y = 1.0
			}
			if buttons.Right.EndedDown {
				controll.ddP.x = 1.0


			} else {

				//GameState.Player_Position.moving = false
			}
			if math.abs(controll.ddP.y) == math.abs(controll.ddP.x) {
				controll.ddP *= .70710678118
			}

			if buttons.Action1.EndedDown {
				fmt.println("Speed")
				controll.aButton = true

			}

			when (TURNOFF) {
				if buttons.Action2.EndedDown {
					fmt.println("end speed")

					GameState.Speed = 0
				}
				//push please

				if buttons.Action3.EndedDown {
					fmt.println("Action3")
				}

				if buttons.Action4.EndedDown {
					fmt.println("Action4")
				}}
		case [9]game_button_state:
			if buttons[0].EndedDown {
			}

		}
		when (TURNOFF) {
			ddPlayer *= 60.0 //m/s^2
			if (GameState.Speed == 1) {
				ddPlayer *= 5
				ddPlayer *= 5
			}

			ddPlayer += -10 * GameState.dPlayer

			PlayerDelta := dtForFrame * Entity.high.dPos + .5 * ddPlayer * dtForFrame * dtForFrame
			NewPlayer := Entity.dormant.Stored.position.TileOffSet + PlayerDelta

			Entity.high.dPos = ddPlayer * dtForFrame + GameState.dPlayer

			P1 := Entity.dormant.Stored.position //GameState.Player_Position
			P1.TileOffSet.x = NewPlayer.x
			P1.TileOffSet.y = NewPlayer.y
			Recon_Position(&P1, world)

			when (TURNOFF) {
				minSearchY: u32 = Min(
					P1.AbsTileY,
					GameState.low_entities[entIndex].position.AbsTileY,
				)
				minSearchX: u32 = Min(
					P1.AbsTileX,
					GameState.low_entities[entIndex].position.AbsTileX,
				)
				maxSearchY: u32 = Max(
					P1.AbsTileY,
					GameState.low_entities[entIndex].position.AbsTileY,
				)
				maxSearchX: u32 = Max(
					P1.AbsTileX,
					GameState.low_entities[entIndex].position.AbsTileX,
				)


				WidthTile: u32 = u32(math.ceil(world.PlayerW / world.TileSideM))
				HeightTile: u32 = u32(math.ceil(world.PlayerH / world.TileSideM))
				if minSearchX > 0 {
					minSearchX -= WidthTile

				}
				maxSearchX += WidthTile

				maxSearchY += HeightTile
			}


			tLowest: f32 = 1
			r: Vector2 = {0, 0}

			for Eindex: u32 = 0; Eindex <= GameState.entityCount; Eindex += 1 {
				/*for minY: u32 = minSearchY; minY <= maxSearchY; minY += 1 {
			//for minX: u32 = minSearchX; minX <= maxSearchX; minX += 1 {
			TestP: global_position
			TestP.AbsTileX = minX
			TestP.AbsTileY = minY
			TestP.TileOffSet = {0, 0}*/
				if Eindex == entIndex {
					continue
				}
				TestEntity := getEntity(GameState, Eindex)


				Diam: Vector2
				Diam.x = TestEntity.dormant.Stored.width + Entity.dormant.Stored.width
				Diam.y = TestEntity.dormant.Stored.height + Entity.dormant.Stored.height
				minCorner: Vector2 = Vector2{-.5 * Diam.x, -1 * TestEntity.dormant.Stored.height}
				maxCorner: Vector2 = 1 * Vector2 {
							TestEntity.dormant.Stored.width + .5 * Diam.x,
							TestEntity.dormant.Stored.height - world.oneMinPH * TestEntity.dormant.Stored.height, //(.75 * world.TileSideM),
						} // + Diam
				dist := SubTile(world, &TestEntity.dormant.Stored.position, &oldPlayerP)

				//					fmt.println("Distance: ", dist.x, dist.y, "Dir:", PlayerDelta.x, PlayerDelta.y)

				if (math.sign(dist.x) != math.sign(PlayerDelta.x) && math.abs(PlayerDelta.x) > 0) {
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
					}

				}
				if (math.sign(dist.x) != math.sign(PlayerDelta.x) && math.abs(PlayerDelta.x) > 0) {
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

					}
				}

				if (math.sign(dist.y) != math.sign(PlayerDelta.y) && math.abs(PlayerDelta.y) > 0) {
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
					}
				}

				if (math.sign(dist.y) != math.sign(PlayerDelta.y) && math.abs(PlayerDelta.y) > 0) {
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
			if tLowest != 1 {

				tEpsilon: f32 = .8

				GameState.low_entities[entIndex].Stored.position.TileOffSet +=
					tEpsilon * tLowest * PlayerDelta
				GameState.low_entities[entIndex].Stored.dP =
					GameState.low_entities[entIndex].Stored.dP -
					1 * dot(GameState.low_entities[entIndex].Stored.dP, r) * r

				GameState.low_entities[entIndex].Stored.position.TileOffSet +=
					(1 - tEpsilon * tLowest) * PlayerDelta -
					1 * dot((1 - tEpsilon * tLowest) * PlayerDelta, r) * r
			} else {
				GameState.low_entities[entIndex].Stored.position.TileOffSet +=
					.9 * tLowest * PlayerDelta

			}


			Recon_Position(&GameState.low_entities[entIndex].Stored.position, world)
		}
	}
}


@(export)
game_hot_reloaded :: proc(mem: ^game_memory) {
	Game_Mem = mem
}
@(export)
game_init :: proc(PSs: u64, PS: rawptr, TSS: u64, TS: rawptr, PS_Alloc: ^mem.Allocator) {
	Game_Mem = new(game_memory)
	Game_Mem.Permanentstoragesize = PSs
	Game_Mem.PermanentStorage = PS

	Game_Mem.Transientstoragesize = TSS
	Game_Mem.Transientstorage = TS
	Game_Mem.PermanentStorageAlloc = PS_Alloc^
}
@(export)
game_sd :: proc() {
	free(Game_Mem)
}
@(export)
game_mem_ptr :: proc() -> rawptr {
	return Game_Mem
}
@(export)
game_GameGetSoundSamples :: proc(
	Thread: ^thread_context,
	Memory: ^game_memory,
	SoundBuffer: ^game_output_sound_buffer,
) -> bool {
	GameState: ^game_state = cast(^game_state)Memory.PermanentStorage
	//GameOutputSound(SoundBuffer, GameState.ToneHz)
	return true
}

mem_arena :: struct {
	data: [^]u8,
	size: u64,
	used: u64,
}
initialize_arena :: proc(arena: ^mem_arena, size: u64, base: rawptr) {

	arena.size = size
	arena.data = cast([^]u8)base
	arena.used = 0
}


@(export)
game_GameUpdateAndRender :: proc(
	Thread: ^thread_context,
	Memory: ^game_memory,
	Input: ^game_input,
	Buffer: ^game_offscreen_buffer,
) -> bool {
	//TODO Possibly implement the game to be told where in time to put sound
	Input0: ^game_controller_input = &Input.Controllers[0]
	Input1: ^game_controller_input = &Input.Controllers[1]
	file_name := "/home/xorbot/CLionProjects/SDL_Odin_Hero/src/forest.bmp"
	//file_name := "src/lol.txt"
	file_name_w := "src/test1.txt"


	if !Memory.isInit {
		//TODO This should almost certainly just be 1 multipointer but have to cross that bridge later
		fmt.println("Initting Mem!")
		Memory.isInit = true
		//	data, bmap =

		GameState = new(game_state, Memory.PermanentStorageAlloc) //cast(^game_state)Memory.PermanentStorage


		GameState.world = new(World, Memory.PermanentStorageAlloc) //DeleteFileData(Bitmapdata, Bitmapmemory)
		GameState.world.TileSideM = 1.4
		GameState.world.TileSidePixels = 70.0
		GameState.world.Upperleftstarty = 5.0
		GameState.world.Upperleftstartx = 5.0
		GameState.world.LowerLeftStartX = 5.0
		GameState.world.LowerLeftStartY = 635.0

		GameState.world.MetersToPixels = GameState.world.TileSidePixels / 1.4
		GameState.world.ChunkShift = 5
		GameState.world.ChunkDim = 32
		GameState.world.ChunkSideM.x = f32(GameState.world.ChunkDim) * GameState.world.TileSideM
		GameState.world.ChunkSideM.y = f32(GameState.world.ChunkDim) * GameState.world.TileSideM
		GameState.world.ChunkX = 300
		GameState.world.ChunkY = 300


		//GameState.world.worldchunks = new([4096]world_chunk)^
		EI := addEntity(GameState)
		GameState.Player_low_index = 0
		GameState.low_entities[EI].Stored.type = .HERO
		GameState.low_entities[EI].chunk_position.ChunkX = 5
		GameState.low_entities[EI].chunk_position.ChunkY = 1
		GameState.low_entities[EI].chunk_position.ChunkZ = 0
		GameState.low_entities[EI].chunk_position.Offset = {
			15 * GameState.world.TileSideM,
			15 * GameState.world.TileSideM,
		}
		GameState.Camera_Following_Entity_Index = EI
		GameState.world.camera_pos = GameState.low_entities[EI].chunk_position

		GameState.low_entities[EI].Stored.width = .75 * GameState.world.TileSideM
		GameState.low_entities[EI].Stored.height = .33 * GameState.world.TileSideM
		GameState.low_entities[EI].Stored.attributes += {.COLLIDES}
		ChangeEntityLocation(
			GameState,
			GameState.world,
			0,
			nil,
			&GameState.low_entities[EI].chunk_position,
		)
		addWall(GameState, 5, 1, 0, 12, 15)
		addWall(GameState, 5, 1, 0, 12, 16)
		addWall(GameState, 5, 1, 0, 13, 15)

		when (TURNOFF) {


			E.dormant.position.AbsTileX = 166
			E.dormant.position.AbsTileY = 36
			E.dormant.type = .HERO
			E.dormant.collides = true
			E.high.width = .75 * world.TileSideM
			E.high.height = .33 * world.TileSideM
			addEntity(E)
		}
		fmt.println("Initting Mem!")

		GameState.world.LowerLeftStartY = f32(windowSizey) * GameState.world.TileSidePixels
		when (TURNOFF) {
			GameState.world.Window_Pos.AbsTileY = 32
			GameState.world.Window_Pos.AbsTileX = 160
			GameState.world.Window_Pos.AbsTileZ = 0

			fmt.println(
				"Orig WP",
				GameState.world.Window_Pos.AbsTileX,
				GameState.world.Window_Pos.AbsTileY,
			)
			temp := To_Chunk_Pos(&GameState.Player_Position, GameState.world)
			GameState.world.camera_pos = temp


			//		GameState.world.chunks = make(
			//			[^]^Map,
			//			u64(GameState.world.ChunkX * GameState.world.ChunkY * size_of(^Map)),
			//			Memory.PermanentStorageAlloc,
			//		)
			Get_Chunk(GameState.world, u32(temp.ChunkX), u32(temp.ChunkY), u32(temp.ChunkZ), true)

		}
		GameState.backGroundData, GameState.backGroundBmap = loadBMP(file_name)


		file_name = "/home/xorbot/CLionProjects/SDL_Odin_Hero/src/Run.bmp"
		GameState.playerData, GameState.playerBmap = loadBMP(file_name)
		fmt.println(
			"bgdata size: ",
			len(GameState.backGroundData),
			"pdSize: ",
			len(GameState.playerData),
		)
		GameState.Max_Sim_Ent = 4096

		sim_buffer := make([]byte, GameState.Max_Sim_Ent * size_of(sim_entitiy) + 1024)
		mem.arena_init(&GameState.sim_arena, sim_buffer)
		GameState.sim_alloc = mem.arena_allocator(&GameState.sim_arena)
		GameState.controllers[0].EntIndex = 0

	}

	for &controller, index in Input.Controllers {
		HandleInput(
			GameState,
			index,
			&controller,
			Buffer.Height,
			Buffer.Width,
			Input.dtForFrame,
			GameState.world,
			0,
		)
	}

	//			fmt.println("Entity: ", index)
	PlayerR: f32 = .5
	PlayerG: f32 = .5
	PlayerB: f32 = 0.5
	PlayerW: f32 = GameState.low_entities[GameState.Player_low_index].Stored.width

	PlayerH: f32 = GameState.low_entities[GameState.Player_low_index].Stored.height
	PlayerRenderH := GameState.world.TileSideM

	GameState.world.PlayerH = PlayerH
	GameState.world.PlayerW = PlayerW
	GameState.world.oneMinPH = 1 - PlayerH / GameState.world.TileSideM

	//SIM REGION START

	MSpanX: f32 = 5 * GameState.world.TileSideM
	MSpanY: f32 = 5 * GameState.world.TileSideM
	ScreenCenterX := .5 * f32(Buffer.Width)
	ScreenCenterY := .5 * f32(Buffer.Height)

	CameraB := RectCenterDim({0, 0}, {MSpanX, MSpanY})
	SimRegion := BeginSim(
		&GameState.sim_alloc,
		GameState.world,
		GameState.world.camera_pos,
		CameraB,
	)

	//TODO FIX
	RenderBckgrnd(
		GameState.backGroundBmap,
		GameState.backGroundData,
		Buffer,
		GameState.world,
		GameState,
	)
	when (TURNOFF) {
		Temp_Pos := GameState.world.Window_Pos
		tt := To_Chunk_Pos(&Temp_Pos, GameState.world)
		//	fmt.println("Current Chunk: ", tt.ChunkX, tt.ChunkY)
	}
	GameState.count += 1
	if GameState.count >= 32 {
		GameState.count = 0
	}


	for &ent, index in SimRegion.Entities {
		if u32(index) == SimRegion.Entity_Count {
			break
		}
		curEnt := GameState.low_entities[ent.StorageIndex]
		dt := Input.dtForFrame

		if ent.type != .HERO {
			color: f32 = 1.0
			/*minX :=
				f32(curEnt.Stored.position.AbsTileX - Temp_Pos.AbsTileX) *
					GameState.world.TileSidePixels +
				GameState.world.Upperleftstartx
			minY :=
				GameState.world.LowerLeftStartY -
				f32(curEnt.Stored.position.AbsTileY - Temp_Pos.AbsTileY + 1) *
					GameState.world.TileSidePixels +
				GameState.world.Upperleftstarty*/
			minX := ScreenCenterX + ent.Pos.x * GameState.world.MetersToPixels
			minY := ScreenCenterY - ent.Pos.y * GameState.world.MetersToPixels

			maxX := minX + GameState.world.MetersToPixels
			maxY := minY + GameState.world.MetersToPixels


			DrawRect(Buffer, minX, minY, maxX, maxY, color, color, color)
		}; if ent.type == .HERO || ent.type != .HERO {
			ddP: Vector2

			for controller in GameState.controllers {
				if controller.EntIndex == ent.StorageIndex {

					ddP = controller.ddP
					break
				}
			}
			fmt.println("ddp: ", ddP.x, ddP.y)
			MoveEntity(SimRegion, &ent, dt, ddP)
			dorm := GameState.low_entities[GameState.Player_low_index]


			PlayerL :=
				ScreenCenterX +
				ent.Pos.x /*f32 =
				f32(
					f32(dorm.Stored.position.AbsTileX - GameState.world.Window_Pos.AbsTileX) *
					GameState.world.TileSidePixels,
				) -
				.5 * (GameState.world.MetersToPixels * PlayerW) +
				GameState.world.MetersToPixels * dorm.Stored.position.TileOffSet.x*/


			/*BMPT: f32 =
				GameState.world.LowerLeftStartY -
				(f32(dorm.Stored.position.AbsTileY - GameState.world.Window_Pos.AbsTileY + 1) +
						.7) *
					GameState.world.TileSidePixels -
				GameState.world.MetersToPixels * dorm.Stored.position.TileOffSet.y*/
			PlayerT :=
				ScreenCenterY -
				ent.Pos.y /*f32 =
				GameState.world.LowerLeftStartY -
				f32(dorm.Stored.position.AbsTileY - GameState.world.Window_Pos.AbsTileY + 1) *
					GameState.world.TileSidePixels -
				GameState.world.MetersToPixels * dorm.Stored.position.TileOffSet.y*/


			DrawRect(
				Buffer,
				PlayerL,
				PlayerT,
				PlayerL + PlayerW * GameState.world.MetersToPixels,
				PlayerT + GameState.world.TileSideM * GameState.world.MetersToPixels, //(PlayerH + (1 - PlayerH)) * GameState.world.MetersToPixels,
				PlayerR,
				PlayerG,
				PlayerB,
			)
			x: i32 = 64
			if (ent.moving) {
				x = 64 + (i32(GameState.count) / 4) * 200
			}


			/*RenderBmp(
				GameState.playerBmap,
				GameState.playerData,
				Buffer,
				GameState.world,
				i32(math.round_f32(PlayerL)),
				i32(math.round_f32(BMPT)),
				i32(math.round_f32(PlayerW * GameState.world.MetersToPixels) + 20),
				i32(math.round_f32(GameState.world.MetersToPixels)) + 60,
				x,
				31,
				int(GameState.Player_low_index),
			)*/

		}
	}

	EndSim(&GameState.sim_alloc, SimRegion, GameState)
	GameState.world.camera_pos = GameState.low_entities[0].chunk_position


	return true

}
