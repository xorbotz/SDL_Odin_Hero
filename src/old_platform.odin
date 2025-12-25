package main

import w "core:sys/windows"
/*

import "base:intrinsics"
import "base:runtime"
import libc "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import os "core:os"
import w "core:sys/windows"

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
GlobalSecondaryBuffer: ^IDirectSoundBuffer
GameMemory: game_memory
win32Memory: win32_game_memory
PerfCounterFrequency: w.LARGE_INTEGER

SoundisValid: bool = false
//hotreloadcode
game_api_version := 0
GameAPI :: struct {
    init:                proc(_: u64, _: rawptr, _: u64, _: rawptr, _: ^mem.Allocator),
    sd:                  proc(),
    mem_ptr:             proc() -> rawptr,
    GameGetSoundSamples: proc(_: rawptr, _: rawptr, _: rawptr) -> bool,
    GameUpdateAndRender: proc(_: rawptr, _: rawptr, _: rawptr, _: rawptr) -> bool,
    hot_reloaded:        proc(_: rawptr),
    lib:                 dynlib.Library,
    dll_time:            os.File_Time,
    api_version:         int,
}

load_game_api :: proc(api_version: int) -> (GameAPI, bool) {
    dll_time, dll_time_err := os.last_write_time_by_name("game.dll"s)
    if dll_time_err != os.ERROR_NONE {
        fmt.println("FETCHING DLL FAILED")
        return {}, false
    }
    dll_name := fmt.tprintf("game_{0}.dll", api_version)
    copy_cmd := fmt.ctprintf("copy game.dll {0}", dll_name)
    if libc.system(copy_cmd) != 0 {
        fmt.println("FAILED TO COPY game.dll to {0}", dll_name)
        return {}, false
    }
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
    api.dll_time = dll_time
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

win32GetWallClock :: #force_inline proc() -> w.LARGE_INTEGER {
    Result: w.LARGE_INTEGER
    w.QueryPerformanceCounter(&Result)
    return Result
}
win32GetSecondsElapsed :: #force_inline proc(Start: w.LARGE_INTEGER, End: w.LARGE_INTEGER) -> f32 {
    return (f32(End - Start)) / f32(PerfCounterFrequency)

}

ReadEntireFile :: proc(filename: string) -> ([^]u8, i64) {

    file_handle, handle := os.open(filename)
    //file_data,file_ok:=os.read_entire_file_from_filename(filename,gameAlloc^)
    fmt.println("handle error: ", handle)
    if handle == nil {
        fmt.println("have handle")
        file_size, _ := os.file_size(file_handle)
        fmt.println("size: ", file_size)
        file_data, file_ok := os.read_entire_file_from_handle(file_handle)
        if file_ok {
            fileptr: [^]u8 = make_multi_pointer([^]u8, file_size, Global_Back_Buffer.arena_alloc)
            fileptr = cast([^]u8)(&file_data)
            return fileptr, file_size
        } else {
        //TODO maybe free this memory? I have to figure that out.
        }
        os.close(file_handle)
        return nil, -1

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
    os.write_entire_file(file_name, Memory)
//w.CloseHandle(FileHandle)
}
ProcessDidigtalButton :: proc(
XInputButtonState: w.XINPUT_GAMEPAD_BUTTON,
OldState: ^game_button_state,
NewState: ^game_button_state,
ButtonBit: w.XINPUT_GAMEPAD_BUTTON_BIT,
) {
    NewState.HalfTransitionCount = OldState.EndedDown != NewState.EndedDown ? 1 : 0
    //    NewState.EndedDown =(XInputButtonState & ButtonBit) == ButtonBit
    NewState.EndedDown =
    XInputButtonState & w.XINPUT_GAMEPAD_BUTTON{ButtonBit} ==
    w.XINPUT_GAMEPAD_BUTTON{ButtonBit}
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
    msg: w.MSG
    KBGPtoUse := &KeyboardController.padButtons.(game_pad)
    for w.PeekMessageW(&msg, nil, 0, 0, w.PM_REMOVE) {
    //TODO could add a quit case here!
        switch (msg.message) {

        case w.WM_KEYUP, w.WM_KEYDOWN, w.WM_SYSKEYDOWN, w.WM_SYSKEYUP:
            VKCode := msg.wParam
            wasDown: bool = (msg.lParam & (1 << 30) != 0)
            isDown: bool = msg.lParam & (1 << 31) == 0
            //TODO NEED TO FIX the stickykeys?
            if isDown != wasDown {
                if VKCode == 'W' {
                    KeyboardProcessDidigtalButton(&KBGPtoUse.Up, isDown)

                } else if VKCode == 'A' {
                    fmt.println("A IS PRESSED")
                    KeyboardProcessDidigtalButton(&KBGPtoUse.Left, isDown)

                } else if VKCode == 'S' {

                //fmt.println("S is pressed", isDown)
                    KeyboardProcessDidigtalButton(&KBGPtoUse.Down, isDown)

                } else if VKCode == 'D' {
                    KeyboardProcessDidigtalButton(&KBGPtoUse.Right, isDown)

                } else if VKCode == 'Q' {

                } else if VKCode == 'E' {

                } else if VKCode == w.VK_RIGHT {
                    KeyboardProcessDidigtalButton(&KBGPtoUse.Action4, isDown)
                } else if VKCode == w.VK_DOWN {
                    KeyboardProcessDidigtalButton(&KBGPtoUse.Action3, isDown)
                } else if VKCode == w.VK_LEFT {
                    KeyboardProcessDidigtalButton(&KBGPtoUse.Action2, isDown)
                } else if VKCode == w.VK_UP {
                    KeyboardProcessDidigtalButton(&KBGPtoUse.Action1, isDown)
                } else if VKCode == w.VK_ESCAPE {

                    fmt.print("Escape: ")
                    if (isDown) {
                        fmt.print("is down")
                    }

                    if (wasDown) {
                        fmt.print("was down")
                    }
                    fmt.print("\n")
                } else if VKCode == w.VK_SPACE {
                    KeyboardProcessDidigtalButton(&KBGPtoUse.Start, isDown)
                }
                AltKeydown := msg.lParam & (1 << 29)
                if VKCode == w.VK_F4 && AltKeydown > 0 {
                    running = false
                }

            }

        //NewInput.Controllers[0].padButtons = KBGPtoUse
        //fmt.println(KBGPtoUse.Down)
        //fmt.println(KeyboardController)j
        case:
            w.TranslateMessage(&msg)
            w.DispatchMessageW(&msg)
        }
    }
}
win32_window_dimensions :: struct {
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

win32ClearBuffer :: proc(SoundOutput: ^win32_sound_output) {
    Region1: w.VOID
    Region1Size: w.DWORD
    Region2: w.VOID
    Region2Size: w.DWORD

    lock_ok := GlobalSecondaryBuffer->Lock(
    0,
    SoundOutput.SecondaryBufferSize,
    &Region1,
    &Region1Size,
    &Region2,
    &Region2Size,
    0,
    )
    if lock_ok < 0 {
    // fmt.eprintf("Error in Lock: 0x%X\n",u32(u64(lock_ok) & 0x0000_0000_FFFF_FFFF))
    //  return
    } else {
        temp: [^]i8 = cast([^]i8)Region1
        temp2: [^]i8 = cast([^]i8)Region2
        DestSample: [^]i32 = cast([^]i32)temp
        DestSample2: [^]i32 = cast([^]i32)temp2

        for ByteIndex: w.DWORD = 0; ByteIndex < Region1Size; ByteIndex += 1 {
            temp[ByteIndex] = 0
        }
        for ByteIndex: w.DWORD = 0; ByteIndex < Region2Size; ByteIndex += 1 {
            temp2[ByteIndex] = 0
        }
    }
    ulock_ok := GlobalSecondaryBuffer->Unlock(Region1, Region1Size, Region2, Region2Size)
    if ulock_ok < 0 {
        fmt.eprintf(
        "Error in GetCurrentPosition: 0x%X\n",
        u32(u64(ulock_ok) & 0x0000_0000_FFFF_FFFF),
        )
        return
    }

}
//Something here isn't quite right when extracting it to the game layer but i don't know what
win32FillSoundBuffer :: proc(
SoundOutput: ^win32_sound_output,
SampleIndextoLock: w.DWORD,
BytesToWrite: w.DWORD,
SourceBuffer: ^game_output_sound_buffer,
) {
    Region1: w.VOID
    Region1Size: w.DWORD
    Region2: w.VOID
    Region2Size: w.DWORD
    //   fmt.println(BytesToWrite)


    lock_ok := GlobalSecondaryBuffer->Lock(
    SampleIndextoLock,
    BytesToWrite,
    &Region1,
    &Region1Size,
    &Region2,
    &Region2Size,
    0,
    )
    if lock_ok < 0 {
    // fmt.eprintf("Error in Lock: 0x%X\n",u32(u64(lock_ok) & 0x0000_0000_FFFF_FFFF))
    //  jreturn
    }

    // Each sample is 32 bit, 16 left and 16 right channel
    temp: [^]i16 = cast([^]i16)Region1
    temp2: [^]i16 = cast([^]i16)Region2
    DestSample: [^]i32 = cast([^]i32)temp
    DestSample2: [^]i32 = cast([^]i32)temp2
    SourceSample: [^]i32 = SourceBuffer.SampleOut
    Region1SampleCount: w.DWORD = Region1Size / cast(u32)SoundOutput.BytesPerSample
    Region2SampleCount: w.DWORD = Region2Size / cast(u32)SoundOutput.BytesPerSample

    for SampleIndex: w.DWORD = 0; SampleIndex < Region1SampleCount; SampleIndex += 1 {
    //SampleValue:i16 = ((SoundOutput.RunningSampleIndex/cast(u32)SoundOutput.SquareWavePeriod/2)%2)==0?SoundOutput.SoundLevel:-1*SoundOutput.SoundLevel
    //temp:=cast(i32)SampleValue
    //temp = temp<<16
    //temp2:=i32(i32(SampleValue)&0b00000000000000001111111111111111)
    //final: = temp|temp2
        SoundOutput.RunningSampleIndex += 1
        DestSample[SampleIndex] = SourceSample[SampleIndex]
    }

    for SampleIndex: w.DWORD = 0; SampleIndex < Region2SampleCount; SampleIndex += 1 {
    //SampleValue:i16 = ((SoundOutput.RunningSampleIndex/cast(u32)SoundOutput.SquareWavePeriod/2)%2)==0?SoundOutput.SoundLevel:-1*SoundOutput.SoundLevel
    //temp:=cast(i32)SampleValue
    //temp = temp<<16
    //temp2:=i32(i32(SampleValue)&0b00000000000000001111111111111111)
    //final: = temp|temp2
        SoundOutput.RunningSampleIndex += 1
        DestSample2[SampleIndex] = SourceSample[SampleIndex + Region1SampleCount]
    }

    //        fmt.println("RunningSampleindex", SoundOutput.RunningSampleIndex)
    ulock_ok := GlobalSecondaryBuffer->Unlock(Region1, Region1Size, Region2, Region2Size)
    if ulock_ok < 0 {
        fmt.eprintf(
        "Error in GetCurrentPosition: 0x%X\n",
        u32(u64(ulock_ok) & 0x0000_0000_FFFF_FFFF),
        )
        return
    }

}
InitDSound :: proc(
Window: w.HWND,
SamplesPerSecond: u32,
PrimaryBufferSize: u32,
SecondaryBufferSize: u32,
) {
//TODO - REPLACE ALL OF THIS WITH MINIAUDIO. I DON't Have the time to do that yet but I think low level miniaudio is right
    lib, ok := dynlib.load_library("dsound.dll")
    assert(ok)
    sym, found := dynlib.symbol_address(lib, "DirectSoundCreate")
    assert(found)
    DirectSound: ^IDirectSound = {}
    DirectSoundCreate := cast(proc(
    lpGuid: ^w.GUID,
    ppDS: ^^IDirectSound,
    pUnkOuter: rawptr,
    ) -> w.HRESULT)sym
    ds_result := DirectSoundCreate(nil, &DirectSound, nil)
    if ds_result < 0 {
        fmt.eprintf(
        "Error in DirectSoundCreate: 0x%X\n",
        u32(u64(ds_result) & 0x0000_0000_FFFF_FFFF),
        )
        return
    }
    WaveFormat: WAVEFORMATEX = {
        wFormatTag      = WAVE_FORMAT_PCM,
        nChannels       = 2,
        nSamplesPerSec  = cast(u32)SamplesPerSecond,
        wBitsPerSample  = 16,
        nBlockAlign     = (2 * 16) / 8,
        nAvgBytesPerSec = cast(u32)(SamplesPerSecond * (2 * 16) / 8),
        cbSize          = 0,
    }
    if (Window != nil) {
        scl_res := DirectSound->SetCooperativeLevel(Window, DSSCL_PRIORITY)
        if scl_res < 0 {
            fmt.eprintf(
            "Error in SetCooperativeLevel: 0x%X\n",
            u32(u64(scl_res) & 0x0000_0000_FFFF_FFFF),
            )
            return
        }
    }
    BufferDescription: DSBUFFERDESC = {
        dwSize  = size_of(DSBUFFERDESC),
        dwFlags = DSBCAPS_PRIMARYBUFFER,
    //This causes an error
    //dwBufferBytes = PrimaryBufferSize,
    }
    PrimaryBuffer: ^IDirectSoundBuffer
    cb_res := DirectSound->CreateSoundBuffer(&BufferDescription, &PrimaryBuffer, nil)
    if cb_res < 0 {
        fmt.eprintf(
        "Error in SetCooperativeLevel: 0x%X\n",
        u32(u64(cb_res) & 0x0000_0000_FFFF_FFFF),
        )
        return
    }

    sf_res := PrimaryBuffer->SetFormat(&WaveFormat)
    if sf_res < 0 {
        fmt.eprintf(
        "Error in SetCooperativeLevel: 0x%X\n",
        u32(u64(sf_res) & 0x0000_0000_FFFF_FFFF),
        )
        return
    }

    SecondaryBufferDescription: DSBUFFERDESC = {
        dwSize        = size_of(DSBUFFERDESC),
        dwFlags       = DSBCAPS_GETCURRENTPOSITION2,
        dwBufferBytes = SecondaryBufferSize,
        lpwfxFormat   = &WaveFormat,
    }

    sb_err := DirectSound->CreateSoundBuffer(
    &SecondaryBufferDescription,
    &GlobalSecondaryBuffer,
    nil,
    )

    if sb_err < 0 {
        fmt.eprintf(
        "Error in Creating 2ndary buffrer: 0x%X\n",
        u32(u64(sb_err) & 0x0000_0000_FFFF_FFFF),
        )
        return
    } else {
        fmt.eprint("2ndary buffer created successfully")
    }

}

GetWindowDimension :: proc(Window: w.HWND) -> win32_window_dimensions {
    Result: win32_window_dimensions

    ClientRect: w.RECT
    w.GetClientRect(Window, &ClientRect)
    Result.width = ClientRect.right - ClientRect.left
    Result.height = ClientRect.bottom - ClientRect.top
    return Result
}

win32_offscreen_buffer :: struct {
    info:                 w.BITMAPINFO,
    infoadr:              ^w.BITMAPINFO,
    memory:               w.VOID,
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


CopyBufferToWindow :: proc(
Buffer: ^win32_offscreen_buffer,
DevContext: w.HDC,
WindowWidth: i32,
WindowHeight: i32,
x, y, width, height: i32,
) {
    OffsetX: i32 = 10
    OffsetY: i32 = 10


    //Note Changed f to be 1x1 instead of stretching with the window
    w.StretchDIBits(
    DevContext,
    OffsetX,
    OffsetY,
    Buffer.Width,
    Buffer.Height, //WindowWidth, WindowHeight,
    0,
    0,
    Buffer.Width,
    Buffer.Height,
    Buffer.memory,
    Buffer.infoadr,
    w.DIB_RGB_COLORS,
    w.SRCCOPY,
    )

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
    Buffer^.info.bmiHeader.biSize = size_of(Buffer^.info.bmiHeader)
    Buffer^.info.bmiHeader.biWidth = Buffer^.Width
    Buffer^.info.bmiHeader.biHeight = -Buffer^.Height
    Buffer^.info.bmiHeader.biPlanes = 1
    Buffer^.info.bmiHeader.biBitCount = 32
    Buffer^.info.bmiHeader.biCompression = w.BI_RGB
    Buffer^.info.bmiHeader.biSizeImage = 0
    Buffer^.info.bmiHeader.biXPelsPerMeter = 0
    Buffer^.info.bmiHeader.biYPelsPerMeter = 0
    Buffer^.info.bmiHeader.biClrImportant = 0
    Buffer^.info.bmiHeader.biClrImportant = 0
    Buffer^.infoadr = &Buffer^.info

    Bitmapmemorysize: uint = uint(4 * width * height)
    //Saving this in case I need to switch back to windows Malloc
    //Bitmapmemory = w.VirtualAlloc(nil,Bitmapmemorysize,w.MEM_COMMIT, w.PAGE_READWRITE)
    Buffer^.memory = make_multi_pointer([^]u8, Bitmapmemorysize, Global_Back_Buffer.arena_alloc) //&bmarena
}
wndproc :: proc "stdcall" (
window: w.HWND,
msg: w.UINT,
wparam: w.WPARAM,
lparam: w.LPARAM,
) -> w.LRESULT {
    context = runtime.default_context()
    Result: w.LRESULT = 0

    switch (msg) {
    case w.WM_SIZE:

    case w.WM_DESTROY:
        w.OutputDebugStringA("WM_DESTROY\n")
        running = false

    case w.WM_KEYUP, w.WM_KEYDOWN, w.WM_SYSKEYDOWN, w.WM_SYSKEYUP:
        fmt.print("Error in Keyboard handling")
        assert(false == true)

    case w.WM_CLOSE:
    //TODO: change this with a message
        w.OutputDebugStringA("WM_CLOSE\n")
        running = false
    //w.PostQuitMessage(0)

    case w.WM_ACTIVATEAPP:
        w.OutputDebugStringA("WM_ACTivateApp\n")
    case w.WM_PAINT:
        painter: w.PAINTSTRUCT

        DevContext: w.HDC = w.BeginPaint(window, &painter)
        x := painter.rcPaint.left
        y := painter.rcPaint.top
        width := painter.rcPaint.right - painter.rcPaint.left
        height := painter.rcPaint.bottom - painter.rcPaint.top

        Dimension := GetWindowDimension(window)
        CopyBufferToWindow(
        &Global_Back_Buffer,
        DevContext,
        Dimension.width,
        Dimension.height,
        x,
        y,
        width,
        height,
        )

        //w.PatBlt(DevContext,painter.rcPaint.left, painter.rcPaint.top,width,height,color)
        w.EndPaint(window, &painter)
    //fmt.println(colorcount)
    //w.OutputDebugStringA(colorcount)
    case:
        Result = w.DefWindowProcW(window, msg, wparam, lparam)
    //            w.OutputDebugStringA("WM_DEFAULT\n")


    }
    return Result
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
    instance := w.HINSTANCE(w.GetModuleHandleW(nil))


    class_name := w.L("HH Window")

    cls := w.WNDCLASSW {
    //DO THESER MATTER? Yes - redraws the whole window whenever reZied
        style         = w.CS_HREDRAW | w.CS_VREDRAW,
        lpfnWndProc   = wndproc,
        hInstance     = instance,
        lpszClassName = class_name,
    }
    MonitorRefresh: int = 60
    GameUpdateHz := MonitorRefresh / 2
    SecondsPerFrame: f32 = (1.0 / cast(f32)GameUpdateHz)
    PCFResult: w.LARGE_INTEGER
    w.QueryPerformanceFrequency(&PCFResult)
    PerfCounterFrequency = PCFResult
    DesiredSchedulerMS: u32 = 1
    Sleepisok := w.timeBeginPeriod(DesiredSchedulerMS) == w.TIMERR_NOERROR
    class := w.RegisterClassW(&cls)
    assert(class != 0, "calss iddn't register oh no")
    GameWindow := w.CreateWindowExW(
    w.WS_EX_LEFT,
    cls.lpszClassName,
    w.L("Game WIndow DUde"),
    w.WS_OVERLAPPEDWINDOW | w.WS_VISIBLE,
    w.CW_USEDEFAULT,
    w.CW_USEDEFAULT,
    w.CW_USEDEFAULT,
    w.CW_USEDEFAULT,
    nil,
    nil,
    instance,
    nil,
    )

    ResizeDIBSection(&Global_Back_Buffer, 1200, 700)

    fmt.println(GameWindow)
    fmt.println(cast(u16)w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.A})
    if (GameWindow != nil) {
        msg: w.MSG
        refDC := w.GetDC(GameWindow)
        posRate := w.GetDeviceCaps(refDC, 0x74)
        w.ReleaseDC(GameWindow, refDC)

        if posRate > 1 {
            MonitorRefresh = cast(int)posRate
            GameUpdateHz := MonitorRefresh
        }

        SoundOutput: win32_sound_output
        SoundOutput.SamplesPerSecond = 48000
        SoundOutput.Hz = 440
        SoundOutput.RunningSampleIndex = 0
        SoundOutput.SquareWaveCounter = 0

        SoundOutput.SquareWavePeriod = 48000 / SoundOutput.Hz
        SoundOutput.BytesPerSample = size_of(i16) * 2
        SoundOutput.SecondaryBufferSize =
        SoundOutput.SamplesPerSecond * cast(u32)SoundOutput.BytesPerSample
        SoundOutput.SoundLevel = 1000
        SoundOutput.LatencySampleCount = 3 * SoundOutput.SamplesPerSecond / (cast(u32)GameUpdateHz)
        SoundOutput.SafetyBytes =
        8 * SoundOutput.SamplesPerSecond * SoundOutput.BytesPerSample / (cast(u32)GameUpdateHz)
        fmt.println("SafetyBytes", SoundOutput.SafetyBytes)


        InitDSound(
        GameWindow,
        SoundOutput.SamplesPerSecond,
        48000 * size_of(i16) * 2,
        48000 * size_of(i16) * 2,
        )
        Temp2: ^[48000]i32 = new([48000]i32, Global_Back_Buffer.arena_alloc)
        TempS: []i32 = make_slice(
        []i32,
        SoundOutput.SecondaryBufferSize,
        Global_Back_Buffer.arena_alloc,
        )
        Samples: [^]i32
        Samples = raw_data(Temp2[:])

        win32Memory.arena_err = vmem.arena_init_growing(&win32Memory.bmArena)
        win32Memory.arena_alloc = vmem.arena_allocator(&win32Memory.bmArena)
        GameMemory.Permanentstoragesize = mem.Gigabyte * 1
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
        win32ClearBuffer(&SoundOutput)
        GlobalSecondaryBuffer->Play(0, 0, 0x01)

        soundisPlaying := true

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
        KBGP: game_pad
        KeyboardController.padButtons = KBGP
        KBGPtoUse := &KeyboardController.padButtons.(game_pad)


        //TODO Probabl should be global
        FlipWallClock: w.LARGE_INTEGER = win32GetWallClock()

        for running {
            dll_time, dll_timer_err := os.last_write_time_by_name("game.dll")
            reload := dll_timer_err == os.ERROR_NONE && game_api.dll_time != dll_time
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
            MouseP: w.POINT
            w.GetCursorPos(&MouseP)
            w.ScreenToClient(GameWindow, &MouseP)
            NewInput.MouseX = MouseP.x
            NewInput.MouseY = MouseP.y
            KeyboardProcessDidigtalButton(
            &NewInput.MouseButton[0],
            (w.GetKeyState(w.VK_LBUTTON) & (1 << 14)) == (1 << 14),
            )
            KeyboardProcessDidigtalButton(
            &NewInput.MouseButton[1],
            (w.GetKeyState(w.VK_RBUTTON) & (1 << 14)) == (1 << 14),
            )
            for ControllerIndex: w.DWORD = 0;
            ControllerIndex < w.XUSER_MAX_COUNT;
            ControllerIndex += 1 {
                ControllerState: w.XINPUT_STATE
                //TODO - Only poll controllers when we know they are plugged in - you can do this with an HID flag
                //1+ for the keyboard
                OldController = &OldInput.Controllers[1 + ControllerIndex]
                NewController = &NewInput.Controllers[1 + ControllerIndex]

                if cast(u32)w.XInputGetState(cast(w.XUSER)ControllerIndex, &ControllerState) ==
                w.ERROR_SUCCESS {
                    NewController.isConnected = true
                    Pad: ^w.XINPUT_GAMEPAD = &ControllerState.Gamepad

                    //I believe all of this is necessary to work with xInput and Bitmask
                    //I Know you can dereference Pad without ^ but I like doing it for clarity
                    Up: bool =
                    Pad^.wButtons &
                    w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_UP} ==
                    w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_UP}
                    Down: bool =
                    Pad^.wButtons &
                    w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_DOWN} ==
                    w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_DOWN}
                    Left: bool =
                    Pad^.wButtons &
                    w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_LEFT} ==
                    w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_LEFT}
                    Right: bool =
                    Pad^.wButtons &
                    w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_RIGHT} ==
                    w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_RIGHT}
                    Start: bool =
                    Pad^.wButtons &
                    w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.START} ==
                    w.XINPUT_GAMEPAD_BUTTON{w.XINPUT_GAMEPAD_BUTTON_BIT.START}
                    NCGP: game_pad
                    OCGP: game_pad

                    OldController.padButtons = OCGP
                    NewController.padButtons = NCGP

                    if NCGPtoUse, ok := &NewController.padButtons.(game_pad); ok {
                        OCGPtoUse := &OldController.padButtons.(game_pad)
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse.Action3,
                        &NCGPtoUse.Action3,
                        w.XINPUT_GAMEPAD_BUTTON_BIT.A,
                        )
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse.Action1,
                        &NCGPtoUse.Action1,
                        w.XINPUT_GAMEPAD_BUTTON_BIT.B,
                        )
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse.Action4,
                        &NCGPtoUse.Action4,
                        w.XINPUT_GAMEPAD_BUTTON_BIT.X,
                        )
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse.Action2,
                        &NCGPtoUse.Action2,
                        w.XINPUT_GAMEPAD_BUTTON_BIT.Y,
                        )
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse.LShoulder,
                        &NCGPtoUse.LShoulder,
                        w.XINPUT_GAMEPAD_BUTTON_BIT.LEFT_SHOULDER,
                        )
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse.RShoulder,
                        &NCGPtoUse.RShoulder,
                        w.XINPUT_GAMEPAD_BUTTON_BIT.RIGHT_SHOULDER,
                        )
                    } else {
                        NCGPtoUse2 := &NewController.padButtons.([9]game_button_state)
                        OCGPtoUse := &OldController.padButtons.([9]game_button_state)
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse[0],
                        &NCGPtoUse2[0],
                        w.XINPUT_GAMEPAD_BUTTON_BIT.A,
                        )
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse[1],
                        &NCGPtoUse2[1],
                        w.XINPUT_GAMEPAD_BUTTON_BIT.B,
                        )
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse[2],
                        &NCGPtoUse2[2],
                        w.XINPUT_GAMEPAD_BUTTON_BIT.X,
                        )
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse[0],
                        &NCGPtoUse2[0],
                        w.XINPUT_GAMEPAD_BUTTON_BIT.Y,
                        )
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse[0],
                        &NCGPtoUse2[0],
                        w.XINPUT_GAMEPAD_BUTTON_BIT.LEFT_SHOULDER,
                        )
                        ProcessDidigtalButton(
                        Pad^.wButtons,
                        &OCGPtoUse[0],
                        &NCGPtoUse2[0],
                        w.XINPUT_GAMEPAD_BUTTON_BIT.RIGHT_SHOULDER,
                        )
                    }
                    Stickx: i16 = Pad^.sThumbLX
                    Sticky: i16 = Pad^.sThumbLY
                    makefast: i32 = 1

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


                } else {
                    NewController.isConnected = false
                }
                Vibration: w.XINPUT_VIBRATION
                Vibration.wRightMotorSpeed = 60000
                Vibration.wLeftMotorSpeed = 60000
                w.XInputSetState(cast(w.XUSER)0, &Vibration)
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

            PlayerCursor: w.DWORD
            WriteCursor: w.DWORD
            SampleIndextoLock: w.DWORD
            WritePointer: w.DWORD = 0
            BytesToWrite: w.DWORD = 0


            FromBegintoAudioSec := win32GetSecondsElapsed(FlipWallClock, win32GetWallClock())
            gp_ok := GlobalSecondaryBuffer->GetCurrentPosition(&PlayerCursor, &WriteCursor)

            if gp_ok == 0 {

                if !SoundisValid {
                    SoundOutput.RunningSampleIndex = WriteCursor / SoundOutput.BytesPerSample
                    SoundisValid = true
                }
                SampleIndextoLock = 0
                TargetCursor: w.DWORD = 0
                BytesToWrite = 0
                SampleIndextoLock =
                (SoundOutput.RunningSampleIndex * cast(u32)SoundOutput.BytesPerSample) %
                SoundOutput.SecondaryBufferSize

                ExpectedSoundBytesPerFrame :=
                SoundOutput.SamplesPerSecond * SoundOutput.BytesPerSample / u32(GameUpdateHz)
                SecondsTillFlip := SecondsPerFrame - FromBegintoAudioSec
                ExpectedBytestillFlip := cast(w.DWORD)((SecondsTillFlip / SecondsPerFrame) *
                f32(ExpectedSoundBytesPerFrame))
                //               ExpectedFrameBoundaryByte:= PlayerCursor+ExpectedSoundBytesPerFrame
                ExpectedFrameBoundaryByte := PlayerCursor + ExpectedBytestillFlip
                SafeWriteCursor := WriteCursor
                if SafeWriteCursor < PlayerCursor {
                    SafeWriteCursor += SoundOutput.SecondaryBufferSize
                }
                assert(SafeWriteCursor >= PlayerCursor)
                AudioCardLowLat := SafeWriteCursor < ExpectedFrameBoundaryByte

                if false && AudioCardLowLat {

                    TargetCursor =
                    (ExpectedFrameBoundaryByte + ExpectedSoundBytesPerFrame) %
                    SoundOutput.SecondaryBufferSize
                } else {

                    TargetCursor =
                    (WriteCursor + ExpectedFrameBoundaryByte + SoundOutput.SafetyBytes) %
                    SoundOutput.SecondaryBufferSize
                }
                if SampleIndextoLock > TargetCursor {
                    BytesToWrite = SoundOutput.SecondaryBufferSize - SampleIndextoLock
                    BytesToWrite += TargetCursor
                } else {
                    BytesToWrite = TargetCursor - SampleIndextoLock
                }
                SoundBuffer: game_output_sound_buffer
                SoundBuffer.SamplesPerSecond = SoundOutput.SamplesPerSecond
                SoundBuffer.SampleCount = BytesToWrite / SoundOutput.BytesPerSample
                SoundBuffer.SampleOut = Samples
                SoundBuffer.ToneHz = 440 * 2
                game_api.GameGetSoundSamples(
                &Thread,
                cast(^game_memory)game_api.mem_ptr(),
                &SoundBuffer,
                )

                //Change to Commit.

                win32FillSoundBuffer(&SoundOutput, SampleIndextoLock, BytesToWrite, &SoundBuffer)
            } else {
                SoundisValid = false
            }
            if SoundisValid {
            }

            EndCycleCount := intrinsics.read_cycle_counter()
            CycleElapsed := EndCycleCount - LastCycleCount
            WorkCounter := win32GetWallClock()
            SecondsElapseWork := win32GetSecondsElapsed(LastCounter, WorkCounter)
            SecondsElapsedForFrame := SecondsElapseWork
            if SecondsElapsedForFrame <= SecondsPerFrame {
                for SecondsElapsedForFrame < SecondsPerFrame {
                    Sleepms: w.DWORD = w.DWORD(1000.0 * (SecondsPerFrame - SecondsElapsedForFrame))
                    if (Sleepisok) {
                        w.Sleep(Sleepms)
                    }
                    SecondsElapsedForFrame = win32GetSecondsElapsed(
                    LastCounter,
                    win32GetWallClock(),
                    )
                }
            } else {
            //assert for debug
            //    assert(true==false)
            }
            EndCounter: w.LARGE_INTEGER = win32GetWallClock()
            MSPFrame: f32 = 1000.0 * win32GetSecondsElapsed(LastCounter, win32GetWallClock())
            fmt.println("FPS: ", 1/(MSPFrame/1000))
            LastCounter = EndCounter

            DevContext: w.HDC = w.GetDC(GameWindow)
            Dimension := GetWindowDimension(GameWindow)
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
            FlipWallClock = win32GetWallClock()
            w.ReleaseDC(GameWindow, DevContext)

            LastCycleCount = EndCycleCount
            //TODO Can write a little func to do this so you just pingong back and forth
            Temp: ^game_input = NewInput
            //fmt.println(NewInput.Controllers[0].padButtons)
            NewInput = OldInput
            OldInput = Temp
        }
        //game_api.sd()
        unload_game_api(game_api)
    } else {
        fmt.println("we did not create the window!")
    }
}*/
//    w.MessageBoxW(nil,w.L("This is a test"), w.L("Lol"),w.MB_OK|w.MB_ICONINFORMATION)
