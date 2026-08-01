--[[
+------+
| 通用 |
+------+
--]]
-- 读取2da
local kitList_2DA = EEex_Resource_Load2DA('KITLIST')
local alignmnt_2DA = EEex_Resource_Load2DA('ALIGNMNT')
local weapProf_2DA = EEex_Resource_Load2DA('WEAPPROF')
local abilityClassReqs_2DA = EEex_Resource_Load2DA('ABCLASRQ')

-- 建立kitId映射表
local kitIdToKitCode = {}	-- 映射到 kitCode 的表
local kitIdToClassId = {}	-- 映射到所属 classId 的表
local kitIdToUnusable = {}	-- 映射到所属 classId 的表
for rowIndex = 1, kitList_2DA.m_nSizeY - 1 do
	local kitCode = EEex_Resource_GetAt2DAPoint(kitList_2DA, 0, rowIndex)
	local classId = tonumber(EEex_Resource_GetAt2DAPoint(kitList_2DA, 7, rowIndex))
	local kitId = tonumber(EEex_Resource_GetAt2DAPoint(kitList_2DA, 8, rowIndex))
	local unusable = tonumber(EEex_Resource_GetAt2DAPoint(kitList_2DA, 6, rowIndex))
	
	if kitId then
		kitIdToKitCode[kitId] = kitCode
		kitIdToClassId[kitId] = classId
		kitIdToUnusable[kitId] = unusable
	end
end
kitIdToKitCode[0x00004015] = "LATHANDER"	-- 手动修复 0x00004015 重名错误

-- 建立proficiencyId映射表
local profIdToProCode = {}	-- 映射到熟练度名称的表
for rowIndex = 0, weapProf_2DA.m_nSizeY - 1 do
	local proficiencyId = tonumber(weapProf_2DA:getAtPoint(0, rowIndex))
	local proficiencyCode = weapProf_2DA:getRowLabel(rowIndex)

	if proficiencyId then
		profIdToProCode[proficiencyId] = proficiencyCode
	end
end

-- 判断阵营是否符合宗派限制
local function ST_IsKitAllowedAlignment(kitId, alignmentId)
	-- 无宗派不增加额外限制
	if kitId == 0 or kitId == 0x4000 then
		return true
	end
	
	local kitCode = kitIdToKitCode[kitId]
	
	local alignmentMap = {
		[0x11] = "L_G", [0x12] = "L_N", [0x13] = "L_E",
		[0x21] = "N_G", [0x22] = "N_N", [0x23] = "N_E",
		[0x31] = "C_G", [0x32] = "C_N", [0x33] = "C_E",
	}
	
	local alignmentCode = alignmentMap[alignmentId]
	
	local isAllowedValue = tonumber(EEex_Resource_GetAt2DALabels(alignmnt_2DA, alignmentCode, kitCode))
	if isAllowedValue == 0 then
		print(alignmentCode .. ' not allowed from ' ..  kitId .. '(' .. kitCode .. ')')
	end

	return isAllowedValue == 1
end

-- 决定武器熟练度上限
local function ST_ProficiencyMax(sprite, proficiencyId, proficiencyMax)
	if proficiencyMax == 0 then
		return proficiencyMax
	end
	
	local allKitIds = ST_GetAllKitIds(sprite)
	
	local classIdToClassCode = {
		[1]  = "MAGE",
		[2]  = "FIGHTER",
		[3]  = "CLERIC",
		[4]  = "THIEF",
		[5]  = "BARD",
		[6]  = "PALADIN",
		[11] = "DRUID",
		[12] = "RANGER",
		[19] = "SORCERER",
		[20] = "MONK",
		[21] = "SHAMAN",
	}
	
	local proficiencyCode = profIdToProCode[proficiencyId]
	
	local toOverride = false
	local profMaxOverride = 0
	
	for i = 1, #allKitIds do
		local kitId = allKitIds[i]
		local kitCode = kitIdToKitCode[kitId]
		local profMaxKit = tonumber(EEex_Resource_GetAt2DALabels(weapProf_2DA, kitCode, proficiencyCode))
		
		local classId = kitIdToClassId[kitId]
		local classCode = classIdToClassCode[classId]
		local profMaxClass = tonumber(EEex_Resource_GetAt2DALabels(weapProf_2DA, classCode, proficiencyCode))
		
		if profMaxKit ~= profMaxClass then
			toOverride = true
			if profMaxKit == 0 then
				return 0
			else
				profMaxOverride = math.max(profMaxOverride, profMaxKit)
			end
		end
	end
	
	if toOverride then
		proficiencyMax = profMaxOverride
	end
	
	return proficiencyMax
end

