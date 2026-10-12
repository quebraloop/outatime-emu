local CHIP8 = require("chip8")

local COLOR = { 85 / 255, 15 / 255, 247 / 255 }
local BACKGROUND = { 0, 0, 0 }

local SCALE = 20
local WIDTH = DISPLAY_WIDTH * SCALE
local HEIGHT = DISPLAY_HEIGHT * SCALE

local FPS = 60
local FRAME_TIME = 1 / FPS
local INSTRUCTIONS_PER_SECOND = 720

local CYCLES_PER_FRAME = INSTRUCTIONS_PER_SECOND / FPS

local KEYPAD_MAP = {
        ['1'] = 0x1, ['2'] = 0x2, ['3'] = 0x3, ['4'] = 0xC,
        ['q'] = 0x4, ['w'] = 0x5, ['e'] = 0x6, ['r'] = 0xD,
        ['a'] = 0x7, ['s'] = 0x8, ['d'] = 0x9, ['f'] = 0xE,
        ['z'] = 0xA, ['x'] = 0x0, ['c'] = 0xB, ['v'] = 0xF
}

local emulator
local time_acc = 0

function love.load(args)
        love.window.setTitle("CHIP-8")
        love.window.setMode(WIDTH, HEIGHT)
        love.graphics.setBackgroundColor( BACKGROUND[1], BACKGROUND[2], BACKGROUND[3] )

        local path = assert(args[1], "No rom path was given")

        emulator = CHIP8:new()
        emulator:init()

        local rom_content = assert(love.filesystem.read(path))

        emulator:load(rom_content)
end

function love.update(dt)
        -- Must be 60Hz

        time_acc = time_acc + dt

        while time_acc >= FRAME_TIME do
                for i = 1, CYCLES_PER_FRAME, 1 do
                        emulator:cycle()
                end

                if emulator.delay > 0 then
                        emulator.delay = emulator.delay - 1
                end

                if emulator.sound > 0 then
                        -- Beep
                        emulator.sound = emulator.sound - 1
                end

                time_acc = time_acc - FRAME_TIME
        end
end

function love.draw()
        love.graphics.setColor( COLOR[1], COLOR[2], COLOR[3] )
        for y = 1, DISPLAY_HEIGHT, 1 do
                for x = 1, DISPLAY_WIDTH, 1 do
                        local pixel = emulator.display[DISPLAY_WIDTH * (y - 1) + x]

                        if pixel == 1 then
                                love.graphics.rectangle("fill", SCALE * (x - 1), SCALE * (y - 1), SCALE, SCALE)
                        end
                end
        end
end

function love.keypressed(key, scancode, isrepeat)
        local keypad = KEYPAD_MAP[scancode]

        if keypad then
                emulator.keyboard[keypad + 1] = 1
        end

        if scancode == "escape" then
                love.event.quit()
        end
end

function love.keyreleased(key, scancode)
        local keypad = KEYPAD_MAP[scancode]

        if keypad then
                emulator.keyboard[keypad + 1] = 0
        end
end

