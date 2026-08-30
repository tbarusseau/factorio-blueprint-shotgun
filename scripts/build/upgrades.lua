local utils = require("scripts/utils") --[[@as BlueprintShotgun.utils]]
local render = require("scripts/render") --[[@as BlueprintShotgun.render]]

---@class BlueprintShotgun.upgrades
local lib = {}

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    if params.ammo_limit == 0 then return end

    local entities = utils.find_entities_in_radius(params.surface, {
        to_be_upgraded = true,
        position = params.target_pos,
        radius = params.radius,
    }, true)
    table.sort(entities, utils.distance_sort(params.target_pos))
    utils.arc_cull(entities, params.character.position, params.target_pos)

    local used = false

    for _, entity in pairs(entities) do
        if storage.to_upgrade[entity.unit_number] then goto continue end
        local upgrade_target, quality = entity.get_upgrade_target()
        ---@cast upgrade_target -?
        ---@cast quality -?

        local item, stack = utils.find_place_result_stack(params.inventory, upgrade_target.items_to_place_this, quality)
        if not item then goto continue end
        ---@cast stack -?

        local connection
        if entity.type == "underground-belt" then
            connection = entity.neighbours
            if connection and connection.type == "underground-belt" then
                -- impossible for connection to not be marked for upgrade so no need to check
                item.count = item.count * 2
                if stack.count < item.count then goto continue end
                storage.to_upgrade[connection.unit_number] = true
            else
                connection = nil
            end
        end

        local slot = game.create_inventory(1)
        slot[1].transfer_stack(stack, item.count)

        local sprite, shadow = render.draw_new_item(params.surface, item.name, params.source_pos)
        local duration = utils.get_flying_item_duration(params.source_pos, entity.position)
        storage.flying_items[sprite.id] = {
            action = "upgrade",
            slot = slot,
            surface = params.surface,
            force = params.force,
            source_pos = params.source_pos,
            target_pos = entity.position,
            start_tick = params.tick,
            end_tick = params.tick + duration,
            orientation_deviation = utils.orientation_deviation(),
            target_entity = entity,
            unit_number = entity.unit_number,
            sprite = sprite,
            shadow = shadow,
            connection = connection,
        } --[[@as FlyingUpgradeItem]]

        storage.to_upgrade[entity.unit_number] = true

        used = true
        params.ammo_item.drain_ammo(1)
        params.ammo_limit = params.ammo_limit - 1
        if params.ammo_limit <= 0 then break end

        ::continue::
    end

    return used
end

---@param entity LuaEntity
---@return ItemStackDefinition?
local function old_form_stack(entity)
    local place_item = entity.prototype.items_to_place_this[1]
    if not place_item then return end
    return {
        name = place_item.name,
        count = place_item.count,
        quality = entity.quality.name,
        health = entity.get_health_ratio() or 1,
    }
end

---@param item FlyingUpgradeItem
local function upgrade(item)
    local entity = item.target_entity --[[@as LuaEntity]]
    if not (entity.valid and entity.to_be_upgraded) then return end

    local old_stack = old_form_stack(entity)

    local connection = item.connection
    local connection_position, connection_old_stack
    if connection and connection.valid then
        connection_position = connection.position
        connection_old_stack = old_form_stack(connection)
    end

    local success = entity.apply_upgrade()

    if not success then
        if entity.valid then entity.cancel_upgrade(entity.force) end
    else
        success.surface.play_sound { path = 'entity-build/' .. success.name, position = success.position }
        if old_stack then
            item.surface.spill_item_stack{position = item.target_pos, stack = old_stack, force = item.force, allow_belts = false}
        end
        if connection_old_stack then
            item.surface.spill_item_stack{position = connection_position, stack = connection_old_stack, force = item.force, allow_belts = false}
        end
    end

    return success
end

---@param item FlyingUpgradeItem
function lib.action(item)
    if not upgrade(item) then
        utils.spill_item(item)
    end
    storage.to_upgrade[item.unit_number] = nil
end

return lib

---@class FlyingUpgradeItem:FlyingItemBase
---@field action "upgrade"
---@field target_entity LuaEntity
---@field unit_number uint
---@field connection LuaEntity?