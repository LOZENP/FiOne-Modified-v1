--[[
Lua bytecode deserializer
]]--

local compat = require('fione.compat')
local readers = require('fione.readers')
local stream = require('fione.stream')
local bit = compat.bit

-- Parse Lua function prototype
local function stm_lua_func(S, psrc)
	local proto = {}
	local src = stream.stm_lstring(S) or psrc

	proto.source = src

	S:s_int() -- line defined
	S:s_int() -- last line defined

	proto.num_upval = stream.stm_byte(S)
	proto.num_param = stream.stm_byte(S)
	proto.is_vararg = stream.stm_byte(S)
	proto.max_stack = stream.stm_byte(S)

	proto.code = stream.stm_inst_list(S)
	proto.const = stream.stm_const_list(S)
	proto.subs = stream.stm_sub_list(S, src, stm_lua_func)
	proto.lines = stream.stm_line_list(S)

	stream.stm_loc_list(S)
	stream.stm_upval_list(S)

	-- Post-process optimization
	proto.needs_arg = bit.band(proto.is_vararg, 0x5) == 0x5
	
	for _, v in ipairs(proto.code) do
		if v.is_K then
			v.const = proto.const[v.Bx + 1]
		else
			if v.is_KB then 
				v.const_B = proto.const[v.B - 0xFF] 
			end
			if v.is_KC then 
				v.const_C = proto.const[v.C - 0xFF] 
			end
		end
	end

	return proto
end

-- Convert bytecode to state
local function bc_to_state(src)
	local rdr_func
	local little, size_int, size_szt, size_ins, size_num, flag_int

	local S = {
		index = 1,
		source = src,
	}

	assert(stream.stm_string(S, 4) == '\27Lua', 'invalid Lua signature')
	assert(stream.stm_byte(S) == 0x51, 'invalid Lua version')
	assert(stream.stm_byte(S) == 0, 'invalid Lua format')

	little = stream.stm_byte(S) ~= 0
	size_int = stream.stm_byte(S)
	size_szt = stream.stm_byte(S)
	size_ins = stream.stm_byte(S)
	size_num = stream.stm_byte(S)
	flag_int = stream.stm_byte(S) ~= 0

	rdr_func = little and readers.rd_int_le or readers.rd_int_be
	S.s_int = stream.cst_int_rdr(size_int, rdr_func)
	S.s_szt = stream.cst_int_rdr(size_szt, rdr_func)
	S.s_ins = stream.cst_int_rdr(size_ins, rdr_func)

	if flag_int then
		S.s_num = stream.cst_int_rdr(size_num, rdr_func)
	elseif readers.float_types[size_num] then
		S.s_num = stream.cst_flt_rdr(
			size_num, 
			readers.float_types[size_num][little and 'little' or 'big']
		)
	else
		error('unsupported float size')
	end

	return stm_lua_func(S, '@virtual')
end

return {
	bc_to_state = bc_to_state,
}
