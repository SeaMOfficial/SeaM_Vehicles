local Core = exports.SeaM_Core:GetCoreObject()
local active, busy, shots, weaponBusy, aimSessions = {}, {}, {}, {}, {}
local ready = false

local function notice(src, message, kind)
    exports.SeaM_Core:Notify(src, message, kind or 'error')
end

local function citizen(src)
    return exports.SeaM_Core:GetCitizenId(src)
end

local function garageAt(src, name)
    local def = type(name) == 'string' and Config.Garages[name]
    local ped = GetPlayerPed(src)
    if not def or ped == 0 then return nil end
    if #(GetEntityCoords(ped) - def.point) > Config.InteractDistance + 1.0 then return nil end
    return def
end

local function rowFor(src, id)
    id = tonumber(id)
    if not ready or not id or id < 1 or id % 1 ~= 0 then return nil end
    local owner = citizen(src)
    if not owner then return nil end
    return MySQL.single.await('SELECT * FROM seam_vehicles WHERE id = ? AND owner = ?', { id, owner })
end

local function mountFor(model, key)
    local config = type(model) == 'string' and Config.VehicleModels[model:lower()]
    local mount = config and type(key) == 'string' and config[key]
    if type(mount) ~= 'table' or type(mount.bone) ~= 'string' or mount.bone == ''
        or (mount.type ~= 'cannon' and mount.type ~= 'machinegun' and mount.type ~= 'stash') then
        return nil
    end
    return mount
end

local function mountForEntity(entity, key)
    local hash = GetEntityModel(entity)
    for model in pairs(Config.VehicleModels) do
        if joaat(model) == hash then return mountFor(model, key) end
    end
end

