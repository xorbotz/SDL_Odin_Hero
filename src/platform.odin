package main

import "base:intrinsics"

import "base:runtime"
import libc "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import os "core:os/os2"
import "core:time"
import sdl "vendor:sdl3"

/*TODO
    Save Game Locations
    Hand on exe file
    Asset loading path
    Threading
    Raw input (Support for multiple keyboards...)
    Sleep and timeBegin (don't kill a pc battery)
    Clip Cursor
    Fullscreen
    WM_SetupCursor
    WM_Activeapp
    BlitSpeed improvements
    Hardware Accel (OpenGL/Direct3d...)
    GetKeyboardLayout (Other Keyboards)
*/
//TODO MAKE THESE NOT GLOBAL
running := true
Global_Back_Buffer := win32_offscreen_buffer{}
GameMemory: game_memory
win32Memory: win32_game_memory
PerfCounterFrequency: u64 //w.LARGE_INTEGER

SoundisValid: bool = false
//hotreloadcode
get_driver_names :: proc() -> (drivers: []cstring, count: i32) {
	count = sdl.GetNumRenderDrivers()
	drivers = make([]cstring, count)
	for d in 0 ..< count {
		drivers[d] = sdl.GetRenderDriver(d)
	}
	return
}

// Return first driver found in priority list or empty cstring
set_driver_by_priority :: proc(priority_list: []cstring) -> (driver: cstring) {
	fmt.println("HEY I'M HERE")
	driver_list, _ := get_driver_names()
	defer delete(driver_list)
	for priority in priority_list {
		for d in driver_list {

			fmt.println(d)
			if d == priority {
				return priority
			}
		}
	}
	return
}
game_api_version := 0
GameAPI :: struct {
	init:                proc(_: u64, _: rawptr, _: u64, _: rawptr, _: ^mem.Allocator),
	sd:                  proc(),
	mem_ptr:             proc() -> rawptr,
	GameGetSoundSamples: proc(_: rawptr, _: rawptr, _: rawptr) -> bool,
	GameUpdateAndRender: proc(_: rawptr, _: rawptr, _: rawptr, _: rawptr) -> bool,
	hot_reloaded:        proc(_: rawptr),
	lib:                 dynlib.Library,
	dll_time:            time.Time, //os.File_Time,
	api_version:         int,
}

load_game_api :: proc(api_version: int) -> (GameAPI, bool) {
	dll_time, dll_time_err := os.last_write_time_by_name("game.dll")
	if dll_time_err != os.ERROR_NONE {
		fmt.println("FETCHING DLL FAILED")
		return {}, false
	}

	dll_name := "game.dll" //fmt.tprintf("game_{0}.dll", api_version)
	copy_cmd := fmt.ctprintf("copy game.dll {0}", dll_name)
	/*if libc.system(copy_cmd) != 0 {
		fmt.println("FAILED TO COPY game.dll to {0}", dll_name)
		return {}, false
	}*/
	lib, lib_ok := dynlib.load_library(dll_name)
	if !lib_ok {
		fmt.println("FAILED TO LOAD GAME DLL")
		return {}, false
	}
	api: GameAPI
	_, ok := dynlib.initialize_symbols(&api, dll_name, "game_", "lib")
	if !ok {
		fmt.printfln("Failed initialize symbols: {0}", dynlib.last_error())
	}

	api.api_version = api_version
	api.dll_time._nsec = dll_time._nsec
	return api, true

}

unload_game_api :: proc(api: GameAPI) {
	if api.lib != nil {
		dynlib.unload_library(api.lib)
	}
	del_cmd := fmt.ctprintf("del game_{0}.dll", api.api_version)
	if libc.system(del_cmd) != 0 {
		fmt.println("FAILED TO REMOVE game_{0}.dll copy")
	}
}

win32GetWallClock :: #force_inline proc() -> u64 { 	//w.LARGE_INTEGER {
	Result: u64 //w.LARGE_INTEGER
	Result = sdl.GetPerformanceCounter()
	return Result
}
win32GetSecondsElapsed :: #force_inline proc(Start: u64, End: u64) -> f32 {
	return (f32(End - Start)) / f32(PerfCounterFrequency)

}

