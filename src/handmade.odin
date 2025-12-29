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
	world: ^World,
	LowEntityIndex: u32,
	OldP, NewP: ^world_chunk_position,
) {
	if OldP != nil && AreInSameChunk(OldP, NewP) {
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
	ENEMY,
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
low_entity :: struct {
	position:         global_position,
	collides:         bool,
	type:             entity_type,
	width:            f32,
	height:           f32,
	HightEntityIndex: u32,
}


getEntity :: proc(GameState: ^game_state, index: u32) -> entity {
	e: entity
	e.dormant = &GameState.low_entities[index]
	e.high = &GameState.high_entities[index] //nil
	return e
}
addWall :: proc(GameState: ^game_state, AbsTileX, AbsTileY, AbsTileZ: u32) -> u32 {
	EI := addEntity(GameState)
	GameState.low_entities[EI].position.AbsTileX = AbsTileX
	GameState.low_entities[EI].position.AbsTileY = AbsTileY
	GameState.low_entities[EI].position.AbsTileZ = AbsTileZ
	GameState.low_entities[EI].height = GameState.world.TileSideM
	GameState.low_entities[EI].width = GameState.low_entities[EI].height
	GameState.low_entities[EI].collides = true
	return EI


}
addEntity :: proc(GameState: ^game_state) -> u32 {
	assert(GameState.entityCount < len(GameState.entity_residence) - 1)
	eC := GameState.entityCount
	GameState.entity_residence[GameState.entityCount] = .DORMANT
	GameState.high_entities[GameState.entityCount] = {}
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
			cur_Chunk = Alloc_Chunk_C(world, ChunkX, ChunkY, ChunkZ)
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
) -> world_chunk {
	res: world_chunk
	res.ChunkX = Player_Position.AbsTileX >> world.ChunkShift
	res.ChunkY = Player_Position.AbsTileY >> world.ChunkShift
	res.ChunkZ = 0
	res.TileX = Player_Position.AbsTileX & 0x1F
	res.TileY = Player_Position.AbsTileY & 0x1F
	return res

}

UpdateWorldPos :: #force_inline proc(world: ^World) {

	if GameState.low_entities[0].position.AbsTileY > world.Window_Pos.AbsTileY &&
	   GameState.low_entities[0].position.AbsTileY - world.Window_Pos.AbsTileY >= windowSizey {
		world.Window_Pos.AbsTileY += windowSizey
		world.camera_pos.Y += 1
	} else if i32(GameState.low_entities[0].position.AbsTileY) - i32(world.Window_Pos.AbsTileY) <
	   0 {
		world.Window_Pos.AbsTileY -= windowSizey
		world.camera_pos.Y -= 1
	}
	if GameState.low_entities[0].position.AbsTileX > world.Window_Pos.AbsTileX &&
	   GameState.low_entities[0].position.AbsTileX - world.Window_Pos.AbsTileX >= windowSizex {
		world.Window_Pos.AbsTileX += windowSizex

		world.camera_pos.X += 1

		fmt.println("I'M HERE WINDOWPOSX", world.Window_Pos.AbsTileX)
	} else if i32(GameState.low_entities[0].position.AbsTileX) - i32(world.Window_Pos.AbsTileX) <
	   0 {

		fmt.println("I'M HERE WINDOWPOSX", world.Window_Pos.AbsTileX)
		world.Window_Pos.AbsTileX -= windowSizex

		world.camera_pos.X -= 1
	}


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
	world:            ^World,
	arena:            mem_arena,
	Player_Position:  global_position,
	backGroundData:   []u8,
	backGroundBmap:   ^bmp,
	playerBmap:       ^bmp,
	playerData:       []u8,
	count:            u64,
	Speed:            uint,
	dPlayer:          Vector2, //TODO MOVE TO hf_entity
	entityCount:      u32,
	entity_residence: [256]entity_res,
	high_entities:    [256]hf_entity,
	low_entities:     [10000]low_entity,
}

window_group :: struct {
	X: u32,
	Y: u32,
	Z: u32,
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
	Input1: ^game_controller_input,
	Height: i32,
	Width: i32,
	dtForFrame: f32,
	world: ^World,
	entIndex: u32,
) {
	Entity := getEntity(GameState, entIndex)
	oldPlayerP := Entity.dormant.position //GameState.Player_Position
	if Input1.isConnected {
		if (Input1.IsAnalgo) {
		} else {
		}
		//This is the digital part of the analog stick... can handle a bunch of ways

		ddPlayer: Vector2


		switch buttons in Input1.padButtons {
		case game_pad:
			if buttons.Down.EndedDown {
				ddPlayer.y = -1.0
			}
			if buttons.Left.EndedDown {
				ddPlayer.x = -1.0
				Entity.high.Left = true
				Entity.high.Right = false
				Entity.high.moving = true

			} else {

				//GameState.Player_Position.moving = false
			}
			if buttons.Up.EndedDown {

				ddPlayer.y = 1.0
			}
			if buttons.Right.EndedDown {

				ddPlayer.x = 1.0
				Entity.high.Right = true
				Entity.high.Left = false

				Entity.high.moving = true

			} else {

				//GameState.Player_Position.moving = false
			}
			if math.abs(ddPlayer.y) == math.abs(ddPlayer.x) {
				ddPlayer *= .70710678118
			}
			if !(buttons.Right.EndedDown || buttons.Left.EndedDown) {
				Entity.high.moving = false
			}
			if buttons.Action1.EndedDown {
				fmt.println("Speed")
				GameState.Speed = 1

			}

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
			}
		case [9]game_button_state:
			if buttons[0].EndedDown {
			}

		}
		ddPlayer *= 60.0 //m/s^2
		if (GameState.Speed == 1) {
			ddPlayer *= 5
			ddPlayer *= 5
		}

		ddPlayer += -10 * GameState.dPlayer

		PlayerDelta := dtForFrame * Entity.high.dPos + .5 * ddPlayer * dtForFrame * dtForFrame
		NewPlayer := Entity.dormant.position.TileOffSet + PlayerDelta

		Entity.high.dPos = ddPlayer * dtForFrame + GameState.dPlayer

		P1 := Entity.dormant.position //GameState.Player_Position
		P1.TileOffSet.x = NewPlayer.x
		P1.TileOffSet.y = NewPlayer.y
		Recon_Position(&P1, world)

		when (TURNOFF) {
			minSearchY: u32 = Min(P1.AbsTileY, GameState.low_entities[entIndex].position.AbsTileY)
			minSearchX: u32 = Min(P1.AbsTileX, GameState.low_entities[entIndex].position.AbsTileX)
			maxSearchY: u32 = Max(P1.AbsTileY, GameState.low_entities[entIndex].position.AbsTileY)
			maxSearchX: u32 = Max(P1.AbsTileX, GameState.low_entities[entIndex].position.AbsTileX)


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
			Diam.x = TestEntity.dormant.width + Entity.dormant.width
			Diam.y = TestEntity.dormant.height + Entity.dormant.height
			minCorner: Vector2 = Vector2{-.5 * Diam.x, -1 * TestEntity.dormant.height}
			maxCorner: Vector2 = 1 * Vector2 {
						TestEntity.dormant.width + .5 * Diam.x,
						TestEntity.dormant.height - world.oneMinPH * TestEntity.dormant.height, //(.75 * world.TileSideM),
					} // + Diam
			dist := SubTile(world, &TestEntity.dormant.position, &oldPlayerP)

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

			GameState.low_entities[entIndex].position.TileOffSet +=
				tEpsilon * tLowest * PlayerDelta
			GameState.high_entities[entIndex].dPos =
				GameState.high_entities[entIndex].dPos -
				1 * dot(GameState.high_entities[entIndex].dPos, r) * r

			GameState.low_entities[entIndex].position.TileOffSet +=
				(1 - tEpsilon * tLowest) * PlayerDelta -
				1 * dot((1 - tEpsilon * tLowest) * PlayerDelta, r) * r
		} else {
			GameState.low_entities[entIndex].position.TileOffSet += .9 * tLowest * PlayerDelta

		}


		Recon_Position(&GameState.low_entities[entIndex].position, world)
	}
}

