--@module = true
--tatoyoda600
-- Huge thanks to Rumrusher for the base resizing code http://www.bay12forums.com/smf/index.php?topic=164123.msg8487568;topicseen#msg8487568
local help = [====[

resize-site
=============
Resize a site.
Allows for shrinking and growing the current site via a GUI.
By default attempts to preserve unit and item data, but what data to preserve can be specified.

Warnings:
- This script may cause unintended consequences, make sure to save beforehand just in case
- Any parts of a site that are unloaded will be lost


Usage
-----

    resize-site
    resize-site --nomad
    resize-site --keepData [data types]
    resize-site --nomad --keepData [data types]


Examples
--------

"resize-site"
    Opens the standard resizing GUI.

"resize-site --nomad"
    Opens the nomad resizing GUI, which provides a quick and simple interface that stays open for easy site movement.

"resize-site --keepData units,items"
    Tries to preserve as much unit and item data as possible from unloaded areas, and then restore them when revisiting.
    Available data types are:
    - all
    - none
    - units
    - items

]====]

local argparse = require('argparse')
local gui = require('gui')
local widgets = require('gui.widgets')
local overlay = require('plugins.overlay')

local SCRIPT_NAME = "resize-site"
local WIDGET_NAME = "overlay"
local SAVE_DATA_KEY = "tatoyoda600_"..SCRIPT_NAME
local PRESERVED_DATA_SAVE_KEY = SAVE_DATA_KEY.."_preserved_data"

local STD_UI_AREA = {r=4, t=19, w=50, h=36}
local NOMAD_UI_AREA = {r=4, t=19, w=28, h=23}
local MAX_SITE_SIZE = 8

local KEEP_DATA_DEFAULT = { units= true, items= true }
local PRESERVED_DATA_DEFAULT = {
    ---@type { x: integer, y: integer }
    store_pos = nil,
    ---@type item_cagest
    cage = nil,
    ---@type unit[][][][]
    units = {},
    ---@type item[][][][]
    items = {},
    ---@type fun(unit: unit, pos:{x:integer,y:integer,z:integer})
    insertUnit = function(unit, pos)
        preserved_data.units[pos.x] = preserved_data.units[pos.x] or {}
        preserved_data.units[pos.x][pos.y] = preserved_data.units[pos.x][pos.y] or {}
        preserved_data.units[pos.x][pos.y][pos.z] = preserved_data.units[pos.x][pos.y][pos.z] or {}
        preserved_data.units[pos.x][pos.y][pos.z][unit.id] = unit
    end,
    ---@type fun(item: item, pos:{x:integer,y:integer,z:integer})
    insertItem = function(item, pos)
        preserved_data.items[pos.x] = preserved_data.items[pos.x] or {}
        preserved_data.items[pos.x][pos.y] = preserved_data.items[pos.x][pos.y] or {}
        preserved_data.items[pos.x][pos.y][pos.z] = preserved_data.items[pos.x][pos.y][pos.z] or {}
        preserved_data.items[pos.x][pos.y][pos.z][item.id] = item
    end
}
local CAGE_MAT = {
    df.builtin_mats.INORGANIC,
    158 --DIAMOND_BLACK
}
TILE_MAP = {
    ---@param nesw { n: boolean, e: boolean, s: boolean, w: boolean }
    ---@return integer
    getPenKey= function(nesw)
        return (
            (nesw.n and 8 or 0)
            + (nesw.e and 4 or 0)
            + (nesw.s and 2 or 0)
            + (nesw.w and 1 or 0)
        )
    end
}
---@type table<integer, Pen>
TILE_MAP.pens= {
    [TILE_MAP.getPenKey{ n=false, e=false, s=false, w=false }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3, 15), fg=COLOR_GREEN, ch='X'}, -- INSIDE
    [TILE_MAP.getPenKey{ n=true,  e=false, s=false, w=true  }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3,  1), fg=COLOR_GREEN, ch='X'}, -- NW
    [TILE_MAP.getPenKey{ n=true,  e=false, s=false, w=false }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3,  5), fg=COLOR_GREEN, ch='X'}, -- NORTH
    [TILE_MAP.getPenKey{ n=true,  e=true,  s=false, w=false }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3,  2), fg=COLOR_GREEN, ch='X'}, -- NE
    [TILE_MAP.getPenKey{ n=false, e=false, s=false, w=true  }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3,  7), fg=COLOR_GREEN, ch='X'}, -- WEST
    [TILE_MAP.getPenKey{ n=false, e=true,  s=false, w=false }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3,  6), fg=COLOR_GREEN, ch='X'}, -- EAST
    [TILE_MAP.getPenKey{ n=false, e=false, s=true,  w=true  }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3,  4), fg=COLOR_GREEN, ch='X'}, -- SW
    [TILE_MAP.getPenKey{ n=false, e=false, s=true,  w=false }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3,  8), fg=COLOR_GREEN, ch='X'}, -- SOUTH
    [TILE_MAP.getPenKey{ n=false, e=true,  s=true,  w=false }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3,  3), fg=COLOR_GREEN, ch='X'}, -- SE
    [TILE_MAP.getPenKey{ n=true,  e=true,  s=false, w=true  }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3, 11), fg=COLOR_GREEN, ch='X'}, -- N_NUB
    [TILE_MAP.getPenKey{ n=true,  e=true,  s=true,  w=false }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3, 14), fg=COLOR_GREEN, ch='X'}, -- E_NUB
    [TILE_MAP.getPenKey{ n=true,  e=false, s=true,  w=true  }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3, 13), fg=COLOR_GREEN, ch='X'}, -- W_NUB
    [TILE_MAP.getPenKey{ n=false, e=true,  s=true,  w=true  }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3, 12), fg=COLOR_GREEN, ch='X'}, -- S_NUB
    [TILE_MAP.getPenKey{ n=false, e=true,  s=false, w=true  }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3, 10), fg=COLOR_GREEN, ch='X'}, -- VERT_NS
    [TILE_MAP.getPenKey{ n=true,  e=false, s=true,  w=false }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3,  9), fg=COLOR_GREEN, ch='X'}, -- VERT_EW
    [TILE_MAP.getPenKey{ n=true,  e=true,  s=true,  w=true  }] = dfhack.pen.parse{tile=dfhack.screen.findGraphicsTile("ACTIVITY_ZONES", 3,  0), fg=COLOR_GREEN, ch='X'}, -- POINT
}

---@type ResizeScreenClass|nil
view = view
preserved_data = preserved_data or PRESERVED_DATA_DEFAULT

---@param pos coord
---@param rect coord_rect
local function isInRect(pos, rect)
    return pos.x >= rect.x1 and pos.x <= rect.x2 and pos.y >= rect.y1 and pos.y <= rect.y2
