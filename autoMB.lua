--[[
Copyright © 2020, Ekrividus
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of autoMB nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Ekrividus BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[
autoMB will cast elements for magic bursts automatically
job/level is pulled from game and appropriate elements are used

single bursting only for now, but double may me introduced later

]]
addon.version = '1.3.4'
addon.name = 'autoMB'
addon.author = 'Ekrividus'
addon.desc = 'autoMB will cast elements for magic bursts automatically.'
addon.link = 'https://www.ashitaxi.com/'
-- _addon.commands = {'autoMB','amb'}
-- _addon.lastUpdate = '1/12/2023'
-- _addon.windower = '4'

-- require 'tables'
-- require 'strings'
-- require 'logger'

-- res = require('resources')
-- config = require('config')
-- chat = require('chat') -- Windower's chat
-- packets = require('packets')

local ashita_chat = require('chat')
local settings_manager = require('settings')
local common = require('common') -- Assuming this provides table/string utils, or we add them
local resource_manager = AshitaCore:GetResourceManager()
if resource_manager == nil then
    error("autoMB: Failed to get AshitaCore Resource Manager!")
end
local packet_manager = AshitaCore:GetPacketManager()
if packet_manager == nil then
    error("autoMB: Failed to get AshitaCore Packet Manager!")
end

local weather_memory_pointer = nil
-- local struct = require('struct') -- Assuming Ashita's environment provides struct or it's manually added.
                                 -- If not, this will need to be handled, possibly with manual byte functions.
                                 -- For now, proceeding as if struct.unpack is available.
local struct; -- Declare struct
pcall(function() struct = require('struct') end); -- Safely require struct
if not struct then
    print(addon.name .. ": Error - 'struct' library not found. Packet parsing will fail. Please ensure 'struct.lua' is available.")
    -- Optionally, could implement basic manual unpackers here for critical fields if struct is truly unavailable.
end


-- Helper function (can be moved to common.lua or replaced if available)
local function table_contains(tbl, val)
    for _, value in ipairs(tbl) do
        if value == val then
            return true
        end
    end
    return false
end

local weather_id_to_element_map = {
    [0] = 'Clear', [1] = 'Sunshine', [2] = 'Clouds', [3] = 'Fog',
    [4] = 'Fire', [5] = 'Fire', [6] = 'Water', [7] = 'Water',
    [8] = 'Earth', [9] = 'Earth', [10] = 'Wind', [11] = 'Wind',
    [12] = 'Ice', [13] = 'Ice', [14] = 'Thunder', [15] = 'Thunder',
    [16] = 'Light', [17] = 'Light', [18] = 'Dark', [19] = 'Dark',
}

local vanadiel_day_to_element_map = {
    [0] = 'Fire',    -- Firesday
    [1] = 'Earth',   -- Earthsday
    [2] = 'Water',   -- Watersday
    [3] = 'Wind',    -- Windsday
    [4] = 'Ice',     -- Iceday
    [5] = 'Thunder', -- Lightningday
    [6] = 'Light',   -- Lightsday
    [7] = 'Dark'     -- Darksday
}

-- Helper function for string splitting
local function string_split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

local defaults = {}
defaults.frequency = 10 -- How many times per second to update skillchain effects
defaults.show_skillchain = false -- Whether or not to show skillchain name
defaults.show_elements = false -- Whether or not to show skillchain element info
defaults.show_bonus_elements = false -- Whether or not to show Storm/Weather/Day elements
defaults.show_spell = false -- Whether or not to post the spell selection to chat
defaults.check_day = false -- Whether or not to use day bonus spell
defaults.check_weather = false -- Whether or not to use weather bonus, probably turn on if storms are being used
defaults.useAOE = false -- Whether or not to use AOE elements
defaults.cast_delay = 0.25 -- Delay from when skillchain occurs to when first spell is cast
defaults.double_burst = false -- Not implemented yet
defaults.double_burst_delay = 1 -- Time from when first spell starts casting to when second spell starts casting
defaults.mp = 100 -- Don't burst if it will leave you below this mark
defaults.cast_type = 'spell' -- Type of MB spell|jutsu|helix|ga|ja|ra
defaults.cast_tier = 1 -- What tier should we try to cast
defaults.step_down = 0 -- Step down a tier for double bursts (0: Never, 1: If target changed, 2: Always)
defaults.gearswap = false -- Tell gearswap when we're bursting
defaults.change_target = true -- Swap targets automatically for MBs
defaults.cast_range = 22 -- Maximum range for target to be recognized

-- Newly added setting
defaults.disable_on_zone = false -- Disable when zoning

local settings = settings_manager.load(defaults)
-- Add missing settings
settings.cast_range  = settings.cast_range or 21

local skillchains = {
	[288] = {id=288,english='Light',elements={'Light','Thunder','Wind','Fire'}},
	[289] = {id=289,english='Darkness',elements={'Dark','Ice','Water','Earth'}},
	[290] = {id=290,english='Gravitation',elements={'Dark','Earth'}},
	[291] = {id=291,english='Fragmentation',elements={'Thunder','Wind'}},
	[292] = {id=292,english='Distortion',elements={'Ice','Water'}},
	[293] = {id=293,english='Fusion',elements={'Light','Fire'}},
	[294] = {id=294,english='Compression',elements={'Dark'}},
	[295] = {id=295,english='Liquefaction',elements={'Fire'}},
	[296] = {id=296,english='Induration',elements={'Ice'}},
	[297] = {id=297,english='Reverberation',elements={'Water'}},
	[298] = {id=298,english='Transfixion', elements={'Light'}},
	[299] = {id=299,english='Scission',elements={'Earth'}},
	[300] = {id=300,english='Detonation',elements={'Wind'}},
	[301] = {id=301,english='Impaction',elements={'Thunder'}},
	[767] = {id=767,english='Radiance',elements={'Light','Thunder','Wind','Fire'}},
	[768] = {id=768,english='Umbra',elements={'Dark','Ice','Water','Earth'}},
	[769] = {id=769,english='Radiance',elements={'Light','Thunder','Wind','Fire'}},
	[770] = {id=770,english='Umbra',elements={'Dark','Ice','Water','Earth'}},
}

local magic_tiers = {
	[1] = {suffix=''},
	[2] = {suffix='II'},
	[3] = {suffix='III'},
	[4] = {suffix='IV'},
	[5] = {suffix='V'},
	[6] = {suffix='VI'}
}

local jutsu_tiers = {
    [1] = {suffix='Ichi'},
    [2] = {suffix='Ni'},
    [3] = {suffix='San'}
}

local max_tiers = {
	spell=6,
	helix=2,
	ga=3,
	ja=1,
	ra=3,
	jutsu=3,
	white=3,
	holy=2,
}

local spell_priorities = {
	[1] = {element='Thunder'},
	[2] = {element='Ice'},
	[3] = {element='Wind'},
	[4] = {element='Fire'},
	[5] = {element='Water'},
	[6] = {element='Earth'},
	[7] = {element='Dark'},
	[8] = {element='Light'}
}

local storms = {
	[178] = {id=178,name='Firestorm',weather=4},
	[179] = {id=179,name='Hailstorm',weather=12},
	[180] = {id=180,name='Windstorm',weather=10},
	[181] = {id=181,name='Sandstorm',weather=8},
	[182] = {id=182,name='Thunderstorm',weather=14},
	[183] = {id=183,name='Rainstorm',weather=6},
	[184] = {id=184,name='Aurorastorm',weather=16},
	[185] = {id=185,name='Voidstorm',weather=18},
	[589] = {id=589,name='Firestorm',weather=5},
	[590] = {id=590,name='Hailstorm',weather=13},
	[591] = {id=591,name='Windstorm',weather=11},
	[592] = {id=592,name='Sandstorm',weather=9},
	[593] = {id=593,name='Thunderstorm',weather=15},
	[594] = {id=594,name='Rainstorm',weather=7},
	[595] = {id=595,name='Aurorastorm',weather=17},
	[596] = {id=596,name='Voidstorm',weather=19}
}

local elements = {
	['Light'] = {spell=nil,helix='Luminohelix',ga=nil,ja=nil,ra=nil,jutsu=nil,white='Banish',holy="Holy",drain=nil},
	['Dark'] = {spell=nil,helix='Noctohelix',ga=nil,ja=nil,ra=nil,jutsu=nil,white=nil,holy=nil,drain="Drain"},
	['Thunder'] = {spell='Thunder',helix='Ionohelix',ga='Thundaga',ja='Thundaja',ra='Thundara',jutsu='Raiton',white=nil,holy=nil,drain=nil},
	['Ice'] = {spell='Blizzard',helix='Cryohelix',ga='Blizzaga',ja='Blizzaja',ra='Blizzara',jutsu='Hyoton',white=nil,holy=nil,drain=nil},
	['Fire'] = {spell='Fire',helix='Pyrohelix',ga='Firaga',ja='Firaja',ra='Fira',jutsu='Katon',white=nil,holy=nil,drain=nil},
	['Wind'] = {spell='Aero',helix='Anemohelix',ga='Aeroga',ja='Aeroja',ra='Aerora',jutsu='Huton',white=nil,holy=nil,drain=nil},
	['Water'] = {spell='Water',helix='Hydrohelix',ga='Waterga',ja='Waterja',ra='Watera',jutsu='Suiton',white=nil,holy=nil,drain=nil},
	['Earth'] = {spell='Stone',helix='Geohelix',ga='Stonega',ja='Stoneja',ra='Stonera',jutsu='Doton',white=nil,holy=nil,drain=nil},
}

local cast_types = {'spell', 'helix', 'ga', 'ja', 'ra', 'jutsu', 'white', 'holy', 'drain'}
local spell_users = {'BLM', 'RDM', 'DRK', 'GEO'}
local jutsu_users = {'NIN'}
local helix_users = {'SCH'}

local active = false
local frequency = 1/settings.frequency
local last_skillchain = nil

local player = nil

local last_packet_time = 0
local min_packet_time = 0.05

local finish_act = {2,3,5}
local start_act = {7,8,9,12}
local is_busy = 0
local is_casting = false
local is_bursting = false

local last_check_time = os.clock()
local ability_delay = 1.3
local after_cast_delay = 1.6
local failed_cast_delay = 2

local debug = false -- Show debug output

function message(text, to_log) 
	if (text == nil or #text < 1) then
		return
	end

	if (to_log) then
		print(addon.name .. ': ' .. text) -- Log to console
	else
		print(ashita_chat.prefix(addon.name):append(ashita_chat.message(text)))
	end
end

function debug_message(text, to_log) 
	if (debug == false or text == nil or #text < 1) then
		return
	end

	if (to_log) then
		print(addon.name .. '(debug): ' .. text) -- Log to console
	else
		print(ashita_chat.prefix(addon.name .. '(debug)'):append(ashita_chat.message(text)))
	end
end

function show_help()
	message('Usage:\nautoMB on|off - turn auto magic bursting on or off\nautoMB show on|off - display messages about skillchains|magic bursts')
	show_status()
end

function show_status()
	message('Auto Bursts: \t\t'..(active and 'On' or 'Off'))
	message('Auto Burst Range: \t'..(settings.cast_range)..'y')
	message('Magic Burst Type: \t'..settings.cast_type..' Tier: \t'..(settings.cast_tier))
	message('Min MP: \t\t'..settings.mp)
	message('Cast Delay: '..settings.cast_delay..' seconds')
	message('Double Burst: '..(settings.double_burst and ('On'..' delay '..settings.double_burst_delay..' seconds') or 'Off'))
	message('Check Elements - Day: '..(settings.check_day and 'On' or 'Off')..' Weather: '..(settings.check_weather and 'On' or 'Off'))
	message('Show Skillchain: \t\t'..(settings.show_skillchain and 'On' or 'Off'))
	message('Show Skillchain Elements: \t'..(settings.show_elements and 'On' or 'Off'))
	message('Show Day|Weather Elements: \t'..(settings.show_bonus_elements and 'On' or 'Off'))
	message('Show Spell: \t'..(settings.show_spell and 'On' or 'Off'))
end

function buff_active(buff_id)
    local current_player_entity = ashita.ffxi.get_player_entity()
    if not current_player_entity then return false end
    if table_contains(current_player_entity.buffs, buff_id) then
        return true
    end
    return false
end

function disabled()
    if (buff_active(0)) then -- KO
        return true
    elseif (buff_active(2)) then -- Sleep
        return true
    elseif (buff_active(6)) then -- Silence
        return true
    elseif (buff_active(7)) then -- Petrification
        return true
    elseif (buff_active(10)) then -- Stun
        return true
    elseif (buff_active(14) or buff_active(17)) then -- Charm
        return true
    elseif (buff_active(28)) then -- Terrorize
        return true
    elseif (buff_active(29)) then -- Mute
        return true
    elseif (buff_active(193)) then -- Lullaby
        return true
    elseif (buff_active(262)) then -- Omerta
        return true
    end
    return false
end

function low_mp(spell_name_arg)
    local sp = resource_manager:GetSpellByName(spell_name_arg, 'en')
	-- TODO: Verify Ashita spell object property for MP cost (e.g., sp.cost_mp).
	if (sp == nil) then
		return false
	end

    player = ashita.ffxi.get_player_entity()
    if not player then return true end

	local mp_cost = sp.cost_mp -- Changed from sp.mp_cost
    if (mp_cost == nil or (player.vitals.mp - mp_cost <= settings.mp)) then
        return true
    end

	return false
end

function check_recast(spell_name_arg)
    local recasts = ashita.ffxi.get_player_recasts()
    local spell_obj = resource_manager:GetSpellByName(spell_name_arg, 'en')
	-- TODO: Verify Ashita spell object property for 'id' is compatible with recast table key.
	if (spell_obj == nil) then
		return 0
	end

	local recast = recasts[spell_obj.id]

    return recast
end

function get_bonus_elements()
    local world_info = ashita.ffxi.get_world_info()
    local day_element_name = 'UnknownDay'
    if world_info then
        local vana_day_id = world_info.day_of_week -- Ashita's day_of_week is 0 (Fire) to 7 (Dark)
        day_element_name = vanadiel_day_to_element_map[vana_day_id] or 'UnknownDay('..tostring(vana_day_id)..')'
    else
        day_element_name = 'ErrorGettingDay'
    end

    local current_weather_id_from_memory = GetCurrentWeatherId()
    local final_weather_id_for_element = current_weather_id_from_memory

    local current_player_entity = ashita.ffxi.get_player_entity()
    if current_player_entity and current_player_entity.buffs and #current_player_entity.buffs > 0 then
        for _, buff_id in ipairs(current_player_entity.buffs) do
            for _, storm_info in pairs(storms) do
                if storm_info.id == buff_id then
                    final_weather_id_for_element = storm_info.weather
                    break
                end
            end
            -- Consider if we should break from player buffs loop if a storm is found.
            -- For now, last storm found dictates.
        end
    end

    local weather_element_name = weather_id_to_element_map[final_weather_id_for_element] or 'UnknownWeather('..tostring(final_weather_id_for_element)..')'
    if weather_element_name == 'Clear' or weather_element_name == 'Sunshine' or weather_element_name == 'Clouds' or weather_element_name == 'Fog' then
        weather_element_name = 'NonElementalWeather'
    end

	return weather_element_name, day_element_name
end

local function GetCurrentWeatherId()
    if weather_memory_pointer and weather_memory_pointer ~= 0 then
        return ashita.memory.read_uint8(weather_memory_pointer)
    end
    -- Fallback or error
    local world_info = ashita.ffxi.get_world_info()
    if world_info then return world_info.weather_id end
    return 0 -- Default to Clear if pointer not found
end

function clear_skillchain()
	last_skillchain = {}
	last_skillchain.english = 'None'
	last_skillchain.elements = {}
end

function cast_spell(spell_cmd, target_struct)
    -- Assuming target_struct contains an 'id' field from previous logic
    local target_entity = ashita.ffxi.get_mob_by_id(target_struct.id)
    if not target_entity then
        debug_message("Cast Spell: Target entity not found for ID: " .. tostring(target_struct.id))
		finish_burst()
		return
    end

	-- TODO: Verify Ashita entity property 'is_valid_target'.
	if (not target_entity.is_valid_target) then
		debug_message("Cast Spell: Target is no longer valid")
		finish_burst()
		return
	end
    -- TODO: Verify Ashita entity property 'is_npc'.
	if (not target_entity.is_npc) then
		debug_message("Cast Spell: Target is not an npc")
		finish_burst()
		return
	end
    -- TODO: Verify Ashita entity property 'hpp'.
	if (target_entity.hpp <= 0) then
		debug_message("Cast Spell: Target is too dead already")
		finish_burst()
		return
	end
	
	if (settings.show_spell) then
		message("Casting - "..spell_cmd..' for the burst!')
	end
	if (settings.gearswap) then
		ashita.ffxi.command('gs c bursting')
	end
	ashita.ffxi.command('/ma "'..spell_cmd..'" <t>') -- Removed 'input ' for Ashita command
end

function get_spell(skillchain, last_spell, second_burst, target_change)
	local spell_element = ''
	local weather_element, day_element = get_bonus_elements()
	local spell = ''
	local step_down = 0
	local cast_type = settings.cast_type
	local tier = settings.cast_tier

	debug_message('Getting Spell ...',true)
	debug_message('Day Element: '..day_element,true)
	debug_message('Weather Element: '..weather_element,true)

	if (not second_burst or last_spell == nil) then
		last_spell = ''
	end

	if (second_burst) then
		if (cast_type == 'ja') then
			cast_type = 'spell'
		elseif (settings.step_down == 2 or (settings.step_down == 1 and target_change ~= nil and target_change > 0)) then
			step_down = 1
		end
	end

	if (settings.check_weather and table_contains(skillchain.elements, weather_element)) then -- TODO: Implement table_contains or use common.lua utility
		spell_element = weather_element
	elseif (settings.check_day and table_contains(skillchain.elements, day_element)) then -- TODO: Implement table_contains or use common.lua utility
		spell_element = day_element
	else
		for i=1,#spell_priorities do
			if (table_contains(skillchain.elements, spell_priorities[i].element)) then -- TODO: Implement table_contains or use common.lua utility
				spell_element = spell_priorities[i].element
				break
			end
		end
	end

	debug_message('Best Spell Element: '..spell_element,true)

	if (tier > max_tiers[cast_type]) then
		tier = max_tiers[cast_type]
	end
	tier = (tier - step_down > 0 and (tier - step_down) or 1)
	
	-- Find spell/helix/jutsu that will be best based on best element
	if (elements[spell_element] ~= nil and elements[spell_element][cast_type] ~= nil) then
		spell = elements[spell_element][cast_type]

		tier = tier >= 1 and tier or 1
		tier = cast_type == 'jutsu' and tier > 3 and 3 or tier

		spell = spell .. (cast_type == 'jutsu' and (': ' .. jutsu_tiers[tier].suffix or magic_tiers[tier].suffix) or (tier > 1 and ' ' or ''))

		local recast = check_recast(spell)
		if (recast > 0) then
			if (settings.step_down == 2 and tier > 1) then
				spell = elements[spell_element][cast_type]
				while (tier > 1) do
					tier = tier - 1
					tier = (tier >= 1 and tier or 1)
					spell = spell .. (cast_type == 'jutsu' and (': ' .. jutsu_tiers[tier].suffix or magic_tiers[tier].suffix) or (tier > 1 and ' ' or ''))

					local recast = check_recast(spell)
					if (not recast or recast <= 0) then
						break
					end
					spell = nil
				end
			end
		end
	end

	debug_message('Spell: '..spell,true)

	if (spell == nil or spell == '') then
		for _,element in pairs(skillchain.elements) do
			if (elements[element] ~= nil and elements[element][cast_type] ~= nil) then
				spell = elements[element][cast_type]

				tier = (tier >= 1 and tier or 1)
				spell = spell .. (cast_type == 'jutsu' and (': ' .. jutsu_tiers[tier].suffix or magic_tiers[tier].suffix) or (tier > 1 and ' ' or ''))
			
				local recast = check_recast(spell)
				if (recast == 0) then
					break
				end
			end
		end
	end

	debug_message('Spell: '..(spell == nil and 'None Found' or spell),true)

	-- Display some skillchain/magic burst info, can show up whether auto bursts are on or not
	local element_list = ''
	local sc_info = addon.name..': '

	for i=1,#skillchain.elements do
		element_list = element_list..skillchain.elements[i]..(i<#skillchain.elements and ', ' or '')
	end
	
	if (settings.show_skillchain) then sc_info = sc_info..'Skillchain effect '..skillchain.english..' ' end
	if (settings.show_elements) then sc_info = sc_info..'['..element_list..'] ' end
	if (settings.show_bonus_elements) then sc_info = sc_info..'Weather: '.. weather_element..' Day: '..day_element..' ' end
	if (settings.show_skillchain or settings.show_elements or settings.show_bonus_elements) then print(ashita_chat.prefix(addon.name):append(ashita_chat.message(sc_info))) end

	return spell
end -- get_spell()

function set_target(target_to_set) -- Renamed 'target' to 'target_to_set' to avoid conflict
    player = ashita.ffxi.get_player_entity() -- Ensure 'player' is the Ashita entity
    if not player then return 0 end

	local cur_target_entity = player.target_index and ashita.ffxi.get_mob_by_index(player.target_index) or nil

    -- TODO: Verify Ashita entity property 'is_valid_target'.
    -- TODO: Verify Ashita entity property 'is_npc'.
    -- TODO: Verify Ashita entity property 'hpp'.
	if (target_to_set == nil or not target_to_set.is_valid_target or not target_to_set.is_npc or target_to_set.hpp == nil or target_to_set.hpp <= 0) then
		return 0
	end

	if (cur_target_entity ~= nil and cur_target_entity.id == target_to_set.id) then
		return 0
	end

    -- TODO: Verify the exact structure and byte packing for packet 0x058.
    -- Assuming Player ID (4 bytes), Target ID (4 bytes), Player Index (2 bytes). Total 10 bytes.
    -- This is a common structure for S->C Action_Target type packets where an actor targets something.
    local packet_data = {}
    if not player or not player.id or not player.index then
        debug_message("Set_Target: Player or player info missing for packet construction.")
        return 0
    end
    if not target_to_set or not target_to_set.id then
        debug_message("Set_Target: Target entity or target ID missing for packet construction.")
        return 0
    end

    local p_id_bytes = ashita.memory.uint_to_bytes(player.id)
    local t_id_bytes = ashita.memory.uint_to_bytes(target_to_set.id)
    local p_idx_bytes = ashita.memory.ushort_to_bytes(player.index)

    -- Assuming little-endian, which is typical for FFXI and Ashita's helpers handle it.
    for i = 1, 4 do table.insert(packet_data, p_id_bytes[i]) end
    for i = 1, 4 do table.insert(packet_data, t_id_bytes[i]) end
    for i = 1, 2 do table.insert(packet_data, p_idx_bytes[i]) end

    -- Packet 0x058 might have more fields (e.g., action counter, often 0). If the packet is strictly 10 bytes:
    -- If it needs to be padded to a certain size or has other fields, this will need adjustment.
    -- For example, if there's a 2-byte action counter (e.g., 0x0000) after target_id and before player_index:
    -- table.insert(packet_data, 0); table.insert(packet_data, 0); -- for a u_short action_count = 0
    -- Then the player.index would follow.
    -- For now, sticking to the 3 fields implied by the Windower code.

    if packet_manager then
        packet_manager:AddIncomingPacket(0x058, packet_data)
    else
        print(addon.name .. ": Error - Packet Manager not available for set_target.")
    end
    -- debug_message("TODO: Implement packet injection for setting target in Ashita.") -- Original debug message removed as implementation is added.

	return 1
end

function do_burst(target_mob, skillchain, second_burst, last_spell) -- Renamed 'target' to 'target_mob'
    player = ashita.ffxi.get_player_entity() -- Ensure 'player' is the Ashita entity
    if not player then
        debug_message("Player entity not found in do_burst.")
        finish_burst()
        return
    end

    -- TODO: Verify Ashita entity property 'is_npc'.
    -- TODO: Verify Ashita entity property 'is_valid_target'.
    -- TODO: Verify Ashita entity property 'hpp'.
	if (target_mob == nil or not target_mob.is_npc or not target_mob.is_valid_target or target_mob.hpp <= 0) then
		debug_message("Bad Target!")
		finish_burst()
		return
	end

	local target_delay = 0
	if (settings.change_target) then
		target_delay = set_target(target_mob)
	end

	local spell = get_spell(skillchain, last_spell, second_burst, target_delay >= 1)

	if (spell == nil or spell == '') then
		if (settings.show_spell) then
			message("No spell found for burst!")
		end
		finish_burst()
		return
	elseif (disabled()) then
		message("Unable to cast, disabled!")
		finish_burst()
		return
	elseif (low_mp(spell)) then
		message("Not enough MP for MB!")
		finish_burst()
		return
	end
	
	is_bursting = true
	local cast_delay_val = math.random(0.1, settings.cast_delay) -- Renamed to avoid conflict with global cast_delay
    ashita.tasks.once(target_delay + cast_delay_val, function() cast_spell(spell, target_mob) end)

	if (settings.double_burst and not second_burst) then
		debug_message("Setting up double burst")
        local spell_obj = resource_manager:GetSpellByName(spell, 'en')
		local cast_time = spell_obj and spell_obj.cast_time or nil -- TODO: Verify Ashita spell object property for 'cast_time'.
		if (cast_time == nil) then
			finish_burst()
			return
		end
		local d = cast_time + settings.double_burst_delay + target_delay + 1
        ashita.tasks.once(d, function() do_burst(target_mob, skillchain, true, spell) end)
	else
        local spell_obj = resource_manager:GetSpellByName(spell, 'en')
		local cast_time = spell_obj and spell_obj.cast_time or nil -- TODO: Verify Ashita spell object property for 'cast_time'.
		if (cast_time == nil) then
			finish_burst()
			return
		end
		local d = cast_time + target_delay
        ashita.tasks.once(d, function() finish_burst() end)
	end
end

function finish_burst()
	is_bursting = false
	debug_message("Finished Burst, clearing chain and telling gearswap")
	if (settings.gearswap) then
		ashita.ffxi.command('gs c notbursting')
	end
	clear_skillchain()
end

--[[ Ashita Events ]]--
local function autoMB_load()
    local signature_offset = ashita.memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0, 0)
    if signature_offset > 0 then
        weather_memory_pointer = ashita.memory.read_uint32(signature_offset + 0x02)
        if weather_memory_pointer == 0 then
            print(addon.name .. ': Warning - Found weather signature but pointer was null.')
        else
            -- Optional: print(addon.name .. ': Weather memory pointer initialized.')
        end
    else
        print(addon.name .. ': Error - Could not find memory signature for weather pointer.')
    end
    -- Potentially call handle_job_change here if needed on load, after getting player info
    -- local player_entity = ashita.ffxi.get_player_entity()
    -- if player_entity and player_entity.main_job_id and player_entity.sub_job_id then
    --    handle_job_change(player_entity.main_job_id, player_entity.main_job_level, player_entity.sub_job_id, player_entity.sub_job_level)
    -- end
end
ashita.events.register('load', 'autoMB_load', autoMB_load)


ashita.events.register('d3d_present', 'autoMB_d3d_present', function()
	local time = os.clock()
	local delta_time = time - last_check_time
	last_check_time = time

	if (is_busy > 0) then
		is_busy = (is_busy - delta_time) < 0 and 0 or (is_busy - delta_time)
	end
end)

-- Check for skillchain effects applied, this can get wonky if/when a group is skillchaining on multiple mobs at once
ashita.events.register('packet_in', 'autoMB_packet_in', function(e)
	if (e.id ~= 0x28 or not active) then
		return
	end
	local now = os.clock()
	if (now < last_packet_time + min_packet_time) then
		return
	end
	last_packet_time = now

    if not struct then
        debug_message("Struct library not available, cannot parse packet 0x028.")
        return
    end

    -- TODO: VERIFY ALL OFFSETS AND DATA TYPES FOR PACKET 0x028
    -- These offsets are 1-based for string.byte and struct.unpack.
    local OFFSET_ACTOR_ID = 5  -- 0-idx 4: Actor ID (4 bytes)
    local OFFSET_TARGET_COUNT = 9 -- 0-idx 8: Number of targets (1 byte). This is often part of the main action header.
                                  -- Note: Windower's `data:unpack('C', 20)` was likely for a specific interpretation where target count is further in.
                                  -- A common 0x028 structure has actor ID, then some flags/category/param, then target count, then targets.
                                  -- Let's try a more standard interpretation first for target count.

    -- For player's own action (when actor_id is self)
    local OFFSET_SELF_ACTION_CATEGORY = 11 -- 0-idx 10: Main Action Category (1 byte)
    local OFFSET_SELF_ACTION_PARAM = 12    -- 0-idx 11: Main Action Parameter (uShort, 2 bytes)

    -- For target blocks (iterating target_count times)
    local OFFSET_FIRST_TARGET_BLOCK_START = 28 -- Speculative: Start of the first target's data block.
                                               -- This must be *after* the main header fields.
    local TARGET_ID_SIZE = 4
    local TARGET_EFFECT_MSG_SIZE = 1
    -- Stride to get to the *start* of the next target's ID, assuming a minimal block of ID + effect message.
    -- This is highly simplified. Real 0x028 target blocks are complex and variable.
    local TARGET_BLOCK_STRIDE = TARGET_ID_SIZE + TARGET_EFFECT_MSG_SIZE -- Minimal stride (5 bytes)
    local OFFSET_ADD_EFFECT_MSG_RELATIVE = TARGET_ID_SIZE -- 0-idx from start of target_id to its effect message byte (i.e. byte after ID)

    if not e.data_raw or #e.data_raw < 20 then -- Minimum length for basic header fields up to a potential target count.
        debug_message("Packet 0x028 too short for initial parsing or data_raw missing.")
        return
    end

    local actor_id = struct.unpack("<I", e.data_raw, OFFSET_ACTOR_ID)
    local target_count = string.byte(e.data_raw, OFFSET_TARGET_COUNT)

    player = ashita.ffxi.get_player_entity()

    if player and actor_id == player.id then
        -- This is an action by the player themself. Update is_busy, is_casting.
        -- TODO: VERIFY OFFSETS for player's own action category and param.
        if #e.data_raw >= (OFFSET_SELF_ACTION_PARAM + 1) then -- Ensure packet is long enough for these fields
            local self_action_category = string.byte(e.data_raw, OFFSET_SELF_ACTION_CATEGORY)
            local self_action_param = struct.unpack("<H", e.data_raw, OFFSET_SELF_ACTION_PARAM)

            if table_contains(start_act, self_action_category) then
                if self_action_param == 24931 then -- Begin Casting/WS/Item/Range
                    is_busy = 0
                    is_casting = true
                elseif self_action_param == 28787 then -- Failed Casting/WS/Item/Range
                    is_casting = false
                    is_busy = failed_cast_delay
                end
            elseif self_action_category == 6 then -- Use Job Ability
                is_busy = ability_delay
            elseif self_action_category == 4 then -- Finish Casting
                is_busy = after_cast_delay
                is_casting = false
            elseif table_contains(finish_act, self_action_category) then -- Finish Range/WS/Item Use
                is_busy = 0
                is_casting = false
            end
        else
            debug_message("Player action packet 0x028 too short for category/param.")
        end
    end

    if is_bursting then
        -- debug_message("Bursting: "..(is_bursting and "Yes" or "No").." Casting: "..(is_casting and "Yes" or "No").." Busy: "..is_busy.." second(s)")
        return
    end

    if target_count and target_count > 0 then
        -- Calculate where action details might start *after* all target blocks.
        -- This is needed if OFFSET_SELF_ACTION_CATEGORY/PARAM are relative to this point for non-player actor packets.
        -- However, for skillchain detection, we are interested in effects *on* targets.

        -- The crucial part is the structure of each target's data block and the actions within it.
        -- Windower's `actions_packet.targets[idx].actions[idx2].add_effect_message` implies a nested structure.
        -- A common 0x028 format: Header -> TargetCount -> [TargetID, NumSubActions, [ActionType, ActionParam, ActionMessage]...]
        -- The simplified loop below assumes the add_effect_message is at a fixed relative offset from TargetID,
        -- which is often true for the *primary* additional effect like skillchains.

        -- TODO: VERIFY OFFSET_FIRST_TARGET_BLOCK_START and TARGET_BLOCK_STRIDE
        -- These are highly speculative.
        if #e.data_raw < (OFFSET_FIRST_TARGET_BLOCK_START + (target_count * TARGET_BLOCK_STRIDE) - TARGET_BLOCK_STRIDE + OFFSET_ADD_EFFECT_MSG_RELATIVE) then
            debug_message("Packet 0x028 too short for all declared targets and effects.")
            return
        end

        for i = 0, target_count - 1 do
            local target_base_offset = OFFSET_FIRST_TARGET_BLOCK_START + (i * TARGET_BLOCK_STRIDE)

            local target_id = struct.unpack("<I", e.data_raw, target_base_offset)
            -- The add_effect_message_id is the byte immediately after the 4-byte target_id in this simplified model.
            local add_effect_message_id = string.byte(e.data_raw, target_base_offset + OFFSET_ADD_EFFECT_MSG_RELATIVE)

            if skillchains[add_effect_message_id] then
                local target_entity = ashita.ffxi.get_mob_by_id(target_id)
                if target_entity then
                    -- TODO: Verify Ashita entity properties: is_npc, claim_id, distance, name
                    if target_entity.is_npc then
                        -- TODO: Party/Claim Check. For now, let's assume we burst on any valid NPC target.
                        -- This needs refinement to avoid bursting on mobs not engaged by player/party.
                        if target_entity.distance and target_entity.distance < settings.cast_range then
                            debug_message("Skillchain effect " .. skillchains[add_effect_message_id].english .. " detected on " .. (target_entity.name or "Unknown Target"))
                            last_skillchain = skillchains[add_effect_message_id]
                            local delay_for_burst = settings.cast_delay + is_busy -- is_busy should be updated by player's own actions
                            ashita.tasks.once(delay_for_burst, function() do_burst(target_entity, last_skillchain, false, '', 0) end)
                            break -- Act on first valid skillchain target
                        else
                            debug_message("Target (" .. (target_entity.name or "Unknown Target") .. ") for skillchain out of range (" .. string.format("%.2f", target_entity.distance) .. "y).")
                        end
                    end
                else
                    debug_message("Skillchain effect on unknown target ID: " .. target_id)
                end
            end
        end
    end
end)

local function handle_job_change()
    local p_entity = ashita.ffxi.get_player_entity()
    if not p_entity then
        print(addon.name .. ": Could not get player entity in handle_job_change.")
        return
    end

    local main_job_id = p_entity.main_job_id -- TODO: Verify property name for main_job_id
    local main_job_lvl = p_entity.main_job_level -- TODO: Verify property name for main_job_level
    local sub_job_id = p_entity.sub_job_id -- TODO: Verify property name for sub_job_id
    local sub_job_lvl = p_entity.sub_job_level -- TODO: Verify property name for sub_job_level

    -- Ensure these are not nil before proceeding, provide defaults if necessary
    main_job_id = main_job_id or 0
    main_job_lvl = main_job_lvl or 0
    sub_job_id = sub_job_id or 0
    sub_job_lvl = sub_job_lvl or 0

    local main_job_obj = resource_manager:GetJobById(main_job_id) -- Use main_job_id (was main_job_id_arg)
    local main = main_job_obj and main_job_obj.short_name_en or "UNK" -- TODO: Verify Ashita job object property for short English name (e.g., short_name_en, abbr_en).
    local sub_job_obj = resource_manager:GetJobById(sub_job_id)     -- Use sub_job_id (was sub_job_id_arg)
    local sub = sub_job_obj and sub_job_obj.short_name_en or "UNK" -- TODO: Verify Ashita job object property for short English name.

	-- Set settings.cast_type to 'none' to stop casting if job/sub doesn't support casting
	settings.cast_type = 'none'

	if (table_contains(spell_users, main)) then
		settings.cast_type = 'spell'
	elseif (table_contains(jutsu_users, main)) then
		settings.cast_type = 'jutsu'
	elseif (table_contains(helix_users, main)) then
		settings.cast_type = 'spell'
	elseif (table_contains(spell_users, sub)) then
		settings.cast_type = 'spell'
	elseif (table_contains(jutsu_users, sub)) then
		settings.cast_type = 'jutsu'
	elseif (table_contains(helix_users, sub)) then
		settings.cast_type = 'spell'
	end
	message('> Cast type set to: '..settings.cast_type)
end

-- Stop checking if logout happens or zoning and disable on zone is true
ashita.events.register('zone_change', 'autoMB_zone_change', function(e)
	ashita.ffxi.command('/autommb off')
	player = nil -- Clear global player cache
    handle_job_change() -- Update cast type based on new zone/job info
	return
end)

-- 
-- Process incoming commands
ashita.events.register('command', 'autoMB_command', function(e)
    local raw_arg_list = string_split(e.command, ' ')
    local command_name = raw_arg_list[1] -- This is the typed command itself, e.g., /autommb

    -- Filter for our addon's commands
    if command_name ~= '/autommb' and command_name ~= '/amb' then
        return
    end
    e.blocked = true -- Block the command if it's for us

    local args = {} -- Create a 1-based args table for compatibility with old code
    for i = 2, #raw_arg_list do
        table.insert(args, raw_arg_list[i])
    end
	local cmd = args[1] or 'none'


	if (cmd == 'test') then
		local test_skillchain = {}
		local test_spell = nil

		test_skillchain.english = 'Test Chain'
		test_skillchain.elements = {'Earth','Light','Fire', 'Ice'}
		test_spell = get_spell(test_skillchain, nil, false, true)
		message('Test Spell: '..(test_spell ~= nil and test_spell or 'Not Found'))
		return
	elseif (cmd == 'help') then
		show_help()
		return
	elseif (cmd == 'status' or cmd == 'show') then
		show_status()
		return
	elseif (cmd == "none") then -- This typically means just `/amb` or `/autommb` was typed
		active = not active
		print(ashita_chat.prefix(addon.name):append(ashita_chat.message('AutoMB '..(active and 'activating' or 'deactivating'))))
		player = ashita.ffxi.get_player_entity()
		last_check_time = os.clock()
        return
	elseif (table_contains({"on","start","run","go"}, cmd)) then
		active = true
		print(ashita_chat.prefix(addon.name):append(ashita_chat.message('AutoMB activating')))
		player = ashita.ffxi.get_player_entity()
		last_check_time = os.clock()
        return
    elseif (table_contains({"off","stop","end"}, cmd)) then
        active = false
        print(ashita_chat.prefix(addon.name):append(ashita_chat.message('AutoMB deactivating')))
		return
	elseif (cmd == 'cast' or cmd == 'c') then
		if (#args < 2) then
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Usage: autoMB cast spell|helix|jutsu\nTells AutoMB what magic type to try to cast if the default is not what you want.")))
		end
		if (#args >= 2 and table_contains(cast_types, args[2]:lower())) then
			settings.cast_type = args[2]:lower()
		end
		print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Cast Type set to "..settings.cast_type)))
		settings_manager.save(settings)
		return
	elseif (cmd == 'tier' or cmd == 't') then
		if (#args < 2) then
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Usage: tier 1~6\nTells autoMB what tier spell to use for Ninjutsu 1~3 will become ichi|ni|san.")))
			return
		end
		local t = tonumber(args[2])
		if (settings.cast_type == 'jutsu') then
			if (t > 0 and t < 4) then
				settings.cast_tier = t
			end
		else
			if (t > 0 and t < 7) then
				settings.cast_tier = t
			end		
		end
		message("Cast Tier set to: "..t.." ["..(settings.cast_type == 'jutsu' and jutsu_tiers[settings.cast_tier] and jutsu_tiers[settings.cast_tier].suffix or magic_tiers[settings.cast_tier] and magic_tiers[settings.cast_tier].suffix or "Unknown Tier").."]")
		settings_manager.save(settings)
		return
	elseif (cmd == 'range' or cmd == 'rng') then
		if (#args < 2) then
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Usage: autoMB ##\nTells AutoMB what the max cast range to target is (default is 22).")))
		end

		settings.cast_range = tonumber(args[2]) and tonumber(args[2]) or 22
		print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Cast Range set to "..settings.cast_range)))
		settings_manager.save(settings)
		return
	elseif (cmd == 'mp') then
		local n = tonumber(args[2])
		if (n == nil or n < 0) then
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Usage: autoMB mp #")))
			return
		end
		settings.mp = n
		print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Cast Min MP set to "..settings.mp)))
		settings_manager.save(settings)
		return
	elseif (cmd == 'delay' or cmd == 'd') then
		local n = tonumber(args[2])
		if (n == nil or n < 0) then
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Usage: autoMB delay #")))
			return
		end
		settings.cast_delay = n
		print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Cast Delay set to "..settings.cast_delay)))
		settings_manager.save(settings)
		return
	elseif (cmd == 'frequency' or cmd == 'f') then
		local n = tonumber(args[2])
		if (n == nil or n < 0) then
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Usage: autoMB (f)requency #")))
			return
		end
		settings.frequency = n
		print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Check Frequency set to "..settings.frequency.." times per second")))
		settings_manager.save(settings)
		return
	elseif (cmd == 'doubleburst' or cmd == 'double' or cmd == 'dbl') then
		settings.double_burst = not settings.double_burst
		print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Double Bursting set to "..(settings.double_burst and "True" or "False"))))
		settings_manager.save(settings)
		return
	elseif (cmd == 'doubleburstdelay' or cmd == 'doubledelay' or cmd == 'dbldelay' or cmd == 'dbld') then
		local n = tonumber(args[2])
		if (n == nil or n < -10 or n > 10) then
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Usage: autoMB doubleburstdelay [-10..10]")))
			return
		end
		settings.double_burst_delay = n
		print(ashita_chat.prefix(addon.name):append(ashita_chat.message("Double Burst Delay set to "..settings.double_burst_delay)))
		settings_manager.save(settings)
		return
	elseif (cmd == 'weather') then
		settings.check_weather = not settings.check_weather
		message('Will'..(settings.check_weather and ' ' or ' not ')..'use current weather bonuses')
		settings_manager.save(settings)
		return
	elseif (cmd == 'day') then
		settings.check_day = not settings.check_day
		message('Will'..(settings.check_day and ' ' or ' not ')..'use current day bonuses')
		settings_manager.save(settings)
		return
	elseif (cmd == 'toggle' or cmd == 'tog') then
		local what = 'all'
		local toggle = 'toggle'

		if (#args > 1) then
			what = args[2]:lower()
		end

		if (#args > 2) then
			toggle = args[3]:lower()
		end

		-- Show/Hide skillchain name/elements and spell(s) to be cast
		if (what == 'skillchain' or what == 'sc' or what == 'all') then
			if (toggle == '' or toggle == 'toggle') then
				settings.show_skillchain = not settings.show_skillchain
			else
				settings.show_skillchain = (toggle == 'on')
			end
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message('AutoMB: Skillchain info will be '..(settings.show_skillchain == true and 'shown' or 'hidden'))))
        end
		
		if (what == 'elements' or what == 'element' or what == 'all') then
			if (toggle == 'toggle') then
				settings.show_elements = not settings.show_elements
			else
				settings.show_elements = (toggle == 'on')
			end
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message('AutoMB: Skillchain element info will be '..(settings.show_elements == true and 'shown' or 'hidden'))))
        end

		if (what == 'weather' or what == 'bonus' or what == 'all') then
			if (toggle == 'toggle') then
				settings.show_bonus_elements = not settings.show_bonus_elements
			else
				settings.show_bonus_elements = (toggle == 'on')
			end
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message('AutoMB: Day/Weather element info will be '..(settings.show_bonus_elements == true and 'shown' or 'hidden'))))
        end

		if (what == 'spell' or what == 'sp' or what == 'all') then
			if (toggle == 'toggle') then
				settings.show_spell = not settings.show_spell
			else
				settings.show_spell = (toggle == 'on')
			end
			print(ashita_chat.prefix(addon.name):append(ashita_chat.message('AutoMB: Spell info will be '..(settings.show_spell == true and 'shown' or 'hidden'))))
		end

		settings_manager.save(settings)
		return
	elseif (cmd == 'stepdown' or cmd == 'sd') then
		local txt = ''
		if (settings.step_down == 0) then
			settings.step_down = 1
			txt = 'on target change'
		elseif (settings.step_down == 1) then
			settings.step_down = 2
			txt = 'always'
		else
			settings.step_down = 0
			txt = 'never'
		end
		message("Double burst Step Down set to "..txt)
		settings_manager.save(settings)
		return
	elseif (cmd == 'gearswap' or cmd == 'gs') then
		if (settings.gearswap) then
			settings.gearswap = false
		else
			settings.gearswap = true
		end
		message("Will "..(settings.gearswap and '' or ' not ').."use 'gs c bursting' and 'gs c notbursting'")
		settings_manager.save(settings)
		return
	elseif (cmd == 'target' or cmd == 'tgt') then
		if (settings.change_target == nil) then
			settings.change_target = false
		end
		settings.change_target = not settings.change_target
		message("Auto target swapping "..(settings.change_target and 'enabled' or 'disabled')..".")
		settings_manager.save(settings)
		return
	elseif (cmd == 'zone' or cmd == 'z') then
		settings.disable_on_zone = settings.disable_on_zone and (not settings.disable_on_zone) or true
		message("Auto MB will be "..(settings.disable_on_zone and 'enabled' or 'disabled').." when zoning.")
		settings_manager.save(settings)
		return
	elseif (cmd == 'debug') then
		debug = not debug
		message("Will "..(debug and '' or ' not ').."show debug information")
		return
    end
end) -- Addon Command