local function installed(row)
    local ok, decoded = pcall(json.decode, row.equipment or '[]')
    if not ok or type(decoded) ~= 'table' then return {} end
    local result, known = {}, {}
    for _, entry in ipairs(decoded) do
        local key = type(entry) == 'table' and entry.key or entry
        if type(key) == 'string' and mountFor(row.model, key) and not known[key] then
            result[#result + 1] = { key = key }
            known[key] = true
        end
    end
    return result
end

-- Keep entries for models/keys temporarily absent from the new config. They
-- must stay in the database when an admin changes another installed item.
local function storedEquipment(row)
    local ok, decoded = pcall(json.decode, row.equipment or '[]')
    if not ok or type(decoded) ~= 'table' then return {} end
    local result, seen = {}, {}
    for _, entry in ipairs(decoded) do
        local key = type(entry) == 'table' and entry.key or entry
        if type(key) == 'string' and #key <= 40 and key:match('^[%w_]+$') and not seen[key] then
            result[#result + 1] = type(entry) == 'table' and entry or { key = key }
            seen[key] = true
        end
    end
    return result
end

local function entityFor(id, netId)
    local record = active[tonumber(id)]
    if not record then return nil end
    local entity = record.entity
    if not DoesEntityExist(entity) or NetworkGetNetworkIdFromEntity(entity) ~= tonumber(netId) then
        active[tonumber(id)] = nil
        return nil
    end
    if Entity(entity).state.seamVehicleId ~= tonumber(id) then return nil end
    return entity, record
end

local function ownerNear(src, id, netId, radius)
    local entity, record = entityFor(id, netId)
    if not entity or not record or citizen(src) ~= record.owner then return nil end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 0 then return nil end
    if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > radius then return nil end
    return entity, record
end

local function syncMounts(id, entity)
    local row = MySQL.single.await('SELECT model, equipment FROM seam_vehicles WHERE id = ?', { id })
    if not row or not DoesEntityExist(entity) then return end
    local mounts = installed(row)
    if active[id] then active[id].mounts = mounts end
    Entity(entity).state:set('seamEquipment', mounts, true)
end

local function weaponKey(id, key)
    local number = tonumber(id)
    if not number or number < 1 or number % 1 ~= 0 then return '' end
    return ('%d:%s'):format(number, key)
end

local function weaponLocked(id)
    for key in pairs(weaponBusy) do
        if key:sub(1, #tostring(id) + 1) == tostring(id) .. ':' then return true end
    end
    return false
end

local function syncAmmo(id, entity)
    if not DoesEntityExist(entity) then return end
    local rows = MySQL.query.await('SELECT mount_key, ammo_type, rounds FROM seam_vehicle_ammo WHERE vehicle_id = ?', { id })
    local state = {}
    for _, row in ipairs(rows or {}) do
        local mount = mountForEntity(entity, row.mount_key)
        if mount and mount.type ~= 'stash' and tonumber(row.rounds) > 0 then
            state[row.mount_key] = { ammoType = row.ammo_type, rounds = tonumber(row.rounds) }
        end
    end
    Entity(entity).state:set('seamAmmo', state, true)
end

CreateThread(function()
    while GetResourceState('SeaM_Core') ~= 'started' do Wait(200) end
    if not Core.DB.requireTables('vehicles', { 'seam_vehicles' }, 'SeaM_Vehicles/install/vehicles.sql') then return end
    local created, reason = pcall(MySQL.query.await, [[CREATE TABLE IF NOT EXISTS seam_vehicle_ammo (
        vehicle_id BIGINT UNSIGNED NOT NULL,
        mount_key VARCHAR(40) NOT NULL,
        ammo_type VARCHAR(40) NOT NULL,
        rounds INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (vehicle_id, mount_key),
        CONSTRAINT seam_vehicle_ammo_vehicle_fk FOREIGN KEY (vehicle_id)
            REFERENCES seam_vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not created then
        print('[SeaM_Vehicles] Cannot initialise ammunition table. Import install/weapons.sql: ' .. tostring(reason))
        return
    end
    -- A resource reload can leave OneSync entities alive. Adopt them so a
    -- second copy cannot be pulled out, then remove them cleanly on stop.
    for _, entity in ipairs(GetAllVehicles()) do
        local id = tonumber(Entity(entity).state.seamVehicleId)
        if id then
            local row = MySQL.single.await('SELECT owner, model, plate, kind FROM seam_vehicles WHERE id = ?', { id })
            if row and not active[id] and GetEntityModel(entity) == joaat(row.model)
                and GetVehicleNumberPlateText(entity):gsub('%s+$', '') == row.plate then
                active[id] = { entity = entity, owner = row.owner, kind = row.kind, model = row.model }
                syncMounts(id, entity)
                syncAmmo(id, entity)
            else
                DeleteEntity(entity)
            end
        end
    end
    ready = true
    print('[SeaM_Vehicles] garages and individual vehicle equipment ready')
end)

Core.Callbacks.register('vehicles:list', function(src, garageName)
    local garage = garageAt(src, garageName)
    if not ready or not garage then return false, 'Step closer to the garage.' end
    local rows = MySQL.query.await([[SELECT id, model, plate, label, kind FROM seam_vehicles
        WHERE owner = ? AND kind = ? ORDER BY id DESC]], { citizen(src), garage.kind })
    for _, row in ipairs(rows) do
        row.id = tonumber(row.id)
        local entity = active[row.id] and active[row.id].entity
        if entity and not DoesEntityExist(entity) then active[row.id] = nil; entity = nil end
        row.out = entity ~= nil
        local equipment = installed(MySQL.single.await('SELECT model, equipment FROM seam_vehicles WHERE id = ?', { row.id }) or {})
        row.mounts = #equipment
    end
    return rows, garage.label
end)

Core.Callbacks.register('vehicles:takeOut', function(src, garageName, id)
    local garage = garageAt(src, garageName)
    local row = garage and rowFor(src, id)
    if not row or row.kind ~= garage.kind then return false, 'Vehicle unavailable here.' end
    id = tonumber(id)
    if busy[id] or active[id] then return false, 'This vehicle is already out.' end
    local p = garage.spawn
    for _, entity in ipairs(GetAllVehicles()) do
        if DoesEntityExist(entity) and #(GetEntityCoords(entity) - vector3(p.x, p.y, p.z)) < 5.0 then
            return false, 'The launch space is occupied.'
        end
    end
    busy[id] = true
    local spawnType = row.kind == 'boat' and 'boat' or row.spawn_type
    local ok, vehicle = pcall(CreateVehicleServerSetter, joaat(row.model), spawnType,
        p.x, p.y, p.z, p.w)
    if not ok or not vehicle or vehicle == 0 then
        busy[id] = nil
        return false, 'Vehicle model could not be spawned.'
    end
    local deadline = GetGameTimer() + 5000
    while not DoesEntityExist(vehicle) and GetGameTimer() < deadline do Wait(50) end
    if not DoesEntityExist(vehicle) then
        busy[id] = nil
        return false, 'Vehicle spawn timed out.'
    end
    SetEntityHeading(vehicle, p.w)
    SetVehicleNumberPlateText(vehicle, row.plate)
    Entity(vehicle).state:set('seamVehicleId', id, true)
    local mounts = installed(row)
    Entity(vehicle).state:set('seamEquipment', mounts, true)
    syncAmmo(id, vehicle)
    local properties = nil
    if row.properties then
        local decoded, data = pcall(json.decode, row.properties)
        if decoded and type(data) == 'table' then properties = data end
    end
    active[id] = { entity = vehicle, owner = row.owner, kind = row.kind, model = row.model, mounts = mounts }
    busy[id] = nil
    return true, NetworkGetNetworkIdFromEntity(vehicle), properties
end)

local function safeProperties(data)
    if type(data) ~= 'table' then return {} end
    local result = {}
    for _, key in ipairs({ 'engine', 'body', 'dirt', 'fuel' }) do
        local n = tonumber(data[key])
        if n and n == n then result[key] = math.max(0, math.min(n, key == 'dirt' and 15 or 1000)) end
    end
    for _, key in ipairs({ 'primary', 'secondary', 'pearl', 'wheels', 'wheelType', 'tint', 'livery' }) do
        local n = tonumber(data[key])
        if n and n % 1 == 0 and n >= -1 and n <= 255 then result[key] = n end
    end
    result.extras, result.toggles = {}, {}
    for _, field in ipairs({ 'extras', 'toggles' }) do
        if type(data[field]) == 'table' then
            for i = 0, 20 do
                if field == 'extras' or i == 18 or i == 20 then
                    local value = data[field][tostring(i)]
                    if type(value) == 'boolean' then result[field][tostring(i)] = value end
                end
            end
            if field == 'toggles' and type(data[field]['22']) == 'boolean' then
                result.toggles['22'] = data[field]['22']
            end
        end
    end
    result.mods = {}
    if type(data.mods) == 'table' then
        for i = 0, 49 do
            local n = tonumber(data.mods[tostring(i)] or data.mods[i])
            if n and n % 1 == 0 and n >= -1 and n < 128 then result.mods[tostring(i)] = n end
        end
    end
    return result
end

Core.Callbacks.register('vehicles:store', function(src, garageName, id, netId, properties)
    local garage = garageAt(src, garageName)
    local row = garage and rowFor(src, id)
    if not row or row.kind ~= garage.kind then return false, 'This vehicle is not yours.' end
    id = tonumber(id)
    if busy[id] or weaponLocked(id) then return false, 'Vehicle is busy.' end
    local entity = ownerNear(src, id, netId, garage.storeRadius)
    if not entity or #(GetEntityCoords(entity) - garage.point) > garage.storeRadius then
        return false, 'Bring your vehicle to the garage.'
    end
    for _, playerId in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(tonumber(playerId))
        if ped ~= 0 and ped ~= GetPlayerPed(src) and GetVehiclePedIsIn(ped, false) == entity then
            return false, 'Passengers must leave first.'
        end
    end
    busy[id] = true
    local ok = MySQL.update.await('UPDATE seam_vehicles SET properties = ? WHERE id = ? AND owner = ?',
        { json.encode(safeProperties(properties)), id, row.owner })
    if ok == nil then busy[id] = nil; return false, 'Could not save the vehicle.' end
    exports.SeaM_Inventory:CloseVehicleStashes(id)
    for _, entry in ipairs(active[id].mounts or {}) do aimSessions[weaponKey(id, entry.key)] = nil end
    DeleteEntity(entity)
    active[id], busy[id] = nil, nil
    return true
end)

Core.Callbacks.register('vehicles:openHold', function(src, id, key, netId)
    id = tonumber(id)
    if not exports[GetCurrentResourceName()]:CanUseStash(src, id, key, netId) then
        return false, 'You cannot open this hold.'
    end
    local mount = mountFor(active[id].model, key)
    return exports.SeaM_Inventory:OpenVehicleStash(src, id, key, netId,
        mount.label or key:gsub('_', ' '), mount.slots or 40, mount.maxWeight or 100000)
end)

exports('CanUseStash', function(src, id, key, netId)
    if not ready or type(key) ~= 'string' then return false end
    local entity, record = entityFor(id, netId)
    if not entity or (Config.VehicleStashesOwnerOnly and record.owner ~= citizen(src)) then return false end
    local mount = mountFor(record.model, key)
    if not mount or mount.type ~= 'stash' then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 0 then return false end
    local reach = (Config.MountAccessDistance and Config.MountAccessDistance[record.kind])
        or Config.StashDistance
    if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > reach then return false end
    -- The server cache is authoritative; a client state bag cannot grant a mount.
    for _, entry in ipairs(record.mounts or {}) do
        if entry.key == key then return true end
    end
    return false
end)

local function weaponContext(src, id, key, netId)
    id = tonumber(id)
    if not id or id % 1 ~= 0 or type(key) ~= 'string' then
        return nil, nil, nil, 'Invalid weapon mount.'
    end
    local record = active[id]
    local reach = record and Config.MountAccessDistance and Config.MountAccessDistance[record.kind] or 9.0
    local entity, current = ownerNear(src, id, netId, reach)
    if not entity then return nil, nil, nil, 'Get closer to your vehicle.' end
    local mount = mountFor(current.model, key)
    if not mount or (mount.type ~= 'cannon' and mount.type ~= 'machinegun') then
        return nil, nil, nil, 'Invalid weapon mount.'
    end
    for _, entry in ipairs(current.mounts or {}) do
        if entry.key == key then return entity, current, mount end
    end
    return nil, nil, nil, 'That mount is not installed.'
end

local function ammoRow(id, key)
    return MySQL.single.await('SELECT ammo_type, rounds FROM seam_vehicle_ammo WHERE vehicle_id = ? AND mount_key = ?',
        { id, key })
end

Core.Callbacks.register('vehicles:loadWeapon', function(src, id, key, netId, ammoType)
    local entity, _, mount, err = weaponContext(src, id, key, netId)
    if not entity then return false, err end
    id = tonumber(id)
    local lock = weaponKey(id, key)
    if busy[id] or weaponBusy[lock] then return false, 'This mount is busy.' end
    local definition
    if mount.type == 'cannon' and ammoType == 'cannon' then
        definition = { item = Config.Weapons.cannon.item, rounds = 1, label = 'Cannonball' }
    elseif mount.type == 'machinegun' then
        definition = Config.Weapons.machinegun.boxes[ammoType]
    end
    if not definition then return false, 'Unknown ammunition.' end
    weaponBusy[lock] = true
    local loaded = ammoRow(id, key)
    if loaded and tonumber(loaded.rounds) > 0 then
        weaponBusy[lock] = nil
        return false, 'This mount already has ammunition loaded.'
    end
    local removed, reason = AmmoInventory.consume(src, definition.item)
    if not removed then weaponBusy[lock] = nil; return false, reason end
    local ok, changed = pcall(MySQL.update.await, [[INSERT INTO seam_vehicle_ammo
        (vehicle_id, mount_key, ammo_type, rounds) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE ammo_type = VALUES(ammo_type), rounds = VALUES(rounds)]],
        { id, key, ammoType, definition.rounds })
    if not ok or not changed then
        AmmoInventory.refund(src, definition.item)
        weaponBusy[lock] = nil
        return false, 'Ammunition could not be saved.'
    end
    syncAmmo(id, entity)
    weaponBusy[lock] = nil
    return true, ('Loaded %s (%d rounds).'):format(definition.label, definition.rounds)
end)

Core.Callbacks.register('vehicles:beginAim', function(src, id, key, netId)
    local entity, _, _, err = weaponContext(src, id, key, netId)
    if not entity then return false, err end
    id = tonumber(id)
    if busy[id] or weaponBusy[weaponKey(id, key)] then return false, 'This mount is busy.' end
    local row = ammoRow(id, key)
    if not row or tonumber(row.rounds) <= 0 then return false, 'Load ammunition first.' end
    aimSessions[weaponKey(id, key)] = { src = src, netId = tonumber(netId), expires = GetGameTimer() + 15000 }
    return true, tonumber(row.rounds), row.ammo_type
end)

RegisterNetEvent('SeaM_Vehicles:server:endAim', function(id, key)
    if type(key) ~= 'string' then return end
    local lock = weaponKey(id, key)
    if aimSessions[lock] and aimSessions[lock].src == source then aimSessions[lock] = nil end
end)

RegisterNetEvent('SeaM_Vehicles:server:keepAim', function(id, key, netId)
    local lock = type(key) == 'string' and weaponKey(id, key) or ''
    local session = aimSessions[lock]
    if session and session.src == source and session.netId == tonumber(netId) then
        local entity = weaponContext(source, id, key, netId)
        if entity then session.expires = GetGameTimer() + 15000
        else aimSessions[lock] = nil end
    end
end)

AddEventHandler('playerDropped', function()
    for key, session in pairs(aimSessions) do
        if session.src == source then aimSessions[key] = nil end
    end
end)

local function validDirection(entity, mount, direction)
    if type(direction) ~= 'table' then return false end
    local x, y, z = direction.x, direction.y, direction.z
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number'
        or x ~= x or y ~= y or z ~= z or math.abs(x) > 1 or math.abs(y) > 1 or math.abs(z) > 1 then
        return false
    end
    local length = math.sqrt(x*x + y*y + z*z)
    if math.abs(length - 1.0) > 0.025 then return false end
    local limits = Config.Weapons[mount.type]
    local pitch = math.deg(math.asin(z))
    if pitch < limits.minPitch - 2 or pitch > limits.maxPitch + 2 then return false end
    local base = -(GetEntityHeading(entity) + (mount.heading or 0))
    local heading = math.deg(math.atan(x, y))
    local delta = (heading - base + 180) % 360 - 180
    return math.abs(delta) <= limits.yawLimit + 3
end

Core.Callbacks.register('vehicles:fire', function(src, id, key, netId, direction)
    local entity, _, mount, err = weaponContext(src, id, key, netId)
    if not entity then return false, err end
    id = tonumber(id)
    local lock = weaponKey(id, key)
    local session = aimSessions[lock]
    local now = GetGameTimer()
    if not session or session.src ~= src or session.netId ~= tonumber(netId) or session.expires < now then
        return false, 'Aim the mount first.'
    end
    if not validDirection(entity, mount, direction) then return false, 'Outside the mount firing arc.' end
    if busy[id] or weaponBusy[lock] then return false, 'Mount is busy.' end
    local cooldown = mount.cooldown or (mount.type == 'cannon' and 3000 or 160)
    if shots[lock] and now - shots[lock] < cooldown then return false, 'Mount is cooling down.' end
    weaponBusy[lock] = true
    local ok, changed = pcall(MySQL.update.await, [[UPDATE seam_vehicle_ammo SET rounds = rounds - 1
        WHERE vehicle_id = ? AND mount_key = ? AND rounds > 0]], { id, key })
    if not ok or not changed then
        weaponBusy[lock] = nil
        return false, 'Could not save this shot. Try again.'
    end
    if changed < 1 then
        weaponBusy[lock] = nil
        return false, 'Out of ammunition.'
    end
    shots[lock] = GetGameTimer()
    session.expires = shots[lock] + 15000
    local remaining = ammoRow(id, key)
    syncAmmo(id, entity)
    weaponBusy[lock] = nil
    TriggerClientEvent('SeaM_Vehicles:client:shot', -1, src, netId, key, direction)
    return true, remaining and tonumber(remaining.rounds) or 0
end)

local function validModel(model)
    return type(model) == 'string' and #model > 0 and #model <= 40
        and model:match('^[%w_]+$') ~= nil
end

local function grant(owner, model, kind, label)
    if not ready or type(owner) ~= 'string' or #owner > 24 or not validModel(model)
        or (kind ~= 'boat' and kind ~= 'land') then return false, 'Invalid vehicle details.' end
    label = type(label) == 'string' and label:sub(1, 64) or model
    for _ = 1, 10 do
        local plate = ('SM%06d'):format(math.random(0, 999999))
        local ok, id = pcall(MySQL.insert.await, [[INSERT INTO seam_vehicles
            (owner, model, plate, label, kind, spawn_type, equipment) VALUES (?, ?, ?, ?, ?, ?, '[]')]],
            { owner, model, plate, label, kind,
              kind == 'boat' and 'boat' or
                  ((Config.VehicleModels[model:lower()] or {}).spawnType or 'automobile') })
        if ok and id then return id, plate end
    end
    return false, 'Could not allocate a unique registration.'
end

exports('GrantVehicle', grant)

local function modifyMount(id, key, add)
    id = tonumber(id)
    if not ready or not id or id < 1 or id % 1 ~= 0 or type(key) ~= 'string' then
        return false, 'Invalid mount.'
    end
    if busy[id] or weaponLocked(id) then return false, 'Vehicle is busy.' end
    busy[id] = true
    local row = MySQL.single.await('SELECT model, kind, equipment FROM seam_vehicles WHERE id = ?', { id })
    if not row or (row.kind ~= 'boat' and row.kind ~= 'land') then
        busy[id] = nil; return false, 'Vehicle not found.'
    end
    local mount = mountFor(row.model, key)
    if not mount then busy[id] = nil; return false, 'Configure this mount and its bone for the vehicle model first.' end
    local list = storedEquipment(row)
    local index
    for i, item in ipairs(list) do if item.key == key then index = i break end end
    if add and index then busy[id] = nil; return false, 'Already installed.' end
    if not add and not index then busy[id] = nil; return false, 'Not installed.' end
    if add then
        list[#list + 1] = { key = key }
    else
        if mount.type ~= 'stash' then
            local ammo = MySQL.single.await('SELECT rounds FROM seam_vehicle_ammo WHERE vehicle_id = ? AND mount_key = ?',
                { id, key })
            if ammo and tonumber(ammo.rounds) > 0 then
                busy[id] = nil
                return false, 'Fire the remaining ammunition before removing this mount.'
            end
        end
        if mount.type == 'stash' then
            local stashId = ('vessel:%d:%s'):format(id, key)
            local items = exports.SeaM_Inventory:GetStashItems(stashId)
            if not items then
                local stored = MySQL.single.await('SELECT items FROM seam_inventories WHERE id = ?', { stashId })
                if stored then local valid, decoded = pcall(json.decode, stored.items); items = valid and decoded or nil end
            end
            if items and next(items) then busy[id] = nil; return false, 'Empty the hold first.' end
        end
        table.remove(list, index)
        aimSessions[weaponKey(id, key)] = nil
    end
    local count = MySQL.update.await('UPDATE seam_vehicles SET equipment = ? WHERE id = ?', { json.encode(list), id })
    if count and count > 0 and active[id] and DoesEntityExist(active[id].entity) then
        if not add then exports.SeaM_Inventory:CloseVehicleStashes(id) end
        local visible = installed({ model = row.model, equipment = json.encode(list) })
        active[id].mounts = visible
        Entity(active[id].entity).state:set('seamEquipment', visible, true)
    end
    if count and count > 0 and not add and mount.type ~= 'stash' then
        MySQL.update.await('DELETE FROM seam_vehicle_ammo WHERE vehicle_id = ? AND mount_key = ?', { id, key })
    end
    busy[id] = nil
    return count and count > 0, count and nil or 'Database update failed.'
end

exports('InstallMount', function(id, key) return modifyMount(id, key, true) end)
exports('RemoveMount', function(id, key) return modifyMount(id, key, false) end)

RegisterCommand('seamgive', function(src, args)
    if src ~= 0 and not exports.SeaM_Core:HasGroup(src, 'admin') then return end
    local target, model, kind = tonumber(args[1]), args[2], args[3]
    if not target or not citizen(target) then
        if src ~= 0 then notice(src, 'Usage: /seamgive [player ID] [model] [land|boat] [label]') end
        return
    end
    local label = #args >= 4 and table.concat(args, ' ', 4) or model
    local id, plate = grant(citizen(target), model, kind, label)
    if not id then notice(src, plate) return end
    notice(target, ('Vehicle %s (%s) added to your garage.'):format(model, plate), 'success')
    if src ~= 0 then notice(src, ('Registered vehicle #%d (%s).'):format(id, plate), 'success') end
end, false)

RegisterCommand('seamfit', function(src, args)
    if src ~= 0 and not exports.SeaM_Core:HasGroup(src, 'admin') then return end
    if args[3] and args[3] ~= 'remove' then
        if src ~= 0 then notice(src, 'Usage: /seamfit [vehicle ID] [equipment key] [remove]') end
        return
    end
    local ok, err = modifyMount(args[1], args[2], args[3] ~= 'remove')
    if src ~= 0 then notice(src, ok and 'Mount updated.' or err, ok and 'success' or 'error') end
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id, record in pairs(active) do
        exports.SeaM_Inventory:CloseVehicleStashes(id)
        if DoesEntityExist(record.entity) then DeleteEntity(record.entity) end
    end
end)