--[[
+-----------+
| CLAB 系统 |
+-----------+
--]]
-- 应用CLAB时所使用的 kitId
function ST_RegisterHook_CLABGetKit()
	EEex_HookBeforeCallWithLabels(0x14034773c, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(80)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)], rcx
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)], rdx
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)], r11
				mov r11d, dword ptr [r15 + 0x48]
			]]},
			EEex_GenLuaCall("ST_Hook_CLABGetKit", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r11 #ENDL", {rspOffset}} end,
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rdx #ENDL", {rspOffset}} end,
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r8 #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),
			{[[
				call_error:
				
				no_error:
				
				mov r11, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)]
				mov rdx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)]
				mov rcx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]
				mov r8, qword ptr [rsp + 56]
				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end

function ST_Hook_CLABGetKit(spriteId, classId, kitId)
	local sprite = EEex_GameObject_Get(spriteId)
	
	if kitIdToClassId[kitId] == classId then
		return kitId
	end
	local exKitId = ST_GetExKitId(sprite, 1)
	if kitIdToClassId[exKitId] == classId then
		return exKitId
	end
	exKitId = ST_GetExKitId(sprite, 2)
	if kitIdToClassId[exKitId] == classId then
		return exKitId
	end
	
	return kitId
end

--[[
+--------------+
| 角色面板显示 |
+--------------+
--]]
-- 角色面板读取到的kit
function ST_RegisterHook_CharPanelGetKit()
	EEex_HookAfterCallWithLabels(0x14023E7A7, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(64)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)], rax
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)], r10
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)], r11
				mov eax, dword ptr ds:[r13+0x48]
				movzx r10d, byte ptr ss:[rsp+#LAST_FRAME_TOP(0x22)]
				mov r11d, dword ptr ss:[rsp+#LAST_FRAME_TOP(0x30)]
			]]},
			EEex_GenLuaCall("ST_Hook_CharPanelGetKit", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rax #ENDL", {rspOffset}} end,
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r10 #ENDL", {rspOffset}} end,
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r11 #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),
			{[[
				call_error:
				
				no_error:
				
				mov dword ptr ss:[rsp+#LAST_FRAME_TOP(0x30)], eax
				mov r11, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)]
				mov r10, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)]
				mov rax, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]
				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end

function ST_Hook_CharPanelGetKit(spriteId, classId, kitId)
	local sprite = EEex_GameObject_Get(spriteId)
	if kitIdToClassId[kitId] == classId then
		return kitId
	end
	local exKitId = ST_GetExKitId(sprite, 1)
	if kitIdToClassId[exKitId] == classId then
		return exKitId
	end
	exKitId = ST_GetExKitId(sprite, 2)
	if kitIdToClassId[exKitId] == classId then
		return exKitId
	end
	
	return kitId
end

--[[
+----------------------------+
| 角色创建/转职 职业选择阶段 |
+----------------------------+
--]]
-- 建立兼职 classId 对应的 singleClassId 表
local charRegClassIdTable = {
	[7] = {		-- 7 FIGHTER_MAGE
		[1] = 2, -- FIGHTER
		[2] = 1, -- MAGE
	},
	[8] = {		-- 8 FIGHTER_CLERIC
		[1] = 2, -- FIGHTER
		[2] = 3, -- CLERIC
	},
	[9] = {		-- 9 FIGHTER_THIEF
		[1] = 2, -- FIGHTER
		[2] = 4, -- THIEF
	},
	[10] = {	-- 10 FIGHTER_MAGE_THIEF
		[1] = 2, -- FIGHTER
		[2] = 1, -- MAGE
		[3] = 4, -- THIEF
	},
	[13] = {	-- 13 MAGE_THIEF
		[1] = 1, -- MAGE
		[2] = 4, -- THIEF
	},
	[14] = {	-- 14 CLERIC_MAGE
		[1] = 3, -- CLERIC
		[2] = 1, -- MAGE
	},
	[15] = {	-- 15 CLERIC_THIEF
		[1] = 3, -- CLERIC
		[2] = 4, -- THIEF
	},
	[16] = {	-- 16 FIGHTER_DRUID
		[1] = 2,  -- FIGHTER
		[2] = 11, -- DRUID
	},
	[17] = {	-- 17 FIGHTER_MAGE_CLERIC
		[1] = 2, -- FIGHTER
		[2] = 1, -- MAGE
		[3] = 3, -- CLERIC
	},
	[18] = {	-- 18 CLERIC_RANGER
		[1] = 3,  -- CLERIC
		[2] = 12, -- RANGER
	},
}

