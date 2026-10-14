local Core = exports.SeaM_Core:GetCoreObject()
local current, opened, waiting = nil, false, false
local listedModels = {}

local function notify(message, kind)
    exports.SeaM_Core:Notify(message, kind or 'error')
end

local function close()
    if not opened then return end
    opened, current = false, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function refresh()
    if not current then return end
    local rows, label = Core.Callbacks.await('vehicles:list', current)
    if type(rows) ~= 'table' then
        notify(label or 'Garage unavailable.')
        close()
        return
    end
    listedModels = {}
    for _, vehicle in ipairs(rows) do listedModels[tonumber(vehicle.id)] = vehicle.model end
    SendNUIMessage({ action = 'open', garage = label, kind = Config.Garages[current].kind,
        vehicles = rows })
end

local function open(name)
    if opened or waiting or IsNuiFocused() or not exports.SeaM_Core:IsPlayerLoaded() then return end
    waiting = true
    current = name
    local rows, label = Core.Callbacks.await('vehicles:list', name)
    waiting = false
    if type(rows) ~= 'table' then
        current = nil
        notify(label or 'Garage unavailable.')
        return
    end
    listedModels = {}
    for _, vehicle in ipairs(rows) do listedModels[tonumber(vehicle.id)] = vehicle.model end
    opened = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', garage = label, kind = Config.Garages[name].kind,
        vehicles = rows })
end

local function props(vehicle)
    SetVehicleModKit(vehicle, 0)
    local mods = {}
    for i = 0, 49 do mods[tostring(i)] = GetVehicleMod(vehicle, i) end
    local primary, secondary = GetVehicleColours(vehicle)
    local pearl, wheels = GetVehicleExtraColours(vehicle)
    local extras = {}
    for i = 0, 20 do
        if DoesExtraExist(vehicle, i) then extras[tostring(i)] = IsVehicleExtraTurnedOn(vehicle, i) end
    end
    local toggles = {}
    for _, i in ipairs({ 18, 20, 22 }) do toggles[tostring(i)] = IsToggleModOn(vehicle, i) end
    return { engine = GetVehicleEngineHealth(vehicle), body = GetVehicleBodyHealth(vehicle),
        dirt = GetVehicleDirtLevel(vehicle), fuel = GetVehicleFuelLevel(vehicle), mods = mods,
        primary = primary, secondary = secondary, pearl = pearl, wheels = wheels,
        wheelType = GetVehicleWheelType(vehicle), tint = GetVehicleWindowTint(vehicle),
        livery = GetVehicleLivery(vehicle), extras = extras, toggles = toggles }
end

local function applyProps(vehicle, data)
    if type(data) ~= 'table' then return end
    if data.engine then SetVehicleEngineHealth(vehicle, data.engine) end
    if data.body then SetVehicleBodyHealth(vehicle, data.body) end
    if data.dirt then SetVehicleDirtLevel(vehicle, data.dirt) end
    if data.fuel then SetVehicleFuelLevel(vehicle, data.fuel) end
    if data.primary and data.secondary then SetVehicleColours(vehicle, data.primary, data.secondary) end
    if data.pearl and data.wheels then SetVehicleExtraColours(vehicle, data.pearl, data.wheels) end
    if data.wheelType then SetVehicleWheelType(vehicle, data.wheelType) end
    if data.tint then SetVehicleWindowTint(vehicle, data.tint) end
    SetVehicleModKit(vehicle, 0)
    if type(data.mods) == 'table' then
        for key, value in pairs(data.mods) do
            local slot, mod = tonumber(key), tonumber(value)
            if slot and mod and slot >= 0 and slot <= 49 and mod >= -1 then
                SetVehicleMod(vehicle, slot, mod, false)
            end
        end
    end
    if type(data.toggles) == 'table' then
        for key, on in pairs(data.toggles) do ToggleVehicleMod(vehicle, tonumber(key), on == true) end
    end
    if type(data.extras) == 'table' then
        for key, on in pairs(data.extras) do SetVehicleExtra(vehicle, tonumber(key), on and 0 or 1) end
    end
    if data.livery and data.livery >= 0 then SetVehicleLivery(vehicle, data.livery) end
end

local function localVehicle(id)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if tonumber(Entity(vehicle).state.seamVehicleId) == tonumber(id) then return vehicle end
    end
end

RegisterNUICallback('close', function(_, cb)
    close()
    cb({ ok = true })
end)

RegisterNUICallback('action', function(data, cb)
    if waiting or not opened or type(data) ~= 'table' then cb({ ok = false }) return end
    local id = tonumber(data.id)
    if not id or id < 1 or id % 1 ~= 0 then cb({ ok = false }) return end
    if not listedModels[id] then cb({ ok = false }) return end
    if data.type == 'takeOut' then
        local hash = joaat(listedModels[id])
        if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
            notify('This vehicle model is not streamed on your client.')
            cb({ ok = false })
            return
        end
    end
    waiting = true
    local garageName = current
    CreateThread(function()
        local ok, result, state
        if data.type == 'takeOut' then
            ok, result, state = Core.Callbacks.await('vehicles:takeOut', garageName, id)
            if ok then
                local deadline = GetGameTimer() + 5000
                local vehicle = NetworkGetEntityFromNetworkId(result)
                while vehicle == 0 and GetGameTimer() < deadline do
                    Wait(50)
                    vehicle = NetworkGetEntityFromNetworkId(result)
                end
                if vehicle ~= 0 then applyProps(vehicle, state) end
                notify('Vehicle launched.', 'success')
            end
        elseif data.type == 'store' then
            local vehicle = localVehicle(id)
            if vehicle then
                ok, result = Core.Callbacks.await('vehicles:store', garageName, id,
                    NetworkGetNetworkIdFromEntity(vehicle), props(vehicle))
            else
                ok, result = false, 'Bring the vehicle close to this garage.'
            end
            if ok then notify('Vehicle stored.', 'success') end
        else
            ok, result = false, 'Unknown action.'
        end
        if not ok then notify(result or 'Could not complete that action.') end
        waiting = false
        if opened and current == garageName then refresh() end
    end)
    cb({ ok = true })
end)

RegisterNetEvent('SeaM_Core:player:unloaded', close)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then close() end
end)

local registered = false
local function registerZones()
    if registered or GetResourceState('SeaM_Target') ~= 'started' then return end
    for name, garage in pairs(Config.Garages) do
        local garageName = name
        exports.SeaM_Target:addSphereZone({
            id = 'seam_vehicles_' .. garageName,
            coords = garage.point, radius = 1.4, label = garage.label,
            options = { { name = 'seam_garage_' .. garageName, label = 'Open garage',
                icon = 'car', distance = Config.InteractDistance,
                onSelect = function() open(garageName) end } },
        })
    end
    registered = true
end

CreateThread(function()
    while true do
        if GetResourceState('SeaM_Target') == 'started' then registerZones()
        else registered = false end
        Wait(1500)
    end
end)
