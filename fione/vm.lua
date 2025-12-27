--[[
Lua 5.1 virtual machine implementation
]]--

local opcodes = require('fione.opcodes')
local OPCODE_RM = opcodes.OPCODE_RM
local FIELDS_PER_FLUSH = opcodes.FIELDS_PER_FLUSH

-- Close upvalues at or above index
local function close_lua_upvalues(list, index)
	for i, uv in pairs(list) do
		if uv.index >= index then
			uv.value = uv.store[uv.index]
			uv.store = uv
			uv.index = 'value'
			list[i] = nil
		end
	end
end

-- Open or reuse upvalue
local function open_lua_upvalue(list, index, memory)
	local prev = list[index]

	if not prev then
		prev = {index = index, store = memory}
		list[index] = prev
	end

	return prev
end

-- Error handler
local function on_lua_error(failed, err)
	local src = failed.source
	local line = failed.lines[failed.pc - 1]
	error(string.format('%s:%i: %s', src, line, err), 0)
end

-- Main VM execution loop
local function run_lua_func(state, env, upvals)
	local code = state.code
	local subs = state.subs
	local vararg = state.vararg
	local top_index = -1
	local open_list = {}
	local memory = state.memory
	local pc = state.pc

	while true do
		local inst = code[pc]
		local op = inst.op
		pc = pc + 1

		if op < 18 then
			if op < 8 then
				if op < 3 then
					if op < 1 then --[[ LOADNIL ]]
						for i = inst.A, inst.B do memory[i] = nil end
					elseif op > 1 then --[[ GETUPVAL ]]
						local uv = upvals[inst.B]
						memory[inst.A] = uv.store[uv.index]
					else --[[ ADD ]]
						local lhs = inst.is_KB and inst.const_B or memory[inst.B]
						local rhs = inst.is_KC and inst.const_C or memory[inst.C]
						memory[inst.A] = lhs + rhs
					end
				elseif op > 3 then
					if op < 6 then
						if op > 4 then --[[ SELF ]]
							local A = inst.A
							local B = inst.B
							local index = inst.is_KC and inst.const_C or memory[inst.C]
							memory[A + 1] = memory[B]
							memory[A] = memory[B][index]
						else --[[ GETGLOBAL ]]
							memory[inst.A] = env[inst.const]
						end
					elseif op > 6 then --[[ GETTABLE ]]
						local index = inst.is_KC and inst.const_C or memory[inst.C]
						memory[inst.A] = memory[inst.B][index]
					else --[[ SUB ]]
						local lhs = inst.is_KB and inst.const_B or memory[inst.B]
						local rhs = inst.is_KC and inst.const_C or memory[inst.C]
						memory[inst.A] = lhs - rhs
					end
				else --[[ MOVE ]]
					memory[inst.A] = memory[inst.B]
				end
			elseif op > 8 then
				if op < 13 then
					if op < 10 then --[[ SETGLOBAL ]]
						env[inst.const] = memory[inst.A]
					elseif op > 10 then
						if op < 12 then --[[ CALL ]]
							local A = inst.A
							local B = inst.B
							local C = inst.C
							local params = B == 0 and (top_index - A) or (B - 1)
							local ret_list = table.pack(memory[A](table.unpack(memory, A + 1, A + params)))
							local ret_num = ret_list.n
							if C == 0 then
								top_index = A + ret_num - 1
							else
								ret_num = C - 1
							end
							table.move(ret_list, 1, ret_num, A, memory)
						else --[[ SETUPVAL ]]
							local uv = upvals[inst.B]
							uv.store[uv.index] = memory[inst.A]
						end
					else --[[ MUL ]]
						local lhs = inst.is_KB and inst.const_B or memory[inst.B]
						local rhs = inst.is_KC and inst.const_C or memory[inst.C]
						memory[inst.A] = lhs * rhs
					end
				elseif op > 13 then
					if op < 16 then
						if op > 14 then --[[ TAILCALL ]]
							local A = inst.A
							local B = inst.B
							local params = B == 0 and (top_index - A) or (B - 1)
							close_lua_upvalues(open_list, 0)
							return memory[A](table.unpack(memory, A + 1, A + params))
						else --[[ SETTABLE ]]
							local index = inst.is_KB and inst.const_B or memory[inst.B]
							local value = inst.is_KC and inst.const_C or memory[inst.C]
							memory[inst.A][index] = value
						end
					elseif op > 16 then --[[ NEWTABLE ]]
						memory[inst.A] = table.create(inst.const)
					else --[[ DIV ]]
						local lhs = inst.is_KB and inst.const_B or memory[inst.B]
						local rhs = inst.is_KC and inst.const_C or memory[inst.C]
						memory[inst.A] = lhs / rhs
					end
				else --[[ LOADK ]]
					memory[inst.A] = inst.const
				end
			else --[[ FORLOOP ]]
				local A = inst.A
				local step = memory[A + 2]
				local index = memory[A] + step
				local limit = memory[A + 1]
				local loops = (step >= 0 and index <= limit) or (index >= limit)
				if loops then
					memory[A] = index
					memory[A + 3] = index
					pc = pc + inst.sBx
				end
			end
		elseif op > 18 then
			if op < 28 then
				if op < 23 then
					if op < 20 then --[[ LEN ]]
						memory[inst.A] = #memory[inst.B]
					elseif op > 20 then
						if op < 22 then --[[ RETURN ]]
							local A = inst.A
							local B = inst.B
							local len = B == 0 and (top_index - A + 1) or (B - 1)
							close_lua_upvalues(open_list, 0)
							return table.unpack(memory, A, A + len - 1)
						else --[[ CONCAT ]]
							local B, C = inst.B, inst.C
							local success, str = pcall(table.concat, memory, "", B, C)
							if not success then
								str = memory[B]
								for i = B + 1, C do str = str .. memory[i] end
							end
							memory[inst.A] = str
						end
					else --[[ MOD ]]
						local lhs = inst.is_KB and inst.const_B or memory[inst.B]
						local rhs = inst.is_KC and inst.const_C or memory[inst.C]
						memory[inst.A] = lhs % rhs
					end
				elseif op > 23 then
					if op < 26 then
						if op > 24 then --[[ CLOSE ]]
							close_lua_upvalues(open_list, inst.A)
						else --[[ EQ ]]
							local lhs = inst.is_KB and inst.const_B or memory[inst.B]
							local rhs = inst.is_KC and inst.const_C or memory[inst.C]
							if (lhs == rhs) == (inst.A ~= 0) then 
								pc = pc + code[pc].sBx 
							end
							pc = pc + 1
						end
					elseif op > 26 then --[[ LT ]]
						local lhs = inst.is_KB and inst.const_B or memory[inst.B]
						local rhs = inst.is_KC and inst.const_C or memory[inst.C]
						if (lhs < rhs) == (inst.A ~= 0) then 
							pc = pc + code[pc].sBx 
						end
						pc = pc + 1
					else --[[ POW ]]
						local lhs = inst.is_KB and inst.const_B or memory[inst.B]
						local rhs = inst.is_KC and inst.const_C or memory[inst.C]
						memory[inst.A] = lhs ^ rhs
					end
				else --[[ LOADBOOL ]]
					memory[inst.A] = inst.B ~= 0
					if inst.C ~= 0 then pc = pc + 1 end
				end
			elseif op > 28 then
				if op < 33 then
					if op < 30 then --[[ LE ]]
						local lhs = inst.is_KB and inst.const_B or memory[inst.B]
						local rhs = inst.is_KC and inst.const_C or memory[inst.C]
						if (lhs <= rhs) == (inst.A ~= 0) then 
							pc = pc + code[pc].sBx 
						end
						pc = pc + 1
					elseif op > 30 then
						if op < 32 then --[[ CLOSURE ]]
							local sub = subs[inst.Bx + 1]
							local nups = sub.num_upval
							local uvlist
							if nups ~= 0 then
								uvlist = table.create(nups - 1)
								for i = 1, nups do
									local pseudo = code[pc + i - 1]
									if pseudo.op == OPCODE_RM[0] then
										uvlist[i - 1] = open_lua_upvalue(open_list, pseudo.B, memory)
									elseif pseudo.op == OPCODE_RM[4] then
										uvlist[i - 1] = upvals[pseudo.B]
									end
								end
								pc = pc + nups
							end
							memory[inst.A] = lua_wrap_state(sub, env, uvlist)
						else --[[ TESTSET ]]
							local A = inst.A
							local B = inst.B
							if (not memory[B]) ~= (inst.C ~= 0) then
								memory[A] = memory[B]
								pc = pc + code[pc].sBx
							end
							pc = pc + 1
						end
					else --[[ UNM ]]
						memory[inst.A] = -memory[inst.B]
					end
				elseif op > 33 then
					if op < 36 then
						if op > 34 then --[[ VARARG ]]
							local A = inst.A
							local len = inst.B
							if len == 0 then
								len = vararg.len
								top_index = A + len - 1
							end
							table.move(vararg.list, 1, len, A, memory)
						else --[[ FORPREP ]]
							local A = inst.A
							local init = assert(tonumber(memory[A]), '`for` initial value must be a number')
							local limit = assert(tonumber(memory[A + 1]), '`for` limit must be a number')
							local step = assert(tonumber(memory[A + 2]), '`for` step must be a number')
							memory[A] = init - step
							memory[A + 1] = limit
							memory[A + 2] = step
							pc = pc + inst.sBx
						end
					elseif op > 36 then --[[ SETLIST ]]
						local A = inst.A
						local C = inst.C
						local len = inst.B
						local tab = memory[A]
						local offset
						if len == 0 then len = top_index - A end
						if C == 0 then
							C = inst[pc].value
							pc = pc + 1
						end
						offset = (C - 1) * FIELDS_PER_FLUSH
						table.move(memory, A + 1, A + len, offset + 1, tab)
					else --[[ NOT ]]
						memory[inst.A] = not memory[inst.B]
					end
				else --[[ TEST ]]
					if (not memory[inst.A]) ~= (inst.C ~= 0) then 
						pc = pc + code[pc].sBx 
					end
					pc = pc + 1
				end
			else --[[ TFORLOOP ]]
				local A = inst.A
				local base = A + 3
				local vals = {memory[A](memory[A + 1], memory[A + 2])}
				table.move(vals, 1, inst.C, base, memory)
				if memory[base] ~= nil then
					memory[A + 2] = memory[base]
					pc = pc + code[pc].sBx
				end
				pc = pc + 1
			end
		else --[[ JMP ]]
			pc = pc + inst.sBx
		end

		state.pc = pc
	end
end

-- Wrap state into callable function
function lua_wrap_state(proto, env, upval)
	return function(...)
		local passed = table.pack(...)
		local memory = table.create(proto.max_stack)
		local vararg = {len = 0, list = {}}

		table.move(passed, 1, proto.num_param, 0, memory)

		if proto.num_param < passed.n then
			local start = proto.num_param + 1
			local len = passed.n - proto.num_param
			vararg.len = len
			table.move(passed, start, start + len - 1, 1, vararg.list)
		end

		if proto.needs_arg then
			memory[proto.num_param] = {
				n = vararg.len, 
				table.unpack(vararg.list, 1, vararg.len)
			}
		end

		local state = {
			vararg = vararg, 
			memory = memory, 
			code = proto.code, 
			subs = proto.subs, 
			pc = 1
		}

		local result = table.pack(pcall(run_lua_func, state, env, upval))

		if result[1] then
			return table.unpack(result, 2, result.n)
		else
			local failed = {
				pc = state.pc, 
				source = proto.source, 
				lines = proto.lines
			}
			on_lua_error(failed, result[2])
		end
	end
end

return {
	wrap_state = lua_wrap_state,
}