-- 角色创建 选择职业
function ST_RegisterHook_CharGenClassDone()
	EEex_HookAfterCallWithLabels(0x1402b8c7a, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(48)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)], r10
				mov r10d, dword ptr [r14+0x770]
			]]},
			EEex_GenLuaCall("ST_Hook_CharGenClassDone", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r10 #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),
			{[[
				call_error:
				
				no_error:

				mov r10, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]
				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end

local CharGenMode = nil	-- 1 角色创建; 2 转职

local charGenSprite = nil	-- 角色创建阶段的 sprite
local charGenClassId = 0	-- 角色创建阶段的 classId
local charRegSingleClassNum = 0		-- 当前选择的兼职总共包含的职业数量
local charRegSingleClassIndex = 1	-- 当前界面对应的单职业在兼职中的序号

local charGenKitIdList = {}	-- 当前已选择的kit表。表的第一级是单职业的 singleClassId，第二级是该职业的 kitId

function ST_Hook_CharGenClassDone(spriteId)
	local sprite = EEex_GameObject_Get(spriteId)	
	charGenSprite = sprite
	
	local classId = sprite.m_typeAI.m_Class
	charGenClassId = classId
	
	CharGenMode = 1	-- 角色创建
	
	charGenKitIdList = {}
	charRegSingleClassIndex = 1
	if charRegClassIdTable[classId] then
		charRegSingleClassNum = #charRegClassIdTable[classId]
		for _, singleClassId in pairs(charRegClassIdTable[classId]) do
			charGenKitIdList[singleClassId] = 0x4000
		end
	else
		charRegSingleClassNum = 1
	end
	
	ST_SetExKitId(sprite, 1, 0)
	ST_SetExKitId(sprite, 2, 0)
end

-- 转职 选择职业
function ST_RegisterHook_DualClassDone()
	EEex_HookBeforeRestoreWithLabels(0x1402B9EB2, 0, 0, 16, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX,
			EEex_HookIntegrityWatchdogRegister.RDX,
			EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9,
			EEex_HookIntegrityWatchdogRegister.R10,
			EEex_HookIntegrityWatchdogRegister.R11,
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(48)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)], r10
				mov r10d, dword ptr [r14+770h]
			]]},

			EEex_GenLuaCall("ST_Hook_DualClassDone", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r10 #ENDL", {rspOffset}} end,
				},
			}),

			{[[
				call_error:

				no_error:
				; 使用引擎原函数生成 chargen.kit
				mov rdx, qword ptr ss:[rsp+#LAST_FRAME_TOP(40h)]
				mov rcx, r14

				#ALIGN
				call 0x1402C55D0
				#ALIGN_END

				; 转职主流程直接进入技能阶段
				; 自定义宗派面板作为 modal 覆盖在上面
				mov dword ptr [r14+768h], 19h

				mov rcx, ]]},
				{EEex_WriteStringCache("ST_DUALCLASS_KIT")},
			{[[
				#ALIGN
				call 0x1403DA620
				#ALIGN_END

				mov r10, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]
				#DESTROY_SHADOW_SPACE

				#MANUAL_HOOK_EXIT(0)
				jmp 0x1402BA336
			]]},
		})
	)
end

local charGenSingleClassId = nil
function ST_Hook_DualClassDone(spriteId)
	local sprite = EEex_GameObject_Get(currentID)
	charGenSprite = sprite
	
	local oldClassId = sprite.m_typeAI.m_Class
	local newClassId = chargen.class[currentChargenClass].id
	charGenSingleClassId = newClassId
	
	CharGenMode = 2	-- 转职
	
	charGenKitIdList = {}
	charGenKitIdList[oldClassId] = sprite.m_derivedStats.m_nKit
	charGenKitIdList[charGenSingleClassId] = 0x4000
	
	ST_SetExKitId(sprite, 1, 0)
	
	Infinity_PushMenu("ST_DUALCLASS_KIT")
end

--[[
+----------------------------+
| 角色创建/转职 宗派准备阶段 |
+----------------------------+
--]]
-- 生成 chargen.kit 时依据的 classId
function ST_RegisterHook_CharGenKitListClassId()
	EEex_HookBeforeCallWithLabels(0x1402c5664, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(96)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)],  rcx
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)], rdx
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)], r8
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-32)], r9

			]]},
			EEex_GenLuaCall("ST_Hook_CharGenKitListClassId", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r8 #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),
			{[[
				call_error:
				
				no_error:

				mov rcx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]
				mov rdx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)]
				mov r8,  rax
				mov r9,  qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-32)]
				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end

function ST_Hook_CharGenKitListClassId(classId)
	if CharGenMode == 1 and charRegClassIdTable[classId] then
		charGenSingleClassId = charRegClassIdTable[classId][charRegSingleClassIndex]
		charRegSingleClassIndex = charRegSingleClassIndex + 1
		return charGenSingleClassId
	elseif CharGenMode == 2 and charGenSingleClassId then
		return charGenSingleClassId
	end
	
	return classId
end

-- 决定是否打开kitList
function ST_RegisterHook_CharGenCheckEnterKit()
	EEex_HookBeforeRestoreWithLabels(0x1402b8c8c, 0, 10, 10, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(48)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)], r10
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)], r11
				mov r10d, dword ptr [r14+770h]
			]]},
			EEex_GenLuaCall("ST_Hook_CharGenCheckEnterKit", {
			}),
			{[[
				call_error:
				
				no_error:
				
				mov r11, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)]
				mov r10, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]

				#DESTROY_SHADOW_SPACE
				jmp 0x1402b8c96
			]]},
		})
	)
end

function ST_Hook_CharGenCheckEnterKit()
	currentChargenKit = 1	-- 打开kitL时显示选择第一个（基础职业）
end

