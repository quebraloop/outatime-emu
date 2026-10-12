-- CHIP-8 core, implemented following Cowgod's "Chip-8 Technical Reference v1.0"

local chip8 = {}

local MEM_SIZE = 4 * 1024 -- 4KB
local NUM_GPR = 16 -- Number of general purpose registers (V0 to VF)
local NUM_STK_VAL = 16 -- Number of stack values
local NUM_KEY = 16 -- Number of keys in the keypad
local PROG_START_ADDR = 0x0200 -- Start address of the program
local FONT_START_ADDR = 0x0000 -- Start address of the font sprites
local BYTES_PER_SPRITE = 5 -- Number of bytes per sprite
DISPLAY_WIDTH = 64 -- Display width in pixels (global: used by main.lua)
DISPLAY_HEIGHT = 32 -- Display height in pixels (global: used by main.lua)

-- Font sprites for the hex digits 0-F (each one is 8x5 pixels)
local FONT_SPRITES = {
        [0x0] = { 0xF0, 0x90, 0x90, 0x90, 0xF0 }, -- 0
        [0x1] = { 0x20, 0x60, 0x20, 0x20, 0x70 }, -- 1
        [0x2] = { 0xF0, 0x10, 0xF0, 0x80, 0xF0 }, -- 2
        [0x3] = { 0xF0, 0x10, 0xF0, 0x10, 0xF0 }, -- 3
        [0x4] = { 0x90, 0x90, 0xF0, 0x10, 0x10 }, -- 4
        [0x5] = { 0xF0, 0x80, 0xF0, 0x10, 0xF0 }, -- 5
        [0x6] = { 0xF0, 0x80, 0xF0, 0x90, 0xF0 }, -- 6
        [0x7] = { 0xF0, 0x10, 0x20, 0x40, 0x40 }, -- 7
        [0x8] = { 0xF0, 0x90, 0xF0, 0x90, 0xF0 }, -- 8
        [0x9] = { 0xF0, 0x90, 0xF0, 0x10, 0xF0 }, -- 9
        [0xA] = { 0xF0, 0x90, 0xF0, 0x90, 0x90 }, -- A
        [0xB] = { 0xE0, 0x90, 0xE0, 0x90, 0xE0 }, -- B
        [0xC] = { 0xF0, 0x80, 0x80, 0x80, 0xF0 }, -- C
        [0xD] = { 0xE0, 0x90, 0x90, 0x90, 0xE0 }, -- D
        [0xE] = { 0xF0, 0x80, 0xF0, 0x80, 0xF0 }, -- E
        [0xF] = { 0xF0, 0x80, 0xF0, 0x80, 0x80 }  -- F
}

-- Note: Lua arrays start at index 1, so every access to mem, vreg, stack,
-- keyboard and display adds 1 to the CHIP-8 address/index (which is 0-based).

-- Helper function to return an array with N elements initialized with 0
local function narray(n)
        local mem = {}

        for i = 1, n, 1 do
                mem[i] = 0
        end

        return mem
end

function chip8:new()
        local o = {}
        self.__index = self
        setmetatable(o, self)

        local mem = narray(MEM_SIZE) -- 4KB of RAM
        local vreg = narray(NUM_GPR) -- V0 to VF (8-bit registers)
        local ireg = 0x0000 -- I register (16-bit)
        local delay = 0x00 -- Delay timer (8-bit)
        local sound = 0x00 -- Sound timer (8-bit)
        local pc = 0x0000 -- Program counter (16-bit)
        local sp = 0x00 -- Stack pointer (8-bit)
        local stack = narray(NUM_STK_VAL) -- 16 16-bit return addresses

        local keyboard = narray(NUM_KEY) -- 16-key keypad (1 = pressed, 0 = released)

        local display = narray(DISPLAY_WIDTH * DISPLAY_HEIGHT) -- 64x32-pixel monochrome display (1 = on, 0 = off)

        o.mem = mem
        o.vreg = vreg
        o.ireg = ireg
        o.delay = delay
        o.sound = sound
        o.pc = pc
        o.sp = sp
        o.stack = stack

        o.keyboard = keyboard

        o.display = display

        return o
end

function chip8:init()
        self.pc = PROG_START_ADDR

        -- Copying font sprites into memory
        for digit = 0x0, 0xF, 0x1 do
                local sprite = FONT_SPRITES[digit]

                for b = 1, BYTES_PER_SPRITE, 1 do
                        self.mem[FONT_START_ADDR + (digit * BYTES_PER_SPRITE) + b] = sprite[b]
                end
        end

        math.randomseed(os.time())
end