end

---@param num number
---@return integer
local function sign(num)
    return num > 0 and 1
        or num < 0 and -1
        or 0
end

---@param table table
---@param key string
---@return boolean
function hasKey(table, key)
    return table._type._fields[key] ~= nil
end

---@param store_pos? coord
local function shiftPreservedInBounds(store_pos)
    if dfhack.isMapLoaded() then
        if preserved_data.store_pos then
            store_pos = store_pos or { x= preserved_data.store_pos.x, y= preserved_data.store_pos.y, z= df.global.world.map.z_count - 1 }
        end
        store_pos = store_pos or { x= 1, y=1, z= df.global.world.map.z_count - 1 }
        preserved_data.store_pos = { x= store_pos.x, y= store_pos.y }

        -- Move the cage to the storage position
        if preserved_data.cage then
            preserved_data.cage.pos = xyz2pos(store_pos.x, store_pos.y, store_pos.z)
        end

        -- Move all preserved units to the storage position
        for _,y_list in pairs(preserved_data.units) do
            for _,z_list in pairs(y_list) do
                for _,unit_list in pairs(z_list) do
                    for _,unit in pairs(unit_list) do
                        if unit then
                            unit.pos = xyz2pos(store_pos.x, store_pos.y, store_pos.z)
                        end
                    end
                end
            end
        end

        -- Move all preserved items to the storage position
        for _,y_list in pairs(preserved_data.items) do
            for _,z_list in pairs(y_list) do
                for _,item_list in pairs(z_list) do
                    for _,item in pairs(item_list) do
                        if item then
                            item.pos = xyz2pos(store_pos.x, store_pos.y, store_pos.z)
                        end
                    end
                end
            end
        end
    end
end

---@param store_pos? coord
local function shiftPreservedOutOfBounds(store_pos)
    if dfhack.isMapLoaded() then
        if preserved_data.store_pos then
            store_pos = store_pos or { x= preserved_data.store_pos.x, y= preserved_data.store_pos.y, z= df.global.world.map.z_count + 1 }
        end
        store_pos = store_pos or { x= 1, y=1, z= df.global.world.map.z_count + 1 }
        preserved_data.store_pos = { x= store_pos.x, y= store_pos.y }

        -- Move the cage to the storage position
        if preserved_data.cage then
            preserved_data.cage.pos = xyz2pos(store_pos.x, store_pos.y, store_pos.z)
        end

        -- Move all preserved units to the storage position
        for _,y_list in pairs(preserved_data.units) do
            for _,z_list in pairs(y_list) do
                for _,unit_list in pairs(z_list) do
                    for _,unit in pairs(unit_list) do
                        if unit then
                            unit.pos = xyz2pos(store_pos.x, store_pos.y, store_pos.z)
                        end
                    end
                end
            end
        end

        -- Move all preserved items to the storage position
        for _,y_list in pairs(preserved_data.items) do
            for _,z_list in pairs(y_list) do
                for _,item_list in pairs(z_list) do
                    for _,item in pairs(item_list) do
                        if item then
                            item.pos = xyz2pos(store_pos.x, store_pos.y, store_pos.z)
                        end
                    end
                end
            end
        end
    end
end

local function saveData()
    local save_data = {
        cage = nil,
        units = {},
        items = {}
    }

    local saveCage = function()
        save_data.cage = preserved_data.cage and preserved_data.cage.id or nil
    end
    local saveUnits = function()
        for x,y_list in pairs(preserved_data.units) do
            for y,z_list in pairs(y_list) do
                for z,unit_list in pairs(z_list) do
                    for id,unit in pairs(unit_list) do
                        if unit then
                            save_data.units[id] = { x= x, y= y, z= z }
                        end
                    end
                end
            end
        end
    end
    local saveItems = function()
        for x,y_list in pairs(preserved_data.items) do
            for y,z_list in pairs(y_list) do
                for z,item_list in pairs(z_list) do
                    for id,item in pairs(item_list) do
                        if item then
                            save_data.items[id] = { x= x, y= y, z= z }
                        end
                    end
                end
            end
        end
    end

    if dfhack.isMapLoaded() then
        saveCage()
        saveUnits()
        saveItems()

        dfhack.persistent.saveSiteData(PRESERVED_DATA_SAVE_KEY, save_data)
    end
end

local function loadData()
    local loadCage = function(cage_id)
        -- Find the cage
        local cage = cage_id and df.item.find(cage_id) or nil

        -- If the cage can't be found
        if not cage then
            -- Create a cage
            cage = df.item.find(dfhack.items.createItem(df.item_type.CAGE,-1,CAGE_MAT[1],CAGE_MAT[2],df.global.world.units.all[0]))
        end

        -- If a cage was found/created
        if cage then
            -- Hide it, and forbid it
            cage.flags.hidden = true
            cage.flags.forbid = true
        end

        preserved_data.cage = cage
    end
    local loadUnits = function(unit_list)
        for id,pos in pairs(unit_list) do
            local unit = df.unit.find(id)
            if unit then
                preserved_data.insertUnit(unit, pos)
            end
        end
    end
    local loadItems = function(item_list)
        for id,pos in pairs(item_list) do
            local item = df.item.find(id)
            if item then
                preserved_data.insertItem(item, pos)
            end
        end
    end

    if dfhack.isMapLoaded() then
        local save_data = dfhack.persistent.getSiteData(PRESERVED_DATA_SAVE_KEY, {})
        for key,value in pairs(save_data) do
            if key == "cage" then
                loadCage(value)
            elseif key == "units" then
                loadUnits(value)
            elseif key == "items" then
                loadItems(value)
            end
        end

        if not preserved_data.cage then
            loadCage(nil)
        end

        shiftPreservedOutOfBounds()
        saveData()
    end
end