--[[
+----------------------------+
| 角色创建/转职 宗派选择阶段 |
+----------------------------+
--]]
--
function ST_RegisterHook_CharGenSelectKit()
	EEex_HookBeforeRestoreWithLabels(0x1402BB1E6, 0, 14, 14, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(112)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)],  rax
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)], rcx
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)], rdx
			]]},
			EEex_GenLuaCall("ST_Hook_CharGenSelectKit", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rcx #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Boolean,
			}),
			{[[
				call_error:
				
				no_error:

				mov rdx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)]
				mov rcx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)]				
				mov rax, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]
				cmp qword ptr [rsp + 56], 0x0
				#DESTROY_SHADOW_SPACE
				jnz 0x1402bb1f4	; 宗派数量大于1时跳过写入当前kitId的步骤
			]]},
		})
	)
end

local pendingKitId = 0
local kitCount = 0
function ST_Hook_CharGenSelectKit(kitId)
	if not charGenSingleClassId then	-- 创建纯职角色时跳过此函数
		return false
	end
	
	local sprite = charGenSprite
	
	charGenKitIdList[charGenSingleClassId] = kitId	-- 将kitId记录在表格对应职业处
	pendingKitId = kitId	-- 将kitId记录为待处理
	
	-- 统计总共选择了多少个宗派
	kitCount = 0
	for _, kitId in pairs(charGenKitIdList) do
		if kitId ~= 0x4000 then
			kitCount = kitCount + 1
		end
	end
	
	return kitCount > 1
end

-- 已处理的单职业数量少于兼职所包含的单职业数量时，返回到生成 kitList 阶段	0X1402B8CC9
function ST_RegisterHook_CharGenKit()
	EEex_HookBeforeCallWithLabels(0X1402B8CE1, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(96)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)],  rcx
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)], rdx
			]]},
			EEex_GenLuaCall("ST_Hook_CharGenKit", {
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),
			{[[
				call_error:
				
				no_error:
				mov rdx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)]
				mov rcx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]
				#DESTROY_SHADOW_SPACE

				test eax, eax
				jnz continue_kit_selection

				jmp #L(return)

				continue_kit_selection:
				jmp 0x1402B8C7F
			]]},
		})
	)
end

function ST_Hook_CharGenKit()
	local sprite = charGenSprite
	
	if kitCount > 1 then
		ST_SetExKitId(sprite, kitCount - 1, pendingKitId)
		
		if charGenKitIdList[1] then		
			local kitIdToSpecializationId = {
				[0x00000040] = 1, -- Abjurer
				[0x00000080] = 2, -- Conjurer
				[0x00000100] = 3, -- Diviner
				[0x00000200] = 4, -- Enchanter
				[0x00000400] = 5, -- Illusionist
				[0x00000800] = 6, -- Invoker
				[0x00001000] = 7, -- Necromancer
				[0x00002000] = 8, -- Transmuter
				[0x00004000] = 9, -- Generalist
				[0x80000000] = 9, -- Generalist
			}

			local specializationId = charGenKitIdList[1] or 0
		end
	end
	
	local function ST_ResetLocalVariables()	-- 重置文件级变量
		CharGenMode = nil
		charGenSingleClassId = nil
	end
	
	if not charRegClassIdTable[charGenClassId] then	-- 创建非兼职角色
		return 0	-- 正常流程
	end

	if charRegSingleClassIndex <= #charRegClassIdTable[charGenClassId] then	-- 创建兼职角色，未选择完所有职业
		return 1	-- 回到宗派列表
	else																	-- 已选择完所有职业
		ST_ResetLocalVariables()
		return 0	-- 正常流程
	end
end

-- 转职宗派列表额外过滤
function ST_DualClassFilterKitList()
	if not chargen.kit then
		return
	end
	
	local sprite = EEex_GameObject_Get(currentID)
	
	local alignmentId = sprite.m_typeAI.m_Alignment
	local str = sprite.m_baseStats.m_STRBase
	local dex = sprite.m_baseStats.m_DEXBase
	local con = sprite.m_baseStats.m_CONBase
	local int = sprite.m_baseStats.m_INTBase
	local wis = sprite.m_baseStats.m_WISBase
	local chr = sprite.m_baseStats.m_CHRBase
	
	for index = #chargen.kit, 2, -1 do 	-- 跳过第一项
		local entry = chargen.kit[index]
		local kitId = tonumber(EEex_Resource_GetAt2DAPoint(kitList_2DA, 8, entry.id))
		local kitCode = kitIdToKitCode[kitId]
		
		local minStr = tonumber(EEex_Resource_GetAt2DALabels(abilityClassReqs_2DA, 'MIN_STR', kitCode))
		local minDex = tonumber(EEex_Resource_GetAt2DALabels(abilityClassReqs_2DA, 'MIN_DEX', kitCode))
		local minCon = tonumber(EEex_Resource_GetAt2DALabels(abilityClassReqs_2DA, 'MIN_CON', kitCode))
		local minInt = tonumber(EEex_Resource_GetAt2DALabels(abilityClassReqs_2DA, 'MIN_INT', kitCode))
		local minWis = tonumber(EEex_Resource_GetAt2DALabels(abilityClassReqs_2DA, 'MIN_WIS', kitCode))
		local minChr = tonumber(EEex_Resource_GetAt2DALabels(abilityClassReqs_2DA, 'MIN_CHR', kitCode))
		
		if not ST_IsKitAllowedAlignment(kitId, alignmentId) then
			table.remove(chargen.kit, index)
		elseif str < minStr or dex < minDex or con < minCon or int < minInt or wis < minWis or chr < minChr then
			table.remove(chargen.kit, index)
		end
	end