ReadEntireFile :: proc(filename: string) -> ([]u8, ^[]u8, i64) {

	file_handle, handle := os.open(filename)
	//file_data,file_ok:=os.read_entire_file_from_filename(filename,gameAlloc^)
	fmt.println("handle error: ", handle)
	if handle == nil {
		fmt.println("have handle")
		file_size, _ := os.file_size(file_handle)
		fmt.println("size: ", file_size)
		file_data, file_ok := os.read_entire_file_from_file(file_handle, context.allocator)
		file_ok_check := file_ok.(os.General_Error)
		if file_ok == os.General_Error.None {
			fileptr: ^[]u8 = new([]u8)
			fileptr = &file_data
			return file_data, fileptr, file_size
		} else {
			//TODO maybe free this memory? I have to figure that out.
		}
		os.close(file_handle)
		return nil, nil, -1

	} else {
		//TODO this might be necessary assert(1==0)
		panic("FILE NOTE FOUND CRASHING")
	}
}
DeleteFileData :: proc(file_data: []u8, fileptr: ^[]u8) {
	delete(file_data)
	free(fileptr)
}
PlatformWriteEntireFile :: proc(file_name: string, Memory: []u8, Memsize: int) {
	Name: [^]u8
	Name = raw_data(file_name)
	Name2 := cast([^]u16)Name
	//FileHandle:=w.CreateFileW(Name2,w.GENERIC_WRITE,0,nil,w.CREATE_ALWAYS,0,nil)
	// os.get_std_handle()
	a := os.write_entire_file_from_bytes(file_name, Memory)
	//w.CloseHandle(FileHandle)
}

ProcessDidigtalButton :: proc(
	XInputButtonState: sdl.GamepadButton,
	OldState: ^game_button_state,
	NewState: ^game_button_state,
	GamePade: ^sdl.Gamepad,
) {
	NewState.HalfTransitionCount = OldState.EndedDown != NewState.EndedDown ? 1 : 0
	//    NewState.EndedDown =(XInputButtonState & ButtonBit) == ButtonBit
	NewState.EndedDown = sdl.GetGamepadButton(GamePade, XInputButtonState)

}