---@param region_pos_list coord2d[]
local function hideTiles(region_pos_list)
    -- Format global objects for easier access
    ---@type map_block_column[]
    local map_columns = df.global.world.map.map_block_columns
    ---@type { [1]: divine_treasure[], [2]: encased_horror[], [3]: cursed_tomb[], [4]: glowing_barrier[], [5]: deep_vein_hollow[] }
    local world_secrets = {
        [1]= df.global.world.divine_treasures, --divine_treasure.tiles
        [2]= df.global.world.encased_horrors,  --encased_horror.tiles
        [3]= df.global.world.cursed_tombs,     --cursed_tomb.coffin_pos
        [4]= df.global.world.glowing_barriers, --glowing_barrier.pos
        [5]= df.global.world.deep_vein_hollows --deep_vein_hollow.tiles
    }

    -- Find the corresponding map column for each region position in the list
    for _,column in pairs(map_columns) do
        for _,region_pos in pairs(region_pos_list) do
            if column.map_pos.x == region_pos.x and column.map_pos.y == region_pos.y then
                local avg_tile_height = column.ground_level - column.z_base - 1

                -- Untrigger any world secrets that auto-triggered
                for _,secret_list in pairs(world_secrets) do
                    for _,secret in pairs(secret_list) do
                        if hasKey(secret, "tiles") then
                            for idx,x in pairs(secret.tiles.x) do
                                local y = secret.tiles.y[idx]
                                if x - x % 16 == region_pos.x and y - y % 16 == region_pos.y then
                                    secret.triggered = false
                                    break
                                end
                            end
                        elseif hasKey(secret, "coffin_pos") then
                            if secret.coffin_pos.x - secret.coffin_pos.x % 16 == region_pos.x
                                and secret.coffin_pos.y - secret.coffin_pos.y % 16 == region_pos.y
                            then
                                secret.triggered = false
                            end
                        elseif hasKey(secret, "pos") then
                            if secret.pos.x - secret.pos.x % 16 == region_pos.x
                                and secret.pos.y - secret.pos.y % 16 == region_pos.y
                            then
                                secret.triggered = false
                            end
                        end
                    end
                end

                -- Hide all the blocks under the surface of this column
                for z=column.z_shift, avg_tile_height do
                    ---@type map_block
                    local block = dfhack.maps.getTileBlock(region_pos.x, region_pos.y, z)
                    if block then
                        for _,y_list in pairs(block.designation) do
                            for _,tile_designation in pairs(y_list) do
                                tile_designation.hidden = true
                            end
                        end
                    end
                end

                -- Hide/Reveal tiles that are above/below the column surface
                for x,y_list in pairs(column.elevation) do
                    for y,elevation in pairs(y_list) do
                        local tile_height = elevation - column.z_base - 1
                        if tile_height ~= avg_tile_height then
                            for z=tile_height + 1, avg_tile_height, sign(avg_tile_height - tile_height) do
                                local designation = dfhack.maps.getTileFlags(x, y, z)
                                designation.hidden = not designation.hidden
                            end
                        end
                    end
                end
            end
        end
    end
end

---@type table<string, fun(site: world_site, new_rect: coord_rect)>
local preserveData = {
    ["units"] = function(site, new_rect)
        ---@type _world_units_active|unit[]
        local units_active = df.global.world.units.active

        -- Find any units that are outside of the new rect
        for _,unit in pairs(units_active) do
            if not isInRect(unit.pos, new_rect) then
                -- Add the unit to the preserved list
                local global_x_pos = site.global_min_x * 48 + unit.pos.x
                local global_y_pos = site.global_min_y * 48 + unit.pos.y
                preserved_data.insertUnit(unit, { x= global_x_pos, y= global_y_pos, z= unit.pos.z })

                -- Put the unit in the storage cage, making them immobile and invisible
                ---@type general_ref
                local ref = df.general_ref_contained_in_itemst:new()
                ref.item_id = preserved_data.cage.id
                unit.general_refs:insert('#', ref)
                ref = df.general_ref_contains_unitst:new()
                ref.unit_id = unit.id
                preserved_data.cage.general_refs:insert('#', ref)
                unit.flags1.caged = true
            end
        end
    end,
    ["items"] = function(site, new_rect)
        ---@type _world_items_all|item[]
        local items_all = df.global.world.items.all

        -- Find any items that are outside of the new rect
        for _,item in pairs(items_all) do
            if not isInRect(item.pos, new_rect) then
                -- Add the item to the preserved list
                local global_x_pos = site.global_min_x * 48 + item.pos.x
                local global_y_pos = site.global_min_y * 48 + item.pos.y
                preserved_data.insertItem(item, { x= global_x_pos, y= global_y_pos, z= item.pos.z })

                -- Forbid and hide the item
                item.flags.forbid = true
                item.flags.hidden = true
            end
        end
    end,
}

---@type table<string, fun(site: world_site, new_global_rect: coord_rect)>
local recoverData = {
    ["units"] =  function(site, new_global_rect)
        -- Find the preserved units that lie inside the new rect
        for x,y_list in pairs(preserved_data.units) do
            if x >= new_global_rect.x1 and x <= new_global_rect.x2 then
                for y,z_list in pairs(y_list) do
                    if y >= new_global_rect.y1 and y <= new_global_rect.y2 then
                        -- For each Z index of units inside the rect
                        for z,unit_list in pairs(z_list) do
                            for unit_id,unit in pairs(unit_list) do
                                -- If the unit exists
                                if unit then
                                    -- Delete all links connecting the unit and the cage
                                    for key,value in pairs(unit.general_refs) do
                                        if df.general_ref_contained_in_itemst:is_instance(value) and value.item_id == preserved_data.cage.id then
                                            unit.general_refs:erase(key)
                                            break
                                        end
                                    end
                                    for key,value in pairs(preserved_data.cage.general_refs) do
                                        if df.general_ref_contains_unitst:is_instance(value) and value.unit_id == unit.id then
                                            preserved_data.cage.general_refs:erase(key)
                                            break
                                        end
                                    end

                                    -- Uncage the unit and restore its position
                                    unit.flags1.caged = false
                                    unit.pos = xyz2pos(x - site.global_min_x * 48, y - site.global_min_y * 48, z)
                                end

                                -- Remove the unit from the list
                                unit_list[unit_id] = nil
                            end
                        end
                    end
                end
            end
        end
    end,
    ["items"] = function(site, new_global_rect)
        -- Find the preserved items that lie inside the new rect
        for x,y_list in pairs(preserved_data.items) do
            if x >= new_global_rect.x1 and x <= new_global_rect.x2 then
                for y,z_list in pairs(y_list) do
                    if y >= new_global_rect.y1 and y <= new_global_rect.y2 then
                        -- For each Z index of items inside the rect
                        for z,item_list in pairs(z_list) do
                            for item_id,item in pairs(item_list) do
                                -- If the item exists
                                if item then
                                    -- Unforbid and unhide the item
                                    item.flags.forbid = false
                                    item.flags.hidden = false
                                    item.pos = xyz2pos(x - site.global_min_x * 48, y - site.global_min_y * 48, z)
                                end

                                -- Remove the item from the list
                                item_list[item_id] = nil
                            end
                        end
                    end
                end
            end
        end
    end,
}