end

-- 转职选择宗派
function ST_DualClassSelectKit(kitRowLabel)
	local sprite = EEex_GameObject_Get(currentID)

	local kitId = tonumber(EEex_Resource_GetAt2DAPoint(kitList_2DA, 8, chargen.kit[currentChargenKit].id))
	if not kitId then
		print(
			"[ST] Unknown KITLIST row label: "
			.. tostring(kitRowLabel)
		)
		return
	end

	if sprite.m_derivedStats.m_nKit == 0x4000 then
		sprite.m_derivedStats.m_nKit = kitId
	else
		ST_SetExKitId(sprite, 1, kitId)
	end
end
--[[
+-----------------------+
| 角色创建 阵营选择阶段 |
+-----------------------+
--]]
function ST_RegisterHook_CharGenAlignment()
	EEex_HookBeforeCallWithLabels(0x1402BCFEA, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(96)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)],  rcx
				mov eax, dword ptr [r15+0x48]
			]]},
			EEex_GenLuaCall("ST_Hook_CharGenAlignment", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rax #ENDL", {rspOffset}} end,
				},
			}),
			{[[
				call_error:
				
				no_error:
				mov rcx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]
				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end


function ST_Hook_CharGenAlignment()
	local alignmentMap = {
		[0x11] = "L_G", [0x12] = "L_N", [0x13] = "L_E",
		[0x21] = "N_G", [0x22] = "N_N", [0x23] = "N_E",
		[0x31] = "C_G", [0x32] = "C_N", [0x33] = "C_E",
	}

	for index = #chargen.alignment, 1, -1 do
		local alignmentEntry = chargen.alignment[index]
		local alignmentId = alignmentEntry.id
	end
	
	for index = #chargen.alignment, 1, -1 do
		local alignmentEntry = chargen.alignment[index]
		local alignmentId = alignmentEntry.id

		local isAllowed = true
		
		for _, kitId in pairs(charGenKitIdList) do
			isAllowed = isAllowed and ST_IsKitAllowedAlignment(kitId, alignmentId)
		end
		
		if not isAllowed then
			table.remove(chargen.alignment, index)
		end
	end
end

--[[
+------------------------+
| 角色创建/升级 技能阶段 |
+------------------------+
--]]
-- 技能界面的最大熟练度，仅决定是否显示为可升级
function ST_RegisterHook_ProficiencyUIMax()
	EEex_HookBeforeRestoreWithLabels(0x1402C75C1, 0, 8, 8, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RCX, EEex_HookIntegrityWatchdogRegister.RDX,
			EEex_HookIntegrityWatchdogRegister.R8, EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10,
			EEex_HookIntegrityWatchdogRegister.R11,
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(96)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)],  rax
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)], rcx
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)], rdx
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-32)], r8
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-40)], r9
				mov r8d, dword ptr ss:[rsp+#LAST_FRAME_TOP(0x78)]
			]]},
			EEex_GenLuaCall("ST_Hook_ProficiencyMax", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rsi #ENDL", {rspOffset}} end,
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r8 #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),
			{[[
				call_error:
				
				no_error:
				
				mov dword ptr ss:[rsp+#LAST_FRAME_TOP(0x78)], eax
				mov r9,  qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-40)]
				mov r8,  qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-32)]
				mov rdx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)]
				mov rcx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)]
				mov rax, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]
				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end

-- 实际最大熟练度
function ST_RegisterHook_ProficiencyActualMax()
	EEex_HookBeforeRestoreWithLabels(0x1402BDC31, 0, 8, 8, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RCX, EEex_HookIntegrityWatchdogRegister.RDX,
			EEex_HookIntegrityWatchdogRegister.R8, EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10,
			EEex_HookIntegrityWatchdogRegister.R11,
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(80)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)],  rax
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)], rcx
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)], rdx
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-32)], r8
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-40)], r9
				movsxd rax, dword ptr ss:[rbp-0x9]
			]]},

			EEex_GenLuaCall("ST_Hook_ProficiencyMax", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rsi #ENDL", {rspOffset}} end,
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rax #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),

			{[[
				call_error:

				no_error:
				mov dword ptr ss:[rbp-0x9], eax
				mov r9,  qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-40)]
				mov r8,  qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-32)]
				mov rdx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-24)]
				mov rcx, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)]
				mov rax, qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]
				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end

