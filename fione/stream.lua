--[[
Stream reading utilities
]]--

local compat = require('fione.compat')
local opcodes = require('fione.opcodes')
local bit = compat.bit

local OPCODE_RM = opcodes.OPCODE_RM
local OPCODE_T = opcodes.OPCODE_T
local OPCODE_M = opcodes.OPCODE_M

-- Read single byte from stream
local function stm_byte(S)
	local idx = S.index
	local bt = string.byte(S.source, idx, idx)
	S.index = idx + 1
	return bt
end

-- Read string of specified length
local function stm_string(S, len)
	local pos = S.index + len
	local str = string.sub(S.source, S.index, pos - 1)
	S.index = pos
	return str
end

-- Read Lua string (length-prefixed)
local function stm_lstring(S)
	local len = S:s_szt()
	local str

	if len ~= 0 then 
		str = string.sub(stm_string(S, len), 1, -2) 
	end

	return str
end

-- Create integer reader
local function cst_int_rdr(len, func)
	return function(S)
		local pos = S.index + len
		local int = func(S.source, S.index, pos)
		S.index = pos
		return int
	end
end

-- Create float reader
local function cst_flt_rdr(len, func)
	return function(S)
		local flt = func(S.source, S.index)
		S.index = S.index + len
		return flt
	end
end

-- Read instruction list
local function stm_inst_list(S)
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do
		local ins = S:s_ins()
		local op = bit.band(ins, 0x3F)
		local args = OPCODE_T[op]
		local mode = OPCODE_M[op]
		local data = {
			value = ins, 
			op = OPCODE_RM[op], 
			A = bit.band(bit.rshift(ins, 6), 0xFF)
		}

		if args == 'ABC' then
			data.B = bit.band(bit.rshift(ins, 23), 0x1FF)
			data.C = bit.band(bit.rshift(ins, 14), 0x1FF)
			data.is_KB = mode.b == 'OpArgK' and data.B > 0xFF
			data.is_KC = mode.c == 'OpArgK' and data.C > 0xFF

			if op == 10 then -- NEWTABLE array size
				local e = bit.band(bit.rshift(data.B, 3), 31)
				if e == 0 then
					data.const = data.B
				else
					data.const = bit.lshift(bit.band(data.B, 7) + 8, e - 1)
				end
			end
		elseif args == 'ABx' then
			data.Bx = bit.band(bit.rshift(ins, 14), 0x3FFFF)
			data.is_K = mode.b == 'OpArgK'
		elseif args == 'AsBx' then
			data.sBx = bit.band(bit.rshift(ins, 14), 0x3FFFF) - 131071
		end

		list[i] = data
	end

	return list
end

-- Read constant list
local function stm_const_list(S)
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do
		local tt = stm_byte(S)
		local k

		if tt == 1 then
			k = stm_byte(S) ~= 0
		elseif tt == 3 then
			k = S:s_num()
		elseif tt == 4 then
			k = stm_lstring(S)
		end

		list[i] = k
	end

	return list
end

-- Read sub-function list
local function stm_sub_list(S, src, stm_lua_func)
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do
		list[i] = stm_lua_func(S, src)
	end

	return list
end

-- Read line number list
local function stm_line_list(S)
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do 
		list[i] = S:s_int() 
	end

	return list
end

-- Read local variable list
local function stm_loc_list(S)
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do 
		list[i] = {
			varname = stm_lstring(S), 
			startpc = S:s_int(), 
			endpc = S:s_int()
		} 
	end

	return list
end

-- Read upvalue list
local function stm_upval_list(S)
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do 
		list[i] = stm_lstring(S) 
	end

	return list
end

return {
	stm_byte = stm_byte,
	stm_string = stm_string,
	stm_lstring = stm_lstring,
	cst_int_rdr = cst_int_rdr,
	cst_flt_rdr = cst_flt_rdr,
	stm_inst_list = stm_inst_list,
	stm_const_list = stm_const_list,
	stm_sub_list = stm_sub_list,
	stm_line_list = stm_line_list,
	stm_loc_list = stm_loc_list,
	stm_upval_list = stm_upval_list,
}