---@param nesw { n: integer, e: integer, s: integer, w: integer }
---@param keep_flags? { all: boolean, units: boolean, items: boolean, tiles: boolean }
local function resize(nesw, keep_flags)
    local site = df.global.plotinfo.main.fortress_site
    local store_season_tick = df.global.cur_season_tick
    local was_paused = df.global.pause_state
    ---@type { [1]: report[], [2]: report[], [3]: popup_message[], [4]: announcement_alertst[], [5]: integer[] }
    local alerts = {
        [1]= df.global.world.status.reports,
        [2]= df.global.world.status.announcements,
        [3]= df.global.world.status.popups,
        [4]= df.global.world.status.announcement_alert,
        [5]= df.global.world.status.alert_button_announcement_id
    }

    -- Record what alerts were present before resizing
    local previous_alerts = {}
    for key,value in pairs(alerts) do
        previous_alerts[key] = {}
        for k,_ in pairs(value) do
            previous_alerts[key][k] = true
        end
    end

    -- If any data type is set to be kept
    if keep_flags then
        local new_rect = {
            x1= nesw.w * -48,
            x2= (nesw.e + 1 + site.global_max_x - site.global_min_x) * 48 - 1,
            y1= nesw.n * -48,
            y2= (nesw.s + 1 + site.global_max_y - site.global_min_y) * 48 - 1
        }

        -- The in bounds position where the data will be stored
        local store_pos = {
            x= 1 + math.max(new_rect.x1, 0),
            y= 1 + math.max(new_rect.y1, 0),
            z= df.global.world.map.z_count - 1
        }
        shiftPreservedInBounds(store_pos)

        -- Loop through all the data types' preservation functions
        for key,func in pairs(preserveData) do
            if keep_flags.all or keep_flags[key] then
                func(site, new_rect)
            end
        end
    end

    site.global_min_x = site.global_min_x - nesw.w
    site.global_max_x = site.global_max_x + nesw.e
    site.global_min_y = site.global_min_y - nesw.n
    site.global_max_y = site.global_max_y + nesw.s
    df.global.cur_season_tick = 1999
    dfhack.timeout(1, "frames", function ()
        df.global.pause_state = false
    end)

    local after_resize = function() end
    after_resize = function ()
        if df.global.cur_season_tick >= 2000 then
            if was_paused then
                dfhack.run_command("fpause")
            end
            if store_season_tick % 2005 < 1990 then
                df.global.cur_season_tick = store_season_tick
            else
                df.global.cur_season_tick = store_season_tick + 15
            end

            -- Calculate the new region tiles that were created
            local new_region_tiles_set = {}
            for x=0, df.global.world.map.x_count_block - 1 do
                new_region_tiles_set[x] = new_region_tiles_set[x] or {}
                for y=0, (nesw.n * 3) - 1 do
                    new_region_tiles_set[x][y] = true
                end
                for y=df.global.world.map.y_count_block - nesw.s * 3, df.global.world.map.y_count_block - 1 do
                    new_region_tiles_set[x][y] = true
                end
            end
            for y=0, df.global.world.map.y_count_block - 1 do
                for x=df.global.world.map.x_count_block - nesw.e * 3, df.global.world.map.x_count_block - 1 do
                    new_region_tiles_set[x] = new_region_tiles_set[x] or {}
                    new_region_tiles_set[x][y] = true
                end
                for x=0, (nesw.w * 3) - 1 do
                    new_region_tiles_set[x] = new_region_tiles_set[x] or {}
                    new_region_tiles_set[x][y] = true
                end
            end
            -- Transform it from a set into a list
            local region_pos_list = {}
            for x,y_list in pairs(new_region_tiles_set) do
                for y,_ in pairs(y_list) do
                    table.insert(region_pos_list, { x= x * 16, y= y * 16})
                end
            end

            -- Unreveal the new region tiles
            hideTiles(region_pos_list)

            -- Erase any alerts that weren't present before resizing
            for key,value in pairs(alerts) do
                local erase = {}
                for k,_ in pairs(value) do
                    if not previous_alerts[key][k] then
                        table.insert(erase, k)
                    end
                end
                table.sort(erase, function(a,b) return a > b end)
                for _,k in pairs(erase) do
                    alerts[key]:erase(k)
                end
            end

            -- If any data type is set to be kept
            if keep_flags then
                local new_global_rect = {
                    x1= site.global_min_x * 48,
                    x2= (site.global_max_x + 1) * 48 - 1,
                    y1= site.global_min_y * 48,
                    y2= (site.global_max_y + 1) * 48 - 1
                }

                -- Loop through all the data types' recovery functions
                for key,func in pairs(recoverData) do
                    if keep_flags.all or keep_flags[key] then
                        func(site, new_global_rect)
                    end
                end

                -- The in bounds position where the data will be stored
                local store_pos = {
                    x= 1,
                    y= 1,
                    z= df.global.world.map.z_count - 1
                }
                shiftPreservedOutOfBounds(store_pos)
            end

            -- Save data to the site in order to restore on reload
            saveData()
        else
            if df.global.pause_state then
                df.global.pause_state = false
            end
            dfhack.timeout(1, "ticks", after_resize)
        end
    end

    after_resize()
end


--#region GUI

-- 'view' is only set after init() ends, so delay the dismiss 1 frame in order to allow init() to use it
local function selfDismiss()
    dfhack.timeout(1, 'frames', function()
        if view then
            view:dismiss()
        end
    end)
end