ProcessAnalogAsDidigtalButton :: proc(
	XInputButtonState: bool,
	OldState: ^game_button_state,
	NewState: ^game_button_state,
) {
	NewState.HalfTransitionCount = OldState.EndedDown != NewState.EndedDown ? 1 : 0
	//    NewState.EndedDown =(XInputButtonState & ButtonBit) == ButtonBit
	NewState.EndedDown = XInputButtonState
}
ProcessAnalogStick :: proc(Value: i16, DeadZone: i16) -> f32 {
	x: f32 = 0
	if Value < -1 * DeadZone {
		x = f32(Value) / 32768.0
	} else if Value > DeadZone {
		x = f32(Value) / 32767.0
	}
	return x
}
KeyboardProcessDidigtalButton :: proc(NewState: ^game_button_state, IsDown: bool) {
	if NewState.EndedDown != IsDown {
		NewState.HalfTransitionCount += 1
		//    NewState.EndedDown =(XInputButtonState & ButtonBit) == ButtonBit
		NewState.EndedDown = IsDown
	}
}
win32ProcessPendingMessages :: proc(KeyboardController: ^game_controller_input) {
	msg: sdl.Event
	KBGPtoUse := &KeyboardController.padButtons.(game_pad)
	for (sdl.PollEvent(&msg)) {
		//TODO could add a quit case here!
		#partial switch (msg.type) {

		case .QUIT:
			running = false
			break

		case .KEY_DOWN:
			VKCode := msg.key.key
			wasDown := msg.key.repeat
			isDown := true
			if wasDown != isDown {
				if VKCode == sdl.K_W {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Up, isDown)

				} else if VKCode == sdl.K_A {
					fmt.println("A IS PRESSED")
					fmt.println("hi joe")
					KeyboardProcessDidigtalButton(&KBGPtoUse.Left, isDown)

				} else if VKCode == sdl.K_S {

					//fmt.println("S is pressed", isDown)
					KeyboardProcessDidigtalButton(&KBGPtoUse.Down, isDown)

				} else if VKCode == sdl.K_D {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Right, isDown)

				} else if VKCode == sdl.K_Q {

				} else if VKCode == sdl.K_E {

				} else if VKCode == sdl.K_RIGHT {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Action4, isDown)
				} else if VKCode == sdl.K_DOWN {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Action3, isDown)
				} else if VKCode == sdl.K_LEFT {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Action2, isDown)
				} else if VKCode == sdl.K_UP {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Action1, isDown)
				} else if VKCode == sdl.K_ESCAPE {

					fmt.print("Escape: ")
					if (isDown) {
						fmt.print("is down")
					}

					fmt.print("\n")
				} else if VKCode == sdl.K_SPACE {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Start, isDown)
				}
				temp := sdl.GetKeyboardState(nil)
				if VKCode == sdl.K_F4 && temp[sdl.Scancode.LALT] == true {
					running = false
				}

			}
		case .KEY_UP:
			VKCode := msg.key.key
			wasDown := msg.key.repeat
			isDown := false
			if true {
				if VKCode == sdl.K_W {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Up, isDown)

				} else if VKCode == sdl.K_A {
					fmt.println("A IS PRESSED")
					KeyboardProcessDidigtalButton(&KBGPtoUse.Left, isDown)

				} else if VKCode == sdl.K_S {

					//fmt.println("S is pressed", isDown)
					KeyboardProcessDidigtalButton(&KBGPtoUse.Down, isDown)

				} else if VKCode == sdl.K_D {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Right, isDown)

				} else if VKCode == sdl.K_Q {

				} else if VKCode == sdl.K_E {

				} else if VKCode == sdl.K_RIGHT {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Action4, isDown)
				} else if VKCode == sdl.K_DOWN {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Action3, isDown)
				} else if VKCode == sdl.K_LEFT {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Action2, isDown)
				} else if VKCode == sdl.K_UP {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Action1, isDown)
				} else if VKCode == sdl.K_ESCAPE {

					fmt.print("Escape: ")
					if (isDown) {
						fmt.print("is down")
					}

					fmt.print("\n")
				} else if VKCode == sdl.K_SPACE {
					KeyboardProcessDidigtalButton(&KBGPtoUse.Start, isDown)
				}
			}


		//NewInput.Controllers[0].padButtons = KBGPtoUse
		//fmt.println(KBGPtoUse.Down)
		//fmt.println(KeyboardController)j
		}
	}
}
window_dimension :: struct {
	width:  i32,
	height: i32,
}

win32_sound_output :: struct {
	SamplesPerSecond:    u32,
	Hz:                  int,
	RunningSampleIndex:  u32,
	SquareWaveCounter:   int,
	SquareWavePeriod:    int,
	BytesPerSample:      u32,
	SecondaryBufferSize: u32,
	SoundLevel:          i16,
	LatencySampleCount:  u32,
	SafetyBytes:         u32,
}
GetWindowDimension :: proc(Window: ^sdl.Window) -> window_dimension {
	Result: window_dimension

	sdl.GetWindowSize(Window, &Result.width, &Result.height)
	return Result
}

win32_offscreen_buffer :: struct {
	memory:               rawptr,
	Height, Width, Pitch: i32,
	bmArena:              vmem.Arena,
	arena_err:            vmem.Allocator_Error, //= vmem.arena_init_growing(&Global_Back_Buffer.bmArena)
	arena_alloc:          mem.Allocator, //= vmem.arena_allocator(&Global_Back_Buffer.bmArena)l
}
win32_game_memory :: struct {
	bmArena:     vmem.Arena,
	arena_err:   vmem.Allocator_Error,
	arena_alloc: mem.Allocator,
}


