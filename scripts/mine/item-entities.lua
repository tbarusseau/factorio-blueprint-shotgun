local utils = require("scripts/utils") --[[@as BlueprintShotgun.utils]]
local vec = require("scripts/vector") --[[@as BlueprintShotgun.vector]]
local render = require("scripts/render") --[[@as BlueprintShotgun.render]]

local ultracube_active = script.active_mods["Ultracube"]

---@param params BlueprintShotgun.HandlerParams
return function(params)
    local entities = utils.find_entities_in_radius(params.surface, {
        type = "item-entity",
        position = params.target_pos,
        radius = params.radius,
    })
    table.sort(entities, utils.distance_sort(params.target_pos))

    if #entities == 0 then return end

    local vacuum_limit = 4 + params.bonus * 2
    for _, entity in pairs(entities) do
        game.play_sound{path = "utility/picked_up_item", position = entity.position}

        local position = entity.position
        local stack = entity.stack
        local sprite, shadow = render.draw_new_item(entity.surface, stack.name, entity.position, 0, 0)
        sprite.move_to_back()
        local slot = game.create_inventory(1)
        local vacuum_item = {
            slot = slot,
            surface = params.surface,
            character = params.character,
            time = 0,
            position = position,
            velocity = vec.random(1/60),
            height = 0,
            orientation_deviation = utils.orientation_deviation(),
            sprite = sprite,
            shadow = shadow,
            deconstruct = entity.to_be_deconstructed() and params.character.force or nil,
        }
        storage.vacuum_items[sprite.id] = vacuum_item
        slot[1].transfer_stack(stack) -- destroys the item

        if ultracube_active then
            local name = vacuum_item.name
            if storage.cubes[name] then
                vacuum_item.ultracube_token = utils.create_ultracube_token(name, slot[1].count, params.surface, position, vacuum_item.velocity, 0)
            end
        end

        params.ammo_item.drain_ammo(0.125)
        if not params.ammo_item.valid_for_read then break end

        vacuum_limit = vacuum_limit - 1
        if vacuum_limit == 0 then break end
    end

    return true
end