-- Load the ROM into memory, starting at PROG_START_ADDR
function chip8:load(content)
        local len = string.len(content)
        local offset = 1

        while len > 0 do
                self.mem[PROG_START_ADDR + offset] = string.byte(content, offset)

                len = len - 1
                offset = offset + 1
        end
end

-- Read the 2-byte opcode at PC (high byte first) and advance PC to the next one
function chip8:fetch()
        local instruction = bit.bor(bit.lshift(self.mem[self.pc + 1], 8), self.mem[self.pc + 2])
        self.pc = self.pc + 2

        return instruction
end

-- Split an opcode into its fields (id is the first nibble)
local function decode_instruction(opcode)
        local id = bit.band(bit.rshift(opcode, 12), 0x000F)
        local nnn = bit.band(opcode, 0x0FFF)
        local n = bit.band(opcode, 0x000F)
        local x = bit.band(bit.rshift(opcode, 8), 0x000F)
        local y = bit.band(bit.rshift(opcode, 4), 0x000F)
        local kk = bit.band(opcode, 0x00FF)

        return { id = id, nnn = nnn, n = n, x = x, y = y, kk = kk }
end

-- Clear the display.
local function instr_00e0(emulator, args)
        for i = 1, DISPLAY_WIDTH * DISPLAY_HEIGHT, 1 do
                emulator.display[i] = 0
        end
end

-- Return from a subroutine.
local function instr_00ee(emulator, args)
        emulator.pc = emulator.stack[emulator.sp]
        emulator.sp = emulator.sp - 1
end

-- Jump to location nnn.
local function instr_1nnn(emulator, args)
        local nnn = args.nnn
        emulator.pc = nnn
end

-- Call subroutine at nnn.
local function instr_2nnn(emulator, args)
        local nnn = args.nnn
        emulator.sp = emulator.sp + 1
        emulator.stack[emulator.sp] = emulator.pc
        emulator.pc = nnn
end

-- Skip next instruction if Vx = kk.
local function instr_3xkk(emulator, args)
        local x, kk = args.x, args.kk
        if emulator.vreg[x + 1] == kk then
                emulator.pc = emulator.pc + 2
        end
end

-- Skip next instruction if Vx != kk.
local function instr_4xkk(emulator, args)
        local x, kk = args.x, args.kk
        if emulator.vreg[x + 1] ~= kk then
                emulator.pc = emulator.pc + 2
        end
end

-- Skip next instruction if Vx = Vy.
local function instr_5xy0(emulator, args)
        local x, y = args.x, args.y
        if emulator.vreg[x + 1] == emulator.vreg[y + 1] then
                emulator.pc = emulator.pc + 2
        end
end

-- Set Vx = kk.
local function instr_6xkk(emulator, args)
        local x, kk = args.x, args.kk
        emulator.vreg[x + 1] = kk
end

-- Set Vx = Vx + kk (wraps around at 8 bits, VF is not changed).
local function instr_7xkk(emulator, args)
        local x, kk = args.x, args.kk
        emulator.vreg[x + 1] = bit.band(emulator.vreg[x + 1] + kk, 0xFF)
end

-- Set Vx = Vy.
local function instr_8xy0(emulator, args)
        local x, y = args.x, args.y
        emulator.vreg[x + 1] = emulator.vreg[y + 1]
end

-- Set Vx = Vx OR Vy.
local function instr_8xy1(emulator, args)
        local x, y = args.x, args.y
        emulator.vreg[x + 1] = bit.band(bit.bor(emulator.vreg[x + 1], emulator.vreg[y + 1]), 0xFF)
end

-- Set Vx = Vx AND Vy.
local function instr_8xy2(emulator, args)
        local x, y = args.x, args.y
        emulator.vreg[x + 1] = bit.band(bit.band(emulator.vreg[x + 1], emulator.vreg[y + 1]), 0xFF)
end

-- Set Vx = Vx XOR Vy.
local function instr_8xy3(emulator, args)
        local x, y = args.x, args.y
        emulator.vreg[x + 1] = bit.bxor(emulator.vreg[x + 1], emulator.vreg[y + 1])
end

-- Set Vx = Vx + Vy, set VF = carry (1 if the sum is greater than 255).
-- VF is written last so it is not overwritten when x = 0xF.
local function instr_8xy4(emulator, args)
        local x, y = args.x, args.y
        local sum = emulator.vreg[x + 1] + emulator.vreg[y + 1]
        emulator.vreg[x + 1] = bit.band(sum, 0xFF)
        emulator.vreg[0xF + 1] = sum > 255 and 1 or 0
end