function ST_Hook_ProficiencyMax(proficiencyId, proficiencyMax)
	local sprite = EEex_GameObject_Get(currentID) or charGenSprite
	newProficiencyMax = ST_ProficiencyMax(sprite, proficiencyId, proficiencyMax)
	
    for i = 1, #ST_ProficiencyMaxListeners do
        local listener = ST_ProficiencyMaxListeners[i]
        local newProficiencyMax = listener(sprite, proficiencyId, proficiencyMax)
    end
	
	return newProficiencyMax
end

ST_ProficiencyMaxListeners = ST_ProficiencyMaxListeners or {}
function ST_AddProficiencyMaxListener(func)
    table.insert(ST_ProficiencyMaxListeners, func)
end

-- 初始盗贼技能点数
function ST_RegisterHook_CharGenSkillStartPoints_At(address)
	EEex_HookAfterCallWithLabels(address, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(48)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)],  rax
			]]},
			EEex_GenLuaCall("ST_Hook_CharGenSkillStartPoints", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rax  #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),
			{[[
				call_error:
				
				no_error:
				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end

function ST_RegisterHook_CharGenSkillStartPoints()
	for _, address in ipairs({
		0x1402C20D9,	-- 高于1级新建角色
		0x1402C244C,	-- 1级新建角色
	}) do
		ST_RegisterHook_CharGenSkillStartPoints_At(address)
	end
end

function ST_Hook_CharGenSkillStartPoints(startPoints)
	local sprite = EEex_GameObject_Get(currentID) or charGenSprite
	local allKitIds = ST_GetAllKitIds(sprite)
	
	local thiefSkill_2da = EEex_Resource_Load2DA("THIEFSKL")
	
	for i = 1, #allKitIds do
		local kitId = allKitIds[i]
		local kitCode = kitIdToKitCode[kitId]
		local tempPoints = tonumber(EEex_Resource_GetAt2DALabels(thiefSkill_2da, 'START_POINTS', kitCode))
		if tempPoints ~= 0 then
			return tempPoints
		end
	end
	
	return startPoints
end

-- 升级获得的盗贼技能点数
function ST_RegisterHook_CharGenSkillLevelPoints()
	EEex_HookAfterCallWithLabels(0x1402C234E, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(48)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)],  rax
			]]},
			EEex_GenLuaCall("ST_Hook_CharGenSkillLevelPoints", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rax  #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),
			{[[
				call_error:
				
				no_error:
				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end

function ST_Hook_CharGenSkillLevelPoints(levelPoints)
	local sprite = EEex_GameObject_Get(currentID) or charGenSprite
	local allKitIds = ST_GetAllKitIds(sprite)
	
	local thiefSkill_2da = EEex_Resource_Load2DA("THIEFSKL")
	
	for i = 1, #allKitIds do
		local kitId = allKitIds[i]
		local kitCode = kitIdToKitCode[kitId]
		local tempPoints = tonumber(EEex_Resource_GetAt2DALabels(thiefSkill_2da, 'LEVEL_POINTS', kitCode))
		if tempPoints ~= 0 then
			return tempPoints
		end
	end
	
	return levelPoints
end

--[[
+-------------------+
| 角色创建 属性阶段 |
+-------------------+
--]]
-- 属性最小值
function ST_RegisterHook_CharGenAbilityBaseMinimum()
    EEex_HookBeforeRestoreWithLabels(0x1402BEB8E, 0, 8, 8, {
        {"hook_integrity_watchdog_ignore_registers", {
            EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RCX, EEex_HookIntegrityWatchdogRegister.RDX,
            EEex_HookIntegrityWatchdogRegister.R8, EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10,
            EEex_HookIntegrityWatchdogRegister.R11,
        }}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(48)
				; [rbp+58h] = 当前属性字段地址
				; r14       = sprite
				mov r10, qword ptr ss:[rbp+58h]
				sub r10, r14

				; [rbp+38h] = 原版合并后的最终职业最低要求
				movsxd r11, dword ptr ss:[rbp+38h]
			]]},

			EEex_GenLuaCall("ST_Hook_CharGenAbilityBaseMinimum", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r10 #ENDL", {rspOffset}} end,
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r11 #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),

			{[[
				call_error:
				
				no_error:
				
				mov dword ptr ss:[rbp+38h], eax
				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end

function ST_Hook_CharGenAbilityBaseMinimum(abilityOffset, minimum)
	local sprite = charGenSprite
	if not sprite then
		return minimum
	end
	
	local ST_AbilityOffsetToCode = {
		[0x790] = 'MIN_STR',
		[0x794] = 'MIN_DEX',
		[0x795] = 'MIN_CON',
		[0x792] = 'MIN_INT',
		[0x793] = 'MIN_WIS',
		[0x796] = 'MIN_CHR',
	}
	local abilityCode = ST_AbilityOffsetToCode[abilityOffset]
	
	local allKitIds = ST_GetAllKitIds(sprite)
	
	for i = 1, #allKitIds do
		local kitId = allKitIds[i]
		local kitCode = kitIdToKitCode[kitId]
		minimum = math.max(minimum, tonumber(EEex_Resource_GetAt2DALabels(abilityClassReqs_2DA, abilityCode, kitCode)))
	end
	
    return minimum
end

--[[
+-------------+
| Match KitId |
+-------------+
--]]
-- 物品及法术可用性
function ST_RegisterHook_UnusableGetKitId()
	EEex_HookBeforeRestoreWithLabels(0x14039C8D4, 0, 14, 14, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RDX, EEex_HookIntegrityWatchdogRegister.R8,
			EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10, EEex_HookIntegrityWatchdogRegister.R11
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(64)
				mov eax, dword ptr [rcx+48h]
			]]},
			EEex_GenLuaCall("ST_Hook_UnusableGetKitId", {
				["args"] = {
					function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rax  #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Number,
			}),
			{[[
				call_error:
				
				no_error:
				
				#DESTROY_SHADOW_SPACE
				jmp 0x14039C96C
			]]},
		})
	)
end

function ST_Hook_UnusableGetKitId(spriteId)
	local sprite = EEex_GameObject_Get(spriteId)
	local allKitIds = ST_GetAllKitIds(sprite)
	
	local unusable = 0
	for i = 1, #allKitIds do
		local kitId = allKitIds[i]
		local kitUnusable = kitIdToUnusable[kitId]
		unusable = EEex_BOr(unusable, kitUnusable)
	end
	
	return unusable
end

-- opcode match kitId
local function ST_RegisterHook_OpcodeMatchKitId_At(
	address,
	spriteRegister,
	effectRegister,
	valueRegister,
	jumpType
)
	local returnDelay = jumpType == "jne_failure" and 22 or 24

	EEex_HookBeforeRestoreWithLabels(address, 0, 0, returnDelay, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RCX, EEex_HookIntegrityWatchdogRegister.RDX,
			EEex_HookIntegrityWatchdogRegister.R8, EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10,
			EEex_HookIntegrityWatchdogRegister.R11,
		}}},
		EEex_FlattenTable({
			{
				[[
					#MAKE_SHADOW_SPACE(56)
					mov eax,dword ptr [#$(1)+0x48]
					mov edx,dword ptr [#$(2)+0x1C]
				]],
				{spriteRegister, effectRegister},
			},

			EEex_GenLuaCall("ST_Hook_OpcodeMatchKitId", {
				["args"] = {
					function(rspOffset) return { "mov qword ptr ss:[rsp+#$(1)],rax #ENDL", {rspOffset}} end,
					function(rspOffset) return { "mov qword ptr ss:[rsp+#$(1)],rdx #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Boolean,
			}),

			jumpType == "je_success"
				and {
					[[
						call_error:

						no_error:
						mov #$(1),dword ptr [#$(2)+1Ch]
						xor eax,1
						test eax,eax
						#DESTROY_SHADOW_SPACE
					]],
					{valueRegister, effectRegister},
				}
				or {
					[[
						call_error:

						no_error:
						cmp eax,1
						#DESTROY_SHADOW_SPACE
					]],
				},
		})
	)
end

function ST_RegisterHook_OpcodeMatchKitId()
	ST_RegisterHook_OpcodeMatchKitId_At(
		0x1401A6AC5,
		"rsi",
		"rbx",
		"edx",
		"je_success"
	)

	ST_RegisterHook_OpcodeMatchKitId_At(
		0x1401ACB45,
		"rsi",
		"rbx",
		"edx",
		"je_success"
	)

	ST_RegisterHook_OpcodeMatchKitId_At(
		0x1401B1AB6,
		"rsi",
		"rbx",
		"edx",
		"je_success"
	)

	ST_RegisterHook_OpcodeMatchKitId_At(
		0x1401B5DE7,
		"rbx",
		"rdi",
		"edx",
		"je_success"
	)

	ST_RegisterHook_OpcodeMatchKitId_At(
		0x1401B5FAC,
		"rdi",
		"rbx",
		"ecx",
		"je_success"
	)

	ST_RegisterHook_OpcodeMatchKitId_At(
		0x1401CDDD1,
		"rbx",
		"rdi",
		nil,
		"jne_failure"
	)
end

function ST_Hook_OpcodeMatchKitId(spriteId, kitId)
	local sprite = EEex_GameObject_Get(spriteId)
	local allKitIds = ST_GetAllKitIds(sprite)
	for i = 1, #allKitIds do
		if kitId == allKitIds[i] then
			return true
		end
	end
	
	return false
end

-- SPLPROT match kitId
function ST_RegisterHook_SPLPROTMatchKitId()
	EEex_HookBeforeCallWithLabels(0x14024A8AE, {
		{"manual_hook_integrity_exit", true},
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RCX, EEex_HookIntegrityWatchdogRegister.RDX,
			EEex_HookIntegrityWatchdogRegister.R8, EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10,
			EEex_HookIntegrityWatchdogRegister.R11,
		}},
	}, EEex_FlattenTable({
		{[[
			cmp r13w, 152
			jne return

			cmp ebp, 1
			je custom_compare

			cmp ebp, 5
			jne return

			custom_compare:
			#MAKE_SHADOW_SPACE(56)

			mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)],  r8
			mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)], r9

			mov eax, dword ptr [rdi+0x48]
			mov r8d, r15d
			mov r9d, ebp
		]]},

		EEex_GenLuaCall("ST_Hook_SPLPROTMatchKitId", {
			["args"] = {
				function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], rax  #ENDL", {rspOffset}} end,
				function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r8  #ENDL", {rspOffset}} end,
				function(rspOffset) return {"mov qword ptr ss:[rsp+#$(1)], r9  #ENDL", {rspOffset}} end,
			},
			["returnType"] = EEex_LuaCallReturnType.Boolean,
		}),

		{[[
			call_error:

			no_error:
			mov r9,  qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-16)]
			mov r8,  qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)]			
			#DESTROY_SHADOW_SPACE
			#MANUAL_HOOK_EXIT(0)
			jmp 0x14024A8C3
		]]},
	}))