when (TURNOFF) {
	IsWorldMapPointEmpty :: proc(
		tile_map: ^Tile_Map,
		world: ^World,
		Player_Pos: ^global_position,
	) -> bool {

		//if Player_Pos.TileMapX >= 0 && Player_Pos.TileMapY >= 0 {
		//	fmt.println("IWMPE: ", Player_Pos.AbsTileX, Player_Pos.AbsTileY)
		chunkp := To_Chunk_Pos(Player_Pos, world)
		map1 := Get_Chunk(tile_map, chunkp.ChunkX, chunkp.ChunkY, chunkp.ChunkZ, true) ///&world.maps[Player_Pos.TileMapY * i32(worldSizeX) + Player_Pos.TileMapX]


		return IsMapPointEmpty(world, map1, chunkp.TileX, chunkp.TileY)
	}

	IsMapPointEmpty :: proc(world: ^World, map1: ^tile_chunk, TestX: u32, TestY: u32) -> bool {
		PlayerTileX := TestX
		PlayerTileY := TestY


		if map1.Tiles[PlayerTileY * world.ChunkDim + PlayerTileX] != 1 {


			return true
		}


		return false

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
		GameState.world.ChunkX = 300
		GameState.world.ChunkY = 300

		for i in 0 ..< len(GameState.entity_residence) {
			GameState.entity_residence[i] = .DORMANT
		}

		GameState.Player_Position.AbsTileX = 166
		GameState.Player_Position.AbsTileY = 36
		E: entity
		E.residence = .HIGH


		addEntity(GameState)
		GameState.entity_residence[0] = .HIGH
		GameState.low_entities[0].position.AbsTileX = 166
		GameState.low_entities[0].position.AbsTileY = 36
		GameState.high_entities[0].width = .75 * GameState.world.TileSideM
		GameState.high_entities[0].height = .33 * GameState.world.TileSideM

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
		GameState.world.Window_Pos.AbsTileY = 32
		GameState.world.Window_Pos.AbsTileX = 160
		GameState.world.Window_Pos.AbsTileZ = 0
		fmt.println(
			"Orig WP",
			GameState.world.Window_Pos.AbsTileX,
			GameState.world.Window_Pos.AbsTileY,
		)
		temp := To_Chunk_Pos(&GameState.Player_Position, GameState.world)
		GameState.world.camera_pos.X = temp.ChunkX
		GameState.world.camera_pos.Y = temp.ChunkY
		GameState.world.camera_pos.Z = temp.ChunkZ

		GameState.world.worldchunks = new([4096]world_chunk)^
		//		GameState.world.chunks = make(
		//			[^]^Map,
		//			u64(GameState.world.ChunkX * GameState.world.ChunkY * size_of(^Map)),
		//			Memory.PermanentStorageAlloc,
		//		)
		Get_Chunk(GameState.world, temp.ChunkX, temp.ChunkY, temp.ChunkZ, true)

		GameState.backGroundData, GameState.backGroundBmap = loadBMP(file_name)


		file_name = "/home/xorbot/CLionProjects/SDL_Odin_Hero/src/Run.bmp"
		GameState.playerData, GameState.playerBmap = loadBMP(file_name)
		fmt.println(
			"bgdata size: ",
			len(GameState.backGroundData),
			"pdSize: ",
			len(GameState.playerData),
		)


	}

	when (TURNOFF) {
		for &controller in Input.Controllers {
			HandleInput(
				GameState,
				&controller,
				Buffer.Height,
				Buffer.Width,
				Input.dtForFrame,
				world,
				0,
			)
		}

	}
	//DrawRect(Buffer, 0, 0, f32(Buffer.Width), f32(Buffer.Height), 0, 0, 0)


	UpdateWorldPos(GameState.world)


	RenderBckgrnd(
		GameState.backGroundBmap,
		GameState.backGroundData,
		Buffer,
		GameState.world,
		GameState,
	)

	Temp_Pos := GameState.world.Window_Pos
	tt := To_Chunk_Pos(&Temp_Pos, GameState.world)
	//	fmt.println("Current Chunk: ", tt.ChunkX, tt.ChunkY)
	for eindex: u32 = 0; eindex <= GameState.entityCount; eindex += 1 {
		ent := getEntity(GameState, eindex)
		if ent.dormant.position.AbsTileX >= Temp_Pos.AbsTileX &&
		   ent.dormant.position.AbsTileY >= Temp_Pos.AbsTileY &&
		   ent.dormant.position.AbsTileX < Temp_Pos.AbsTileX + windowSizex &&
		   ent.dormant.position.AbsTileY <= Temp_Pos.AbsTileY + windowSizey {
			color: f32 = 1.0
			minX :=
				f32(ent.dormant.position.AbsTileX - Temp_Pos.AbsTileX) *
					GameState.world.TileSidePixels +
				GameState.world.Upperleftstartx
			minY :=
				GameState.world.LowerLeftStartY -
				f32(ent.dormant.position.AbsTileY - Temp_Pos.AbsTileY + 1) *
					GameState.world.TileSidePixels +
				GameState.world.Upperleftstarty

			maxX := minX + GameState.world.TileSidePixels
			maxY := minY + GameState.world.TileSidePixels

			DrawRect(Buffer, minX, minY, maxX, maxY, color, color, color)

		}

	}
	when (TURNOFF) {
		for i: u32 = 0; i < windowSizey; i += 1 {

			for j: u32 = 0; j < windowSizex; j += 1 {
				color: f32 = 1.0
				Temp_Pos.AbsTileX = world.Window_Pos.AbsTileX + j
				Temp_Pos.AbsTileY = world.Window_Pos.AbsTileY + i

				//			fmt.println("Temp Ps: ", Temp_Pos.AbsTileX, Temp_Pos.AbsTileY)
				current_chunk_pos := To_Chunk_Pos(&Temp_Pos, world)

				if Temp_Pos.AbsTileY == GameState.Player_Position.AbsTileY &&
				   Temp_Pos.AbsTileX == GameState.Player_Position.AbsTileX {
					//fmt.println("h Player")
					color = 0
				}


				when (TURNOFF) {
					Tileid := Get_Tile_Value(world, &current_chunk_pos) //tile_map[world.currenty][world.currentx].Tilemap[i * mapcountx + j]
				}

				Tileid := 0
				if Tileid == 1 {
					color = 1.0
					minX := f32(j) * world.TileSidePixels + world.Upperleftstartx
					minY :=
						world.LowerLeftStartY -
						f32(i + 1) * world.TileSidePixels +
						world.Upperleftstarty

					maxX := minX + world.TileSidePixels
					maxY := minY + world.TileSidePixels

					DrawRect(Buffer, minX, minY, maxX, maxY, color, color, color)


				}
			}
		}
	}
	GameState.count += 1
	if GameState.count >= 32 {
		GameState.count = 0
	}

	for ent, index in GameState.high_entities {
		if GameState.entity_residence[index] == .HIGH {
			for &controller in Input.Controllers {
				HandleInput(
					GameState,
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
			PlayerW: f32 = ent.width //GameState.world.hf_entity[index].width //.75 * GameState.world.TileSideM
			//.75 * tile_map[GameState.world.currenty][GameState.world.currentx].TileWidt
			PlayerH := ent.height //.33 * GameState.world.TileSideM
			PlayerRenderH := GameState.world.TileSideM

			GameState.world.PlayerH = PlayerH
			GameState.world.PlayerW = PlayerW
			GameState.world.oneMinPH = 1 - PlayerH / GameState.world.TileSideM
			dorm := GameState.low_entities[index]

			PlayerL: f32 =
				f32(
					f32(dorm.position.AbsTileX - GameState.world.Window_Pos.AbsTileX) *
					GameState.world.TileSidePixels,
				) -
				.5 * (GameState.world.MetersToPixels * PlayerW) +
				GameState.world.MetersToPixels * dorm.position.TileOffSet.x


			BMPT: f32 =
				GameState.world.LowerLeftStartY -
				(f32(dorm.position.AbsTileY - GameState.world.Window_Pos.AbsTileY + 1) + .7) *
					GameState.world.TileSidePixels -
				GameState.world.MetersToPixels * dorm.position.TileOffSet.y
			PlayerT: f32 =
				GameState.world.LowerLeftStartY -
				f32(dorm.position.AbsTileY - GameState.world.Window_Pos.AbsTileY + 1) *
					GameState.world.TileSidePixels -
				GameState.world.MetersToPixels * dorm.position.TileOffSet.y


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


			RenderBmp(
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
				index,
			)
		}
	}


	return true

}
