-- Keep inventory operations in one place. A failed or missing export fails closed.
AmmoInventory = {}

local function call(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then
        return false, ('%s is not running.'):format(resource)
    end
    local ok, a, b = pcall(function(...) return exports[resource][method](exports[resource], ...) end, ...)
    if not ok then return false, ('%s.%s unavailable: %s'):format(resource, method, tostring(a)) end
    return true, a, b
end

local function succeeded(result)
    return result == true or (type(result) == 'number' and result > 0)
        or (type(result) == 'table' and (result.success == true or result.ok == true))
end

function AmmoInventory.consume(src, item)
    if Config.AmmoInventory == 'ox' then
        local ok, count = call('ox_inventory', 'GetItemCount', src, item)
        if not ok then return false, count end
        if type(count) ~= 'number' or count < 1 then return false, 'You need ' .. item .. '.' end
        local removed, result, err = call('ox_inventory', 'RemoveItem', src, item, 1)
        if not removed then return false, result end
        return succeeded(result), succeeded(result) and nil or (err or 'Could not remove ammunition.')
    end
    if Config.AmmoInventory == 'seam' then
        -- The SeaM_Inventory integration expects RemoveItem(source, name, amount)
        -- to return true or a positive count, and AddItem for a failed DB write.
        local ok, result, err = call('SeaM_Inventory', 'RemoveItem', src, item, 1)
        if not ok then return false, result end
        return succeeded(result), succeeded(result) and nil or (err or 'You need ' .. item .. '.')
    end
    return false, 'Configure Config.AmmoInventory before loading ammunition.'
end

function AmmoInventory.refund(src, item)
    local resource = Config.AmmoInventory == 'ox' and 'ox_inventory' or 'SeaM_Inventory'
    local ok, result, err = call(resource, 'AddItem', src, item, 1)
    if not ok or not succeeded(result) then
        print(('[SeaM_Vehicles] URGENT: refund one %s to player %s manually (%s)')
            :format(item, src, tostring(err or result)))
        return false
    end
    return true
end