end

function ST_Hook_SPLPROTMatchKitId(spriteId, kitId, relation)
	local sprite = EEex_GameObject_Get(spriteId)
	if sprite == nil then
		return false
	end

	local allKitIds = ST_GetAllKitIds(sprite)

	if relation == 1 then
		for i = 1, #allKitIds do
			if allKitIds[i] == kitId then
				return true
			end
		end
		return false
	end

	if relation == 5 then
		for i = 1, #allKitIds do
			if allKitIds[i] == kitId then
				return false
			end
		end
		return true
	end

	return false
end

-- 脚本 Kit(O:Object*,I:Kit*KIT)
function ST_RegisterHook_TriggerMatchKitId()
	EEex_HookBeforeRestoreWithLabels(0x14015A983, 0, 0, 30, {
		{"hook_integrity_watchdog_ignore_registers", {
			EEex_HookIntegrityWatchdogRegister.RAX, EEex_HookIntegrityWatchdogRegister.RCX, EEex_HookIntegrityWatchdogRegister.RDX,
			EEex_HookIntegrityWatchdogRegister.R8, EEex_HookIntegrityWatchdogRegister.R9, EEex_HookIntegrityWatchdogRegister.R10,
			EEex_HookIntegrityWatchdogRegister.R11,
		}}},
		EEex_FlattenTable({
			{[[
				#MAKE_SHADOW_SPACE(56)
				mov qword ptr ss:[rsp+#SHADOW_SPACE_BOTTOM(-8)], rax

				mov eax, dword ptr [rax+0x48]	; spriteId
				mov edx, dword ptr [rbp+0x354]	; requested kitId
			]]},
			EEex_GenLuaCall("ST_Hook_TriggerMatchKitId", {
				["args"] = {
					function(rspOffset) return { "mov qword ptr ss:[rsp+#$(1)], rax #ENDL", {rspOffset}} end,
					function(rspOffset) return { "mov qword ptr ss:[rsp+#$(1)], rdx #ENDL", {rspOffset}} end,
				},
				["returnType"] = EEex_LuaCallReturnType.Boolean,
			}),
			{[[
				call_error:

				no_error:
				mov qword ptr ss:[rsp+#LAST_FRAME_TOP(58h)],r13

				xor eax,1
				test eax,eax

				#DESTROY_SHADOW_SPACE
			]]},
		})
	)
end

function ST_Hook_TriggerMatchKitId(spriteId, kitId)
	local sprite = EEex_GameObject_Get(spriteId)
	if sprite == nil then
		return false
	end
	
	local allKitIds = ST_GetAllKitIds(sprite)

	for i = 1, #allKitIds do
		if kitId == allKitIds[i] then
			return true
		end
	end

	return false
end

--[[
+----------+
| 注册hook |
+----------+
--]]
EEex_DisableCodeProtection()

ST_RegisterHook_CLABGetKit()

ST_RegisterHook_CharPanelGetKit()

ST_RegisterHook_CharGenClassDone()
ST_RegisterHook_DualClassDone()
ST_RegisterHook_CharGenKitListClassId()
ST_RegisterHook_CharGenCheckEnterKit()

ST_RegisterHook_CharGenSelectKit()
ST_RegisterHook_CharGenKit()

ST_RegisterHook_CharGenAlignment()

ST_RegisterHook_CharGenAbilityBaseMinimum()

ST_RegisterHook_ProficiencyUIMax()
ST_RegisterHook_ProficiencyActualMax()

ST_RegisterHook_CharGenSkillStartPoints()
ST_RegisterHook_CharGenSkillLevelPoints()

ST_RegisterHook_UnusableGetKitId()
ST_RegisterHook_OpcodeMatchKitId()
ST_RegisterHook_SPLPROTMatchKitId()
ST_RegisterHook_TriggerMatchKitId()

EEex_EnableCodeProtection()