-- Draws a list of rects with associated pens, without overlapping the given screen rect
---@param draw_queue {pen: Pen, rect: { x1: integer, x2: integer, y1: integer, y2: integer } }[]
---@param screen_rect { x1: integer, x2: integer, y1: integer, y2: integer }
local function drawOutsideOfScreenRect(draw_queue, screen_rect)
    local view_dims = dfhack.gui.getDwarfmodeViewDims()
    local tile_view_size = { x= view_dims.map_x2 - view_dims.map_x1 + 1, y= view_dims.map_y2 - view_dims.map_y1 + 1 }
    local display_view_size = { x= df.global.init.display.grid_x, y= df.global.init.display.grid_y }
    local display_to_tile_ratio = { x= tile_view_size.x / display_view_size.x, y= tile_view_size.y / display_view_size.y }

    local screen_tile_rect = {
        x1= screen_rect.x1 * display_to_tile_ratio.x - 1,
        x2= screen_rect.x2 * display_to_tile_ratio.x + 1,
        y1= screen_rect.y1 * display_to_tile_ratio.y - 1,
        y2= screen_rect.y2 * display_to_tile_ratio.y + 1
    }

    for _,draw_rect in pairs(draw_queue) do
        -- If there is any overlap between the draw rect and the screen rect
        if screen_tile_rect.x1 < draw_rect.rect.x2
            and screen_tile_rect.x2 > draw_rect.rect.x1
            and screen_tile_rect.y1 < draw_rect.rect.y2
            and screen_tile_rect.y2 > draw_rect.rect.y1
        then
            local temp_rect = { x1= draw_rect.rect.x1, x2= draw_rect.rect.x2, y1= draw_rect.rect.y1, y2= draw_rect.rect.y2 }
            -- Draw to the left of the screen rect
            if temp_rect.x1 < screen_tile_rect.x1 then
                table.insert(draw_queue, {
                    pen= draw_rect.pen,
                    rect = {
                        x1= temp_rect.x1,
                        x2= math.min(temp_rect.x2, screen_tile_rect.x1),
                        y1= temp_rect.y1,
                        y2= temp_rect.y2
                    }
                })
                temp_rect.x1 = screen_tile_rect.x1
            end
            -- Draw to the right of the screen rect
            if temp_rect.x2 > screen_tile_rect.x2 then
                table.insert(draw_queue, {
                    pen= draw_rect.pen,
                    rect = {
                        x1= math.max(temp_rect.x1, screen_tile_rect.x2),
                        x2= temp_rect.x2,
                        y1= temp_rect.y1,
                        y2= temp_rect.y2
                    }
                })
                temp_rect.x2 = screen_tile_rect.x2
            end
            -- Draw above the screen rect
            if temp_rect.y1 < screen_tile_rect.y1 then
                table.insert(draw_queue, {
                    pen= draw_rect.pen,
                    rect = {
                        x1= temp_rect.x1,
                        x2= temp_rect.x2,
                        y1= temp_rect.y1,
                        y2= math.min(temp_rect.y2, screen_tile_rect.y1)
                    }
                })
                temp_rect.y1 = screen_tile_rect.y1
            end
            -- Draw below the screen rect
            if temp_rect.y2 > screen_tile_rect.y2 then
                table.insert(draw_queue, {
                    pen= draw_rect.pen,
                    rect = {
                        x1= temp_rect.x1,
                        x2= temp_rect.x2,
                        y1= math.max(temp_rect.y1, screen_tile_rect.y2),
                        y2= temp_rect.y2
                    }
                })
                temp_rect.y2 = screen_tile_rect.y2
            end

        -- No overlap
        else
            dfhack.screen.fillRect(draw_rect.pen, math.floor(draw_rect.rect.x1), math.floor(draw_rect.rect.y1), math.floor(draw_rect.rect.x2), math.floor(draw_rect.rect.y2), true)
        end
    end
end

-- Sets a TextButton widget's text, without the extra key text that's otherwise forced
local function setTextButtonText(text_button, text_obj)
    -- Format text_obj into { {text=''}, {text=''}, {text=''}}
    for i= #text_obj, 1, -1 do
        if type(text_obj[i]) == "string" then
            -- Newlines can't be put into {text=''} objects, they have to be passed as a string
            local lines = text_obj[i]:split(NEWLINE)
            table.remove(text_obj, i)
            local index = i
            for k,v in pairs(lines) do
                if k > 1 then
                    table.insert(text_obj, index, NEWLINE)
                    index = index + 1
                end
                if v ~= '' then
                    table.insert(text_obj, index, { text= v })
                    index = index + 1
                end
            end
        end
    end

    for _, value in pairs(text_obj) do
        if type(value) == "table" then
            value.key = text_button.label.key
            value.on_activate = text_button.label.on_activate
        end
    end

    text_button.label:setText(text_obj)

    for _,value in pairs(text_button.label.text_lines) do
        local temp = {}
        for key,val in pairs(value) do
            temp[key] = {}
            for k,v in pairs(val) do
                temp[key][k] = v
            end
            temp[key].key = nil
        end
        for k,v in pairs(temp) do
            value[k] = v
        end
    end
end

--================================--
--||           Resize           ||--
--================================--
-- Interface for resizing the site

---@class ResizeClass: Window
---@type ResizeClass
local Resize
Resize = defclass(Resize, widgets.Window --[[@as Window]])
Resize.ATTRS {
    frame_title="Resize Site",
    frame=STD_UI_AREA,
    frame_inset={b=1, t=1},
    interface_masks=DEFAULT_NIL,
    parent=DEFAULT_NIL,
    site=DEFAULT_NIL, ---@type world_site
    size={x=1,y=1},
    size_slider={x=1,y=1},
    size_slider_max={x=1,y=1},
    offset={x=1,y=1},
    offset_slider={x=1,y=1},
    cur_size={x=1,y=1},
    keepData=DEFAULT_NIL
}