ResizeDIBSection :: proc(Buffer: ^win32_offscreen_buffer, width: i32, height: i32) {

	//TODO Free DIBSection
	if (Buffer^.memory != nil) {
		//Saving this just in case I need windows Malloc
		// w.VirtualFree(Bitmapmemory,0,w.MEM_RELEASE)
		vmem.arena_destroy((&Buffer^.bmArena))

	}

	Buffer^.Height = height
	Buffer^.Width = width
	Buffer^.Pitch = width
	Bitmapmemorysize: uint = uint(4 * width * height)
	Buffer^.memory = make_multi_pointer([^]u8, Bitmapmemorysize, Global_Back_Buffer.arena_alloc) //&bmarena
}

main :: proc() {
	Global_Back_Buffer.arena_err = vmem.arena_init_growing(&Global_Back_Buffer.bmArena)
	Global_Back_Buffer.arena_alloc = vmem.arena_allocator(&Global_Back_Buffer.bmArena)
	game_api_version = 0
	game_api, game_api_ok := load_game_api(game_api_version)
	if !game_api_ok {
		fmt.println("FAILED TO LOAD GAME API")
		return
	}
	game_api_version += 1

	colorcount: ^int = new(int)
	colorcount^ = 0

	sdl_ok := sdl.Init({.VIDEO})//, .GAMEPAD,.JOYSTICK})
	defer sdl.Quit()

	if !sdl_ok {
		fmt.eprintln("Failed to initialize")
		return
	}

	driver := set_driver_by_priority({"metal", "gpu", "opengl", "software"})

	window := sdl.CreateWindow("Example Renderer", 1200, 700, {.RESIZABLE})
	renderer := sdl.CreateRenderer(window, driver)
	texture := sdl.CreateTexture(
		renderer,
		sdl.PixelFormat.BGRA32,
		sdl.TextureAccess.STREAMING,
		1200,
		720,
	)
	sdl.SetRenderLogicalPresentation(renderer, 1200, 700, .LETTERBOX)

	defer sdl.DestroyWindow(window)
	defer sdl.DestroyRenderer(renderer)

	// Enable VSync
	vsync_ok := sdl.SetRenderVSync(renderer, 1)
	if !vsync_ok {
		fmt.eprintln("Failed to enable VSync")
	}

	// Some variables for main loop
	display_id := sdl.GetDisplayForWindow(window)
	display_mode := sdl.GetCurrentDisplayMode(display_id)
	refresh_rate := display_mode.refresh_rate
	vsync_enabled := true
	fps_cap_enabled := true
	fps_target := 60
	s_depth := 5
	fps: f64

	color: sdl.FColor
	color_paused: bool

	fmt.print(refresh_rate)
	MonitorRefresh: int = int(refresh_rate)
	GameUpdateHz := MonitorRefresh / 2
	SecondsPerFrame: f32 = (1.0 / cast(f32)GameUpdateHz)
	PCFResult: u64 = sdl.GetPerformanceCounter()
	PerfCounterFrequency = PCFResult
	DesiredSchedulerMS: u32 = 1

	ResizeDIBSection(&Global_Back_Buffer, 1200, 700)


	win32Memory.arena_err = vmem.arena_init_growing(&win32Memory.bmArena)
	win32Memory.arena_alloc = vmem.arena_allocator(&win32Memory.bmArena)
	GameMemory.Permanentstoragesize = mem.Megabyte * 12
	//TODO may have to change this from a multipointer to a slice or something I don't know...
	GameMemory.PermanentStorage = make_multi_pointer(
		[^]rawptr,
		GameMemory.Permanentstoragesize,
		win32Memory.arena_alloc,
	) //&bmarena
	GameMemory.Transientstoragesize = mem.Gigabyte * 4
	GameMemory.Transientstorage = make_multi_pointer(
		[^]rawptr,
		GameMemory.Transientstoragesize,
		win32Memory.arena_alloc,
	) //&bmarena
	fmt.println(
		"Perm Storage: ",
		size_of(GameMemory.PermanentStorage),
		GameMemory.Permanentstoragesize,
	)
	GameMemory.PermanentStorageAlloc = vmem.arena_allocator(&win32Memory.bmArena)

	game_api.init(
		GameMemory.Permanentstoragesize,
		GameMemory.PermanentStorage,
		GameMemory.Transientstoragesize,
		GameMemory.Transientstorage,
		&GameMemory.PermanentStorageAlloc,
	)


	//        win32FillSoundBuffer(&SoundOutput,0,(SoundOutput.LatencySampleCount*SoundOutput.BytesPerSample),&SoundBuffer)


	LastCounter := win32GetWallClock()
	//TODO This probably can be replaced by newer code
	LastCycleCount := intrinsics.read_cycle_counter()
	Input: [2]game_input
	NewInput: ^game_input = &Input[0]
	//NewInput.Controllers
	OldInput: ^game_input = &Input[1]
	NewInput.dtForFrame = SecondsPerFrame
	//TODO I fixed the keyoard, I need to fix the controllers
	OldController: ^game_controller_input
	NewController: ^game_controller_input
	KeyboardController: ^game_controller_input = &NewInput.Controllers[0]
	KeyboardController.isConnected = true
	KBGP: game_pad
	KeyboardController.padButtons = KBGP
	KBGPtoUse := &KeyboardController.padButtons.(game_pad)


	//TODO Probabl should be global
	FlipWallClock := win32GetWallClock()

	numPads: i32
	numPads = 0
	ids := sdl.GetGamepads(&numPads)

	//fmt.println("num Pads:", numPads)
	gamePads: []^sdl.Gamepad
	for i in 0 ..< numPads {
		gamePads[i] = sdl.OpenGamepad(ids[i])
	}


	for running {

		frame_start := sdl.GetTicksNS()
		dll_time, dll_timer_err := os.last_write_time_by_name("game.dll")
		reload := dll_timer_err == os.ERROR_NONE && game_api.dll_time._nsec != dll_time._nsec
		if reload {
			new_api, new_api_ok := load_game_api(game_api_version)
			if new_api_ok {
				game_memory := game_api.mem_ptr()
				unload_game_api(game_api)
				game_api = new_api
				game_api.hot_reloaded(game_memory)
				game_api_version += 1
			}
		}
		KBGPtoUse^.Down.HalfTransitionCount = 0
		KBGPtoUse^.Up.HalfTransitionCount = 0
		KBGPtoUse^.Right.HalfTransitionCount = 0
		KBGPtoUse^.Left.HalfTransitionCount = 0
		KBGPtoUse^.Start.HalfTransitionCount = 0

		KBGPtoUse^.Action1.HalfTransitionCount = 0
		KBGPtoUse^.Action2.HalfTransitionCount = 0
		KBGPtoUse^.Action3.HalfTransitionCount = 0
		KBGPtoUse^.Action4.HalfTransitionCount = 0
		#force_inline win32ProcessPendingMessages(KeyboardController)
		//TODO POSSIBLY POLL MORE OFTEN
		mouse: sdl.MouseButtonFlags = sdl.GetMouseState(&NewInput.MouseX, &NewInput.MouseY)
		KeyboardProcessDidigtalButton(&NewInput.MouseButton[0], sdl.MouseButtonFlag.LEFT in mouse)
		KeyboardProcessDidigtalButton(&NewInput.MouseButton[1], sdl.MouseButtonFlag.RIGHT in mouse)
		//fmt.println("num Pads:", numPads, "has Pads: ", sdl.HasGamepad())
		for ControllerIndex: i32 = 0; ControllerIndex < numPads; ControllerIndex += 1 {
			//TODO - Only poll controllers when we know they are plugged in - you can do this with an HID flag
			//1+ for the keyboard
			OldController = &OldInput.Controllers[1 + ControllerIndex]
			NewController = &NewInput.Controllers[1 + ControllerIndex]

			NewController.isConnected = true


			//I believe all of this is necessary to work with xInput and Bitmask
			//I Know you can dereference Pad without ^ but I like doing it for clarity
			NCGP: game_pad
			OCGP: game_pad

			OldController.padButtons = OCGP
			NewController.padButtons = NCGP

			if NCGPtoUse, ok := &NewController.padButtons.(game_pad); ok {
				OCGPtoUse := &OldController.padButtons.(game_pad)
				ProcessDidigtalButton(
					sdl.GamepadButton.SOUTH,
					&OCGPtoUse.Action3,
					&NCGPtoUse.Action3,
					gamePads[ControllerIndex],
				)
				ProcessDidigtalButton(
					sdl.GamepadButton.EAST,
					&OCGPtoUse.Action1,
					&NCGPtoUse.Action1,
					gamePads[ControllerIndex],
				)
				ProcessDidigtalButton(
					sdl.GamepadButton.WEST,
					&OCGPtoUse.Action4,
					&NCGPtoUse.Action4,
					gamePads[ControllerIndex],
				)
				ProcessDidigtalButton(
					sdl.GamepadButton.NORTH,
					&OCGPtoUse.Action2,
					&NCGPtoUse.Action2,
					gamePads[ControllerIndex],
				)
				ProcessDidigtalButton(
					sdl.GamepadButton.LEFT_SHOULDER,
					&OCGPtoUse.LShoulder,
					&NCGPtoUse.LShoulder,
					gamePads[ControllerIndex],
				)
				ProcessDidigtalButton(
					sdl.GamepadButton.RIGHT_SHOULDER,
					&OCGPtoUse.RShoulder,
					&NCGPtoUse.RShoulder,
					gamePads[ControllerIndex],
				)
			} else {
				NCGPtoUse2 := &NewController.padButtons.([9]game_button_state)
				OCGPtoUse := &OldController.padButtons.([9]game_button_state)
				ProcessDidigtalButton(
					sdl.GamepadButton.SOUTH,
					&OCGPtoUse[0],
					&NCGPtoUse2[0],
					gamePads[ControllerIndex],
				)
				ProcessDidigtalButton(
					sdl.GamepadButton.EAST,
					&OCGPtoUse[1],
					&NCGPtoUse2[1],
					gamePads[ControllerIndex],
				)
				ProcessDidigtalButton(
					sdl.GamepadButton.WEST,
					&OCGPtoUse[2],
					&NCGPtoUse2[2],
					gamePads[ControllerIndex],
				)
				ProcessDidigtalButton(
					sdl.GamepadButton.NORTH,
					&OCGPtoUse[0],
					&NCGPtoUse2[0],
					gamePads[ControllerIndex],
				)
				ProcessDidigtalButton(
					sdl.GamepadButton.LEFT_SHOULDER,
					&OCGPtoUse[0],
					&NCGPtoUse2[0],
					gamePads[ControllerIndex],
				)
				ProcessDidigtalButton(
					sdl.GamepadButton.RIGHT_SHOULDER,
					&OCGPtoUse[0],
					&NCGPtoUse2[0],
					gamePads[ControllerIndex],
				)
			}
			Stickx: i16 = sdl.GetGamepadAxis(gamePads[ControllerIndex], sdl.GamepadAxis.LEFTX) //Pad^.sThumbLX
			Sticky: i16 = sdl.GetGamepadAxis(gamePads[ControllerIndex], sdl.GamepadAxis.LEFTY) //Pad^.sThumbLX			makefast: i32 = 1

			LEFT_THUMB_DEAD_ZONE :: 7849
			DigitalThreshold :: .5
			x := ProcessAnalogStick(Stickx, LEFT_THUMB_DEAD_ZONE)
			y := ProcessAnalogStick(Sticky, LEFT_THUMB_DEAD_ZONE)
			//INVERT X
			NewController.StickFramex = x
			NewController.StickFramey = y
			OCGPtoUse := &OldController.padButtons.(game_pad)
			NCGPtoUse := &NewController.padButtons.(game_pad)
			ProcessAnalogAsDidigtalButton(
				(NewController.StickFramex < -DigitalThreshold ? true : false),
				&OCGPtoUse.Left,
				&NCGPtoUse.Left,
			)
			ProcessAnalogAsDidigtalButton(
				(NewController.StickFramex > DigitalThreshold ? true : false),
				&OCGPtoUse.Right,
				&NCGPtoUse.Right,
			)
			ProcessAnalogAsDidigtalButton(
				(NewController.StickFramey < -DigitalThreshold ? true : false),
				&OCGPtoUse.Up,
				&NCGPtoUse.Up,
			)
			ProcessAnalogAsDidigtalButton(
				(NewController.StickFramey > DigitalThreshold ? true : false),
				&OCGPtoUse.Down,
				&NCGPtoUse.Down,
			)
			NewController.IsAnalgo = true
			//NewInput.Controllers[ControllerIndex+1] = NewController

			/*
			Vibration: w.XINPUT_VIBRATION
			Vibration.wRightMotorSpeed = 60000
			Vibration.wLeftMotorSpeed = 60000
			w.XInputSetState(cast(w.XUSER)0, &Vibration)
			*/
		}
		//TEMP CODE TO PUT THE BUFFER ON THE STACK - TODO Replace


		Thread: thread_context = {}
		Buffer: game_offscreen_buffer
		Buffer.memory = Global_Back_Buffer.memory
		Buffer.Width = Global_Back_Buffer.Width
		Buffer.Height = Global_Back_Buffer.Height
		Buffer.Pitch = Global_Back_Buffer.Pitch

		game_api.GameUpdateAndRender(
			&Thread,
			cast(^game_memory)game_api.mem_ptr(),
			NewInput,
			&Buffer,
		)

		EndCycleCount := intrinsics.read_cycle_counter()
		CycleElapsed := EndCycleCount - LastCycleCount
		WorkCounter := win32GetWallClock()
		SecondsElapseWork := win32GetSecondsElapsed(LastCounter, WorkCounter)
		SecondsElapsedForFrame := SecondsElapseWork

		EndCounter := win32GetWallClock()
		MSPFrame: f32 = 1000.0 * win32GetSecondsElapsed(LastCounter, win32GetWallClock())
		LastCounter = EndCounter

		buf_pitch: i32 = 1200 * 4
		sdl.UpdateTexture(texture, nil, Global_Back_Buffer.memory, buf_pitch)
		sdl.SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff)
		sdl.RenderClear(renderer)
		dest_rect: sdl.FRect
		dest_rect.x = 0
		dest_rect.y = 0
		dest_rect.w = 1200
		dest_rect.h = 700
		sdl.RenderTexture(renderer, texture, nil, &dest_rect)
		sdl.RenderPresent(renderer)
		/*
		CopyBufferToWindow(
			&Global_Back_Buffer,
			DevContext,
			Dimension.width,
			Dimension.height,
			0,
			0,
			Dimension.width,
			Dimension.height,
		)
		*/

		frame_end := sdl.GetTicksNS()

		// Cap fps if enabled
		npf_target := u64(1000000000 / fps_target) // nanoseconds per frame target
		if fps_cap_enabled && (frame_end - frame_start) < npf_target {
			sleep_time := npf_target - (frame_end - frame_start)
			sdl.DelayPrecise(sleep_time)
			frame_end = sdl.GetTicksNS() // Update frame_end counter to include sleep_time for fps calculation
		}

		// update fps tracker
		fps = 1000000000.000 / f64(frame_end - frame_start)
		FlipWallClock = win32GetWallClock()

		LastCycleCount = EndCycleCount
		//TODO Can write a little func to do this so you just pingong back and forth
		Temp: ^game_input = NewInput
		//fmt.println(NewInput.Controllers[0].padButtons)
		NewInput = OldInput
		OldInput = Temp
	}
	//game_api.sd()
	unload_game_api(game_api)

}
//    w.MessageBoxW(nil,w.L("This is a test"), w.L("Lol"),w.MB_OK|w.MB_ICONINFORMATION)