-- Set Vx = Vx - Vy, set VF = NOT borrow (1 if Vx > Vy, as in Cowgod's guide).
local function instr_8xy5(emulator, args)
        local x, y = args.x, args.y
        local sub = emulator.vreg[x + 1] - emulator.vreg[y + 1]
        emulator.vreg[x + 1] = bit.band(sub, 0xFF)
        emulator.vreg[0xF + 1] = sub > 0 and 1 or 0
end

-- Set Vx = Vx SHR 1, set VF = least-significant bit of Vx (before the shift).
local function instr_8xy6(emulator, args)
        local x = args.x
        local lsb = bit.band(emulator.vreg[x + 1], 0x01)
        emulator.vreg[x + 1] = bit.rshift(emulator.vreg[x + 1], 1)
        emulator.vreg[0xF + 1] = lsb == 0x01 and 1 or 0
end

-- Set Vx = Vy - Vx, set VF = NOT borrow (1 if Vy > Vx, as in Cowgod's guide).
local function instr_8xy7(emulator, args)
        local x, y = args.x, args.y
        local sub = emulator.vreg[y + 1] - emulator.vreg[x + 1]
        emulator.vreg[x + 1] = bit.band(sub, 0xFF)
        emulator.vreg[0xF + 1] = sub > 0 and 1 or 0
end

-- Set Vx = Vx SHL 1, set VF = most-significant bit of Vx (before the shift).
local function instr_8xye(emulator, args)
        local x = args.x
        local msb = bit.band(bit.rshift(emulator.vreg[x + 1], 7), 0x01)
        emulator.vreg[x + 1] = bit.band(bit.lshift(emulator.vreg[x + 1], 1), 0xFF)
        emulator.vreg[0xF + 1] = msb == 0x01 and 1 or 0
end

-- Skip next instruction if Vx != Vy.
local function instr_9xy0(emulator, args)
        local x, y = args.x, args.y
        if emulator.vreg[x + 1] ~= emulator.vreg[y + 1] then
                emulator.pc = emulator.pc + 2
        end
end

-- Set I = nnn.
local function instr_annn(emulator, args)
        local nnn = args.nnn
        emulator.ireg = nnn
end

-- Jump to location nnn + V0.
local function instr_bnnn(emulator, args)
        local nnn = args.nnn
        emulator.pc = nnn + emulator.vreg[0 + 1]
end

-- Set Vx = random byte AND kk.
local function instr_cxkk(emulator, args)
        local x, kk = args.x, args.kk

        emulator.vreg[x + 1] = bit.band(math.random(0, 255), kk)
end

-- Display n-byte sprite starting at memory location I at (Vx, Vy), set VF = collision.
-- Pixels are XORed onto the screen and wrap around the edges.
local function instr_dxyn(emulator, args)
        local x, y, n = args.x, args.y, args.n
        local addr = emulator.ireg
        local vx = emulator.vreg[x + 1]
        local vy = emulator.vreg[y + 1]
        local total_bits = n * 8
        local erased = false

        emulator.vreg[0xF + 1] = 0

        for bit_count = 0, total_bits - 1, 1 do
                local row = math.floor(bit_count / 8)
                local col = bit_count % 8
                local px = (vx + col) % DISPLAY_WIDTH
                local py = (vy + row) % DISPLAY_HEIGHT

                local sprite_byte = emulator.mem[addr + row + 1]
                local sprite_pixel = bit.band(bit.rshift(sprite_byte, 7 - col), 0x01)

                if sprite_pixel == 1 then
                        local screen_pixel = emulator.display[DISPLAY_WIDTH * py + px + 1]
                        local new_pixel = bit.bxor(sprite_pixel, screen_pixel)

                        -- A pixel that was on and is now off counts as a collision
                        if new_pixel == 0 then
                                erased = true
                        end

                        emulator.display[DISPLAY_WIDTH * py + px + 1] = new_pixel
                end
        end

        if erased then emulator.vreg[0xF + 1] = 1 end
end

-- Skip next instruction if key with the value of Vx is pressed.
local function instr_ex9e(emulator, args)
        local x = args.x
        if emulator.keyboard[emulator.vreg[x + 1] + 1] == 1 then
                emulator.pc = emulator.pc + 2
        end
end

-- Skip next instruction if key with the value of Vx is not pressed.
local function instr_exa1(emulator, args)
        local x = args.x
        if emulator.keyboard[emulator.vreg[x + 1] + 1] == 0 then
                emulator.pc = emulator.pc + 2
        end
end

-- Set Vx = delay timer value.
local function instr_fx07(emulator, args)
        local x = args.x
        emulator.vreg[x + 1] = emulator.delay
end

-- Wait for a key press, store the value of the key in Vx.
local function instr_fx0a(emulator, args)
        local x = args.x
        local key_pressed = nil

        for i = 1, NUM_KEY, 1 do
                if emulator.keyboard[i] == 1 then
                        key_pressed = i - 1
                        break
                end
        end

        if key_pressed then
                emulator.vreg[x + 1] = key_pressed
        else
                -- No key pressed yet: go back so this instruction runs again
                emulator.pc = emulator.pc - 2
        end
end

-- Set delay timer = Vx.
local function instr_fx15(emulator, args)
        local x = args.x
        emulator.delay = emulator.vreg[x + 1]
end

-- Set sound timer = Vx.
local function instr_fx18(emulator, args)
        local x = args.x
        emulator.sound = emulator.vreg[x + 1]
end

-- Set I = I + Vx.
local function instr_fx1e(emulator, args)
        local x = args.x
        emulator.ireg = bit.band(emulator.ireg + emulator.vreg[x + 1], 0xFFFF)
end

-- Set I = location of sprite for digit Vx.
local function instr_fx29(emulator, args)
        local x = args.x
        local vx = emulator.vreg[x + 1]
        emulator.ireg = FONT_START_ADDR + vx * BYTES_PER_SPRITE
end

-- Store BCD representation of Vx in memory locations I, I+1, and I+2.
local function instr_fx33(emulator, args)
        local x = args.x
        local vx = emulator.vreg[x + 1]
        local i = emulator.ireg

        local hundreds = math.floor(vx / 100)
        local tens = math.floor(vx / 10) % 10
        local ones = vx % 10

        emulator.mem[i + 1] = hundreds
        emulator.mem[i + 2] = tens
        emulator.mem[i + 3] = ones
end

-- Store registers V0 through Vx in memory starting at location I.
local function instr_fx55(emulator, args)
        local x = args.x
        local addr = emulator.ireg

        for i = 0, x, 1 do
                local vi = emulator.vreg[i + 1]

                emulator.mem[addr + 1] = vi
                addr = addr + 1
        end
end

-- Read registers V0 through Vx from memory starting at location I.
local function instr_fx65(emulator, args)
        local x = args.x
        local addr = emulator.ireg

        for i = 0, x, 1 do
                emulator.vreg[i + 1] = emulator.mem[addr + 1]
                addr = addr + 1
        end
end

-- Opcodes starting with 0, selected by the last byte (kk)
local op_table_0 = {
        [0xE0] = instr_00e0,
        [0xEE] = instr_00ee
}

-- Opcodes starting with 8, selected by the last nibble (n)
local op_table_8 = {
        [0x0] = instr_8xy0,
        [0x1] = instr_8xy1,
        [0x2] = instr_8xy2,
        [0x3] = instr_8xy3,
        [0x4] = instr_8xy4,
        [0x5] = instr_8xy5,
        [0x6] = instr_8xy6,
        [0x7] = instr_8xy7,
        [0xE] = instr_8xye
}

-- Opcodes starting with E, selected by the last byte (kk)
local op_table_e = {
        [0x9E] = instr_ex9e,
        [0xA1] = instr_exa1
}

-- Opcodes starting with F, selected by the last byte (kk)
local op_table_f = {
        [0x07] = instr_fx07,
        [0x0A] = instr_fx0a,
        [0x15] = instr_fx15,
        [0x18] = instr_fx18,
        [0x1E] = instr_fx1e,
        [0x29] = instr_fx29,
        [0x33] = instr_fx33,
        [0x55] = instr_fx55,
        [0x65] = instr_fx65
}

-- Corresponding functions and sub-tables according to the primary opcode nibble
local op_table = {
        [0x1] = instr_1nnn,
        [0x2] = instr_2nnn,
        [0x3] = instr_3xkk,
        [0x4] = instr_4xkk,
        [0x5] = instr_5xy0,
        [0x6] = instr_6xkk,
        [0x7] = instr_7xkk,
        [0x9] = instr_9xy0,
        [0xA] = instr_annn,
        [0xB] = instr_bnnn,
        [0xC] = instr_cxkk,
        [0xD] = instr_dxyn,

        [0x0] = op_table_0,
        [0x8] = op_table_8,
        [0xE] = op_table_e,
        [0xF] = op_table_f
}

-- Find the function that implements the instruction, and return it with its arguments
function chip8:decode(instruction)
        local args = decode_instruction(instruction)
        local id = args.id
        local kk = args.kk
        local n = args.n
        local instr_func

        if id == 0x0 or id == 0xE or id == 0xF then
                instr_func = (op_table[id])[kk]
        elseif id == 0x8 then
                instr_func = (op_table[id])[n]
        else
                instr_func = op_table[id]
        end

        return { instr_func, args }
end

function chip8:execute(decoded)
        local instr = decoded[1]
        local args = decoded[2]

        instr(self, args)
end

-- Run one full CPU cycle: fetch, decode and execute
function chip8:cycle()
        self:execute(self:decode(self:fetch()))
end

return chip8