function Resize:init()
    if not self.site then
        selfDismiss()
        return
    end

    self.cur_size = {
        x = self.site.global_max_x - self.site.global_min_x + 1,
        y = self.site.global_max_y - self.site.global_min_y + 1
    }

    self.size = { x= self.cur_size.x, y= self.cur_size.y }
    self.size_slider = { x= self.cur_size.x, y= self.cur_size.y }
    self.size_slider_max = { x= MAX_SITE_SIZE, y= MAX_SITE_SIZE }
    self.offset = { x= 0, y= 0 }
    self.offset_slider = { x= self.size_slider_max.x // 2 + 1, y= self.size_slider_max.y // 2 + 1 }

    -- Size Subviews
    local size_subviews = {
        --Text
        widgets.Label{
            frame={l=0},
            text={ 'Size' }
        },
        --Spacing after text
        widgets.Panel{ frame={h=1} },
        -- Resize Width Text
        widgets.Label{
            frame={l=0},
            text={
                'Width: ',
                { text=function() return self.size.x end }
            }
        },
        -- Resize Width Slider
        widgets.RangeSlider{
            frame={l=-1},
            num_stops=self.size_slider_max.x,
            get_left_idx_fn=function() return 0 end,
            get_right_idx_fn=function()
                return self.size_slider.x
            end,
            on_left_change=function() end,
            on_right_change=function(idx)
                self.size_slider.x = math.min(idx, self.size_slider_max.x)
                self.size.x = self.size_slider.x
                self:visualize()
            end
        },
        -- Spacing between sliders
        widgets.Panel{ frame={h=2} },
        -- Resize Height Text
        widgets.Label{
            frame={l=0},
            text={
                'Height: ',
                { text=function() return self.size.y end }
            }
        },
        -- Resize Height Slider
        widgets.RangeSlider{
            frame={l=-1},
            num_stops=self.size_slider_max.y,
            get_left_idx_fn=function() return 0 end,
            get_right_idx_fn=function()
                return self.size_slider.y
            end,
            on_left_change=function() end,
            on_right_change=function(idx)
                self.size_slider.y = math.min(idx, self.size_slider_max.y)
                self.size.y = self.size_slider.y
                self:visualize()
            end
        }
    }

    -- Offset Subviews
    local offset_subviews = {
        -- Text
        widgets.Label{
            frame={l=0},
            text={ 'Offset' }
        },
        -- Spacing after text
        widgets.Panel{ frame={h=1} },
        -- Horizontal Offset Text
        widgets.Label{
            frame={l=0},
            text={
                'Horizonal: ',
                { text=function() return self.offset.x end }
            }
        },
        -- Horizontal Offset Slider
        widgets.RangeSlider{
            frame={l=-1},
            num_stops=self.size_slider_max.x + 1,
            get_left_idx_fn=function() return 0 end,
            get_right_idx_fn=function()
                return self.offset_slider.x
            end,
            on_left_change=function() end,
            on_right_change=function(idx)
                self.offset_slider.x = math.min(idx, self.size_slider_max.x + 1)
                self.offset.x = self.offset_slider.x - self.size_slider_max.x // 2 - 1
                self:visualize()
            end
        },
        -- Spacing between sliders
        widgets.Panel{ frame={h=2} },
        -- Vertical Offset Text
        widgets.Label{
            frame={l=0},
            text={
                'Vertical: ',
                { text=function() return self.offset.y end }
            }
        },
        -- Vertical Offset Slider
        widgets.RangeSlider{
            frame={l=-1},
            num_stops=self.size_slider_max.y + 1,
            get_left_idx_fn=function() return 0 end,
            get_right_idx_fn=function()
                return self.offset_slider.y
            end,
            on_left_change=function() end,
            on_right_change=function(idx)
                self.offset_slider.y = math.min(idx, self.size_slider_max.y + 1)
                self.offset.y = self.offset_slider.y - self.size_slider_max.y // 2 - 1
                self:visualize()
            end
        }
    }

    self:addviews {
        -- Text
        widgets.Label{
            frame={l=1, t=0},
            text={
                "Resizing the current site"..NEWLINE,
                "- Save before erasing sections ", {text="recommended",pen=COLOR_YELLOW}, NEWLINE,
                "- Erased sections ", {text="can not",pen=COLOR_LIGHTRED}, " be restored"
            }
        },
        -- Size Subpanel
        widgets.ResizingPanel{
            frame={t=5},
            frame_style=gui.FRAME_INTERIOR,
            autoarrange_subviews=1,
            subviews=size_subviews
        },
        -- Offset Subpanel
        widgets.ResizingPanel{
            frame={t=16},
            frame_style=gui.FRAME_INTERIOR,
            autoarrange_subviews=1,
            subviews=offset_subviews
        },
        widgets.TextButton{
            frame={t=28, l=1, w=15, h=1},
            label='Resize',
            text_pen=COLOR_LIGHTRED,
            key='CUSTOM_ALT_R',
            on_activate=function() self:resize() end,
        },
        -- Exit
        widgets.HotkeyLabel{
            frame={l=1, b=0},
            key='LEAVESCREEN',
            label="Return to game",
            on_activate=function()
                repeat until not self:onInput{LEAVESCREEN=true}
                view:dismiss()
            end
        }
    }

    self:visualize()
end

function Resize:visualize()
    local min_x = self.offset.x * 48 - df.global.window_x
    local max_x = min_x + self.size.x * 48 - 1
    local min_y = self.offset.y * 48 - df.global.window_y
    local max_y = min_y + self.size.y * 48 - 1

    local draw_queue = {
        {
            pen= TILE_MAP.pens[TILE_MAP.getPenKey{n=true, e=false, s=false, w=false}],
            rect= { x1= min_x, x2= max_x, y1= min_y, y2= min_y }
        },
        {
            pen= TILE_MAP.pens[TILE_MAP.getPenKey{n=false, e=true, s=false, w=false}],
            rect= { x1= max_x, x2= max_x, y1= min_y, y2= max_y }
        },
        {
            pen= TILE_MAP.pens[TILE_MAP.getPenKey{n=false, e=false, s=true, w=false}],
            rect= { x1= min_x, x2= max_x, y1= max_y, y2= max_y }
        },
        {
            pen= TILE_MAP.pens[TILE_MAP.getPenKey{n=false, e=false, s=false, w=true}],
            rect= { x1= min_x, x2= min_x, y1= min_y, y2= max_y }
        },
        {
            pen= TILE_MAP.pens[TILE_MAP.getPenKey{n=true, e=false, s=false, w=true}],
            rect= { x1= min_x, x2= min_x, y1= min_y, y2= min_y }
        },
        {
            pen= TILE_MAP.pens[TILE_MAP.getPenKey{n=true, e=true, s=false, w=false}],
            rect= { x1= max_x, x2= max_x, y1= min_y, y2= min_y }
        },
        {
            pen= TILE_MAP.pens[TILE_MAP.getPenKey{n=false, e=true, s=true, w=false}],
            rect= { x1= max_x, x2= max_x, y1= max_y, y2= max_y }
        },
        {
            pen= TILE_MAP.pens[TILE_MAP.getPenKey{n=false, e=false, s=true, w=true}],
            rect= { x1= min_x, x2= min_x, y1= max_y, y2= max_y }
        },
    }

    -- If in graphics mode
    if dfhack.screen.inGraphicsMode() then
        -- Draw Outline
        for _,draw_rect in pairs(draw_queue) do
            dfhack.screen.fillRect(draw_rect.pen, math.floor(draw_rect.rect.x1), math.floor(draw_rect.rect.y1), math.floor(draw_rect.rect.x2), math.floor(draw_rect.rect.y2), true)
        end

        -- Fill Center
        local pen = TILE_MAP.pens[TILE_MAP.getPenKey{n=false, e=false, s=false, w=false}]
        dfhack.screen.fillRect(pen, min_x + 1, min_y + 1, max_x - 1, max_y - 1, true)

    -- If in ASCII mode
    elseif self.frame_rect then
        -- Draw the outline, avoiding the GUI
        drawOutsideOfScreenRect(draw_queue, self.frame_rect)
    end
end

function Resize:onRender()
    self:visualize()
end

function Resize:resize()
    view:dismiss()
    resize({
        n= -self.offset.y,
        e= self.size.x - self.cur_size.x + self.offset.x,
        s= self.size.y - self.cur_size.y + self.offset.y,
        w= -self.offset.x
    }, self.keepData)
end

function Resize:onInput(keys)
    if keys._MOUSE_R and self:getMouseFramePos() then
        return false
    end
    if keys.LEAVESCREEN or keys._MOUSE_R then
        return false
    end
    if Resize.super.onInput(self, keys) then
        return true
    end
    if keys._MOUSE_L then
        if self:getMouseFramePos() then return true end
        for _,mask_panel in ipairs(self.interface_masks) do
            if mask_panel:getMousePos() then return true end
        end
    end
    view:sendInputToParent(keys)
    return true
end

--================================--
--||           Nomad           ||--
--================================--
-- Simpler interface for constant moving/resizing of the site

local DEFAULT_BTN_LABELS = {
    { top=" N ", bot=" ^ " },
    { top=" E ", bot=" > " },
    { top=" S ", bot=" v " },
    { top=" W ", bot=" < " },
}
local SHRINK_BTN_LABELS = {
    { top=" N ", bot=" v " },
    { top=" E ", bot=" < " },
    { top=" S ", bot=" ^ " },
    { top=" W ", bot=" > " },
}

---@class NomadClass: Window
---@type NomadClass
local Nomad
Nomad = defclass(Nomad, widgets.Window --[[@as Window]])
Nomad.ATTRS {
    frame_title="Nomad",
    frame=NOMAD_UI_AREA,
    frame_inset={b=1, t=1},
    interface_masks=DEFAULT_NIL,
    parent=DEFAULT_NIL,
    site=DEFAULT_NIL, ---@type world_site
    mode=DEFAULT_NIL,
    modes={
        ['move']   = { text=' Move Site ', pen=COLOR_CYAN, btn_labels= DEFAULT_BTN_LABELS },
        ['grow']   = { text=' Grow Site ', pen=COLOR_LIGHTBLUE, btn_labels= DEFAULT_BTN_LABELS },
        ['shrink'] = { text='Shrink Site', pen=COLOR_LIGHTMAGENTA, btn_labels= SHRINK_BTN_LABELS }
    },
    mode_order={ 'move', 'grow', 'shrink' },
    btn_labels=DEFAULT_NIL,
    keepData=DEFAULT_NIL
}

function Nomad:init()
    if not self.site then
        selfDismiss()
        return
    end

    self:cycleMode()

    local controls_subviews = {
        widgets.TextButton{
            frame={t=0, l=9, w=5, h=2},
            label="N",
            text_pen=COLOR_GREEN,
            key='CUSTOM_ALT_W',
            on_activate=function() self:doAction({ n=1, e=0, s=0, w=0 }) end,
        },
        widgets.TextButton{
            frame={t=2, l=14, w=5, h=2},
            label="E",
            text_pen=COLOR_GREEN,
            key='CUSTOM_ALT_D',
            on_activate=function() self:doAction({ n=0, e=1, s=0, w=0 }) end,
        },
        widgets.TextButton{
            frame={t=4, l=9, w=5, h=2},
            label="S",
            text_pen=COLOR_GREEN,
            key='CUSTOM_ALT_S',
            on_activate=function() self:doAction({ n=0, e=0, s=1, w=0 }) end,
        },
        widgets.TextButton{
            frame={t=2, l=4, w=5, h=2},
            label="W",
            text_pen=COLOR_GREEN,
            key='CUSTOM_ALT_A',
            on_activate=function() self:doAction({ n=0, e=0, s=0, w=1 }) end,
        }
    }
    for key, value in pairs(controls_subviews) do
        setTextButtonText(value, {{ text= function() return self.btn_labels[key].top end }, NEWLINE, { text= function() return self.btn_labels[key].bot end }})
    end

    self:addviews {
        -- Text
        widgets.Label{
            frame={l=1, t=0},
            text={
                "- Move ", {text="everything",pen=COLOR_YELLOW}, " before "..NEWLINE.." erasing", NEWLINE,
                "- Erased sections ", {text="can not",pen=COLOR_LIGHTRED}, NEWLINE.." be restored"
            }
        },
        -- Control Mode Text
        widgets.Label{
            frame={l=7, t=5},
            text={
                {
                    text=function() return self.modes[self.mode].text end,
                    pen=function() return self.modes[self.mode].pen end
                }
            }
        },
        -- Controls Subpanel
        widgets.ResizingPanel{
            frame={t=6},
            frame_style=gui.FRAME_INTERIOR,
            autoarrange_subviews=false,
            subviews=controls_subviews
        },
        widgets.TextButton{
            frame={t=15, l=1, w=15, h=1},
            label='Change Mode',
            text_pen=COLOR_LIGHTRED,
            key='CUSTOM_ALT_R',
            on_activate=function() self:cycleMode() end,
        },
        -- Keybind Text
        widgets.Label{
            frame={t=16, l=1, w=16, h=1},
            text={
                {text="[",pen=COLOR_RED},
                {text="Alt+wasd",pen=COLOR_LIGHTGREEN},
                {text=": NESW",pen=COLOR_GREEN},
                {text="]",pen=COLOR_RED}
            }
        },
        -- Exit
        widgets.HotkeyLabel{
            frame={l=1, b=0},
            key='LEAVESCREEN',
            label="Return to game",
            on_activate=function()
                repeat until not self:onInput{LEAVESCREEN=true}
                view:dismiss()
            end
        }
    }
end

function Nomad:doAction(nesw)
    if self.mode == 'move' then
        resize({
            n= nesw.n - nesw.s,
            e= nesw.e - nesw.w,
            s= nesw.s - nesw.n,
            w= nesw.w - nesw.e
        }, self.keepData)
    elseif self.mode == 'grow' then
        resize({
            n= nesw.n,
            e= nesw.e,
            s= nesw.s,
            w= nesw.w
        }, self.keepData)
    elseif self.mode == 'shrink' then
        resize({
            n= -nesw.n,
            e= -nesw.e,
            s= -nesw.s,
            w= -nesw.w
        }, self.keepData)
    end
end

function Nomad:cycleMode()
    for i,value in pairs(self.mode_order) do
        if value == self.mode then
            self.mode = self.mode_order[i % #self.mode_order + 1]
            self.btn_labels = self.modes[self.mode].btn_labels
            return
        end
    end

    self.mode = self.mode_order[1]
    self.btn_labels = self.modes[self.mode].btn_labels
end

function Nomad:onInput(keys)
    if keys._MOUSE_R and self:getMouseFramePos() then
        return false
    end
    if keys.LEAVESCREEN or keys._MOUSE_R then
        return false
    end
    if Resize.super.onInput(self, keys) then
        return true
    end
    if keys._MOUSE_L then
        if self:getMouseFramePos() then return true end
        for _,mask_panel in ipairs(self.interface_masks) do
            if mask_panel:getMousePos() then return true end
        end
    end
    view:sendInputToParent(keys)
    return true
end

--================================--
--||          ViewMask          ||--
--================================--
-- Draws a transparent box to the UI layer, erasing any on-screen UI behind it

local ViewMask
ViewMask = defclass(ViewMask, widgets.Panel --[[@as Panel]])
ViewMask.ATTRS{
    frame_background=gui.TRANSPARENT_PEN --gui.CLEAR_PEN
}

--================================--
--||        ResizeScreen        ||--
--================================--
-- The base UI element that contains the visual widgets

---@class ResizeScreenClass: ZScreen
---@type ResizeScreenClass
local ResizeScreen
ResizeScreen = defclass(ResizeScreen, gui.ZScreen)
ResizeScreen.ATTRS{
    focus_path="resize",
    force_pause=true,
    defocusable=false,
    mode='standard',
    keepData=DEFAULT_NIL
}

function ResizeScreen:init()
    local mask_panel = widgets.Panel{
        view_id="panel",
        subviews={
            ViewMask{frame={l=0, r=0, b=0, h=3}},
        }
    }

    local site = df.global.plotinfo.main.fortress_site
    if not site then
        selfDismiss()
        return
    end

    if self.mode == 'nomad' then
        self.force_pause = false
        self:addviews{
            mask_panel,
            Nomad {
                view_id="nomad",
                interface_masks=mask_panel.subviews,
                parent=self,
                site=site,
                keepData=self.keepData
            }
        }
    else
        self:addviews{
            mask_panel,
            Resize {
                view_id="resize",
                interface_masks=mask_panel.subviews,
                parent=self,
                site=site,
                keepData=self.keepData
            }
        }
    end
end

function ResizeScreen:onRender(dc)
    ResizeScreen.super.render(self, dc)

    if self.subviews.resize then
        self.subviews.resize:onRender()
    end
end

function ResizeScreen:onDismiss()
    -- Global variable 'view' can be used to check if the gui is already open
    view = nil
end

--================================--
--||        UpdateWidget        ||--
--================================--
-- Can be enabled/disabled from gui/control-panel
-- Handles updating from the background, with no UI

UpdateWidget = defclass(UpdateWidget, overlay.OverlayWidget)
UpdateWidget.ATTRS{
    name='Nomad Updater',
    version='1.0',
    desc='Widget attempt',
    default_enabled=false,
    hotspot=true,
    overlay_onupdate_max_freq_seconds=1000000,
    overlay_only=true,
    viewscreens={'dwarfmode'},
    isInitialized = false
}

OVERLAY_WIDGETS = {
    [WIDGET_NAME]=UpdateWidget,
}

function isWidgetEnabled()
    local config = overlay.get_state().config
    return config and config[SCRIPT_NAME.."."..WIDGET_NAME] and config[SCRIPT_NAME.."."..WIDGET_NAME].enabled or false
end

function UpdateWidget:setUpdateFrequency()
    local rel_tick = df.global.cur_season_tick % 2000
    -- Set frequency to between 0s and 120s, depending on the time until cur_season_tick reaches 2000
    -- - 0.15 is approximately the ratio between season ticks and frame rate, with 100 frames increasing cur_season_tick by 15
    self.overlay_onupdate_max_freq_seconds = rel_tick == 0 and 0 or math.min(120, math.max(0, (1995 - rel_tick) / (df.global.enabler.fps * 0.15 * 10)))
end

function UpdateWidget:loadState()
    self.isInitialized = true
    loadData()
end

function UpdateWidget:unloadState()
    self.isInitialized = false
    shiftPreservedInBounds()
    preserved_data = PRESERVED_DATA_DEFAULT
end

function UpdateWidget:init()
    if dfhack.gui.getViewscreenByType(df.viewscreen_dwarfmodest --[[@as _viewscreen]], -1) then
        self:loadState()
        self:setUpdateFrequency()

        dfhack.onStateChange.resize_site = function(state)
            if state == SC_MAP_UNLOADED or state == SC_WORLD_UNLOADED then
                self:unloadState()
            end
        end
    else
        self.isInitialized = false
    end
end

function UpdateWidget:overlay_onupdate()
    if self.isInitialized then
        self:setUpdateFrequency()
        local rel_tick = df.global.cur_season_tick % 2000
        if rel_tick > 1995 then
            shiftPreservedInBounds()
        elseif rel_tick > 0 and rel_tick < 5 then
            shiftPreservedOutOfBounds()
        end
    end
end

function UpdateWidget:onDismiss()
    self:unloadState()
    dfhack.onStateChange.resize_site = nil
end

--#endregion

function main(...)
    local args = {...}
    local positionals = argparse.processArgsGetopt(args, {
        { 'h', 'help', handler = function() args.help = true end },
        { nil, 'nomad', handler = function() args.nomad = true end },
        { 'k', 'keepData', handler = function(param) args.keepData = param end, hasArg = true }
    })

    -- If '--help'
    if args.help
        or positionals
        and (
            positionals[1] == "h"
            or positionals[1] == "help"
            or positionals[1] == "?"
        )
    then
        print(help)
    else
        -- If in fortress mode
        if dfhack.isMapLoaded() and df.global.gamemode == df.game_mode.DWARF then
            local keepDataString = tostring(args.keepData):lower()
            local keepNothing = keepDataString == "none"

            -- If the widget is enabled in gui/control-panel, or no data is to be preserved
            if isWidgetEnabled() or keepNothing then
                local keepData = keepNothing and nil or KEEP_DATA_DEFAULT
                if args.keepData and keepDataString and not keepNothing then
                    print(args.keepData)
                    keepData = {}
                    local elements = keepDataString:split(',')
                    for _, value in pairs(elements) do
                        if value == "unit" or value == "units" then
                            keepData.units = true
                        elseif value == "item" or value == "items" then
                            keepData.items = true
                        else
                            dfhack.printerr("Error: '"..value.."' is not an accepted keepData parameter")
                            return
                        end
                    end
                end
                view = view and view:raise() or ResizeScreen{ keepData= keepData, mode= args.nomad and 'nomad' or 'standard' }:show()

            -- If the widget isn't enabled, and attempting to run with data preservation
            else
                dfhack.printerr(
                    "Error: "..SCRIPT_NAME.." requires its widget to be enabled in order to be used"..NEWLINE
                    .."The widget runs in the background and takes care of preserving unloaded data"..NEWLINE
                    ..NEWLINE
                    .."It can be enabled in 'gui/control-panel,' under the 'UI Overlays' tab, with the name '"..SCRIPT_NAME.."."..WIDGET_NAME.."'"..NEWLINE
                    ..NEWLINE
                    .."Otherwise you can also use the '--keepData none' option to disable all data preservation"
                )
            end

        -- If not currently in fortress mode
        else
            dfhack.printerr(SCRIPT_NAME.." requires a loaded fortress to work")
        end
    end
end

if not dfhack_flags.module then
    main(...)
end