local mountedGun = nil
local gunCamera = nil

local function notify(message, kind)
    exports.SeaM_Core:Notify(message, kind or 'error')
end

local function gunStatus(gun)
    local mount = gun.mount
    local label = ('%s · %d remaining · LMB fire'):format(mount.label or gun.key:gsub('_', ' '), gun.rounds)
    if mount.type == 'machinegun' then label = label .. ' · G: toggle (' .. gun.mode .. ')' end
    exports.SeaM_Core:ShowTextUI(label .. ' · Backspace exit', 'vehicles:gun', 'LMB')
end

local function mountKey(entry)
    return type(entry) == 'table' and entry.key or entry
end

local function mountedEntry(vehicle, key)
    for _, entry in ipairs(Entity(vehicle).state.seamEquipment or {}) do
        if mountKey(entry) == key then return entry end
    end
end

local function mountFor(vehicle, key)
    local hash = GetEntityModel(vehicle)
    for model, entries in pairs(Config.VehicleModels) do
        if joaat(model) == hash then
            local mount = entries[key]
            if type(mount) == 'table' and type(mount.bone) == 'string' and mount.bone ~= ''
                and (mount.type == 'cannon' or mount.type == 'machinegun' or mount.type == 'stash') then
                return mount
            end
            return nil
        end
    end
end

local function bonePosition(vehicle, key)
    local mount = mountFor(vehicle, key)
    if not mount then return nil end
    local index = GetEntityBoneIndexByName(vehicle, mount.bone)
    if not index or index < 0 then return nil end
    return GetWorldPositionOfEntityBone(vehicle, index)
end

local function stopGun()
    if mountedGun then
        TriggerServerEvent('SeaM_Vehicles:server:endAim', mountedGun.id, mountedGun.key)
    end
    mountedGun = nil
    if gunCamera then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(gunCamera, false)
        gunCamera = nil
    end
    exports.SeaM_Core:HideTextUI('vehicles:gun')
end

local function loaded(vehicle, key)
    local state = Entity(vehicle).state.seamAmmo
    return type(state) == 'table' and type(state[key]) == 'table' and tonumber(state[key].rounds) or 0
end

local function loadMount(vehicle, key, ammoType)
    local id = tonumber(Entity(vehicle).state.seamVehicleId)
    if not id or not mountedEntry(vehicle, key) or not bonePosition(vehicle, key) then return end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    CreateThread(function()
        local ok, message = exports.SeaM_Core:TriggerCallback('vehicles:loadWeapon', id, key, netId, ammoType)
        notify(message or (ok and 'Ammunition loaded.' or 'Could not load ammunition.'), ok and 'success' or 'error')
    end)
end

local function useMount(vehicle, key)
    local id = tonumber(Entity(vehicle).state.seamVehicleId)
    if not id then return end
    if not mountedEntry(vehicle, key) or not bonePosition(vehicle, key) then return end
    local mount = mountFor(vehicle, key)
    if not mount then return end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if mount.type == 'stash' then
        CreateThread(function()
            local ok, err = exports.SeaM_Core:TriggerCallback('vehicles:openHold', id, key, netId)
            if not ok then exports.SeaM_Core:Notify(err or 'Hold unavailable.', 'error') end
        end)
    else
        CreateThread(function()
            if mountedGun then stopGun() end
            local ok, rounds = exports.SeaM_Core:TriggerCallback('vehicles:beginAim', id, key, netId)
            if not ok then notify(rounds or 'Could not aim mount.') return end
            if not DoesEntityExist(vehicle) or tonumber(Entity(vehicle).state.seamVehicleId) ~= id then
                TriggerServerEvent('SeaM_Vehicles:server:endAim', id, key)
                return
            end
            mountedGun = { vehicle = vehicle, id = id, key = key, netId = netId,
                yaw = GetEntityHeading(vehicle) + (mount.heading or 0), pitch = 0.0,
                mode = 'semi', rounds = rounds, mount = mount }
            gunCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
            SetCamFov(gunCamera, mount.type == 'cannon' and 55.0 or 45.0)
            SetCamActive(gunCamera, true)
            RenderScriptCams(true, false, 0, true, true)
            gunStatus(mountedGun)
        end)
    end
end

-- SeaM_Target attaches these options to the vehicle itself. Each choice is
-- available only near its configured bone on the correct spawn model.
local registered = false
CreateThread(function()
    while true do
        if GetResourceState('SeaM_Target') ~= 'started' then
            registered = false
        elseif not registered then
            local options, seen = {}, {}
            for _, entries in pairs(Config.VehicleModels) do
                for key, definition in pairs(entries) do
                    if type(definition) == 'table' and definition.bone and definition.type then
                        local name = key
                        local kind = definition.type
                        local label = definition.label or key:gsub('_', ' ')
                        local choices = kind == 'cannon' and { 'cannon', 'aim' }
                            or kind == 'machinegun' and { 'small', 'medium', 'large', 'aim' }
                            or kind == 'stash' and { 'hold' } or {}
                        for _, choice in ipairs(choices) do
                            local optionType = choice
                            local unique = name .. ':' .. optionType
                            if not seen[unique] then
                                seen[unique] = true
                                local box = Config.Weapons.machinegun.boxes[optionType]
                                local title = optionType == 'aim' and ('Aim ' .. label)
                                    or optionType == 'hold' and ('Open ' .. label)
                                    or ('Load ' .. label .. ': ' .. (box and
                                        (box.label .. ' (' .. box.rounds .. ')') or 'cannonball'))
                                options[#options + 1] = {
                                    name = 'seam_equipment_' .. name .. '_' .. optionType,
                                    label = title, icon = optionType == 'aim' and 'gun' or 'box',
                                    distance = 25.0,
                                    canInteract = function(vehicle)
                                        if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)
                                            or IsNuiFocused() or not mountedEntry(vehicle, name) then return false end
                                        local mount = mountFor(vehicle, name)
                                        if not mount or mount.type ~= kind then return false end
                                        local point = bonePosition(vehicle, name)
                                        if not point or #(GetEntityCoords(PlayerPedId()) - point) > 3.5 then
                                            return false
                                        end
                                        return optionType == 'hold'
                                            or (optionType == 'aim' and loaded(vehicle, name) > 0)
                                            or (optionType ~= 'aim' and loaded(vehicle, name) == 0)
                                    end,
                                    onSelect = function(data)
                                        if optionType == 'aim' or optionType == 'hold' then
                                            useMount(data.entity, name)
                                        else
                                            loadMount(data.entity, name, optionType)
                                        end
                                    end,
                                }
                            end
                        end
                    end
                end
            end
            if #options > 0 then exports.SeaM_Target:addGlobalVehicle(options) end
            registered = true
        end
        Wait(1500)
    end
end)

local function muzzle(vehicle, key)
    if not mountedEntry(vehicle, key) then return nil end
    return bonePosition(vehicle, key)
end

local function direction(gun)
    local yaw, pitch = math.rad(gun.yaw), math.rad(gun.pitch)
    return vector3(-math.sin(yaw) * math.cos(pitch),
        math.cos(yaw) * math.cos(pitch), math.sin(pitch))
end

CreateThread(function()
    while true do
        local wait = 400
        if mountedGun then
            wait = 0
            local gun = mountedGun
            local ped = PlayerPedId()
            local kind = DoesEntityExist(gun.vehicle)
                and IsThisModelABoat(GetEntityModel(gun.vehicle)) and 'boat' or 'land'
            local reach = (Config.MountAccessDistance and Config.MountAccessDistance[kind]) or 9.0
            if not DoesEntityExist(gun.vehicle) or Entity(gun.vehicle).state.seamVehicleId ~= gun.id
                or not mountedEntry(gun.vehicle, gun.key) or not bonePosition(gun.vehicle, gun.key)
                or #(GetEntityCoords(ped) - GetEntityCoords(gun.vehicle)) > reach
                or IsPedDeadOrDying(ped, true) or IsNuiFocused() or IsControlJustPressed(0, 177) then
                stopGun()
            else
                for _, control in ipairs({ 1, 2, 24, 25, 30, 31, 32, 33, 34, 35, 59, 60, 71, 72 }) do
                    DisableControlAction(0, control, true)
                end
                DisablePlayerFiring(PlayerId(), true)
                local mount = gun.mount
                local limits = Config.Weapons[mount.type]
                local base = GetEntityHeading(gun.vehicle) + (mount.heading or 0)
                local delta = (gun.yaw - base + 180) % 360 - 180
                gun.yaw = base + math.max(-limits.yawLimit, math.min(limits.yawLimit,
                    delta - GetDisabledControlNormal(0, 1) * 6.0))
                gun.pitch = math.max(limits.minPitch, math.min(limits.maxPitch,
                    gun.pitch - GetDisabledControlNormal(0, 2) * 6.0))
                local origin = muzzle(gun.vehicle, gun.key)
                if origin then
                    local forward = direction(gun)
                    local camPos = origin - forward * 1.5 + vector3(0.0, 0.0, 0.35)
                    SetCamCoord(gunCamera, camPos.x, camPos.y, camPos.z)
                    SetCamRot(gunCamera, gun.pitch, 0.0, gun.yaw, 2)
                    DrawRect(0.5, 0.5, 0.002, 0.014, 245, 240, 225, 200)
                    DrawRect(0.5, 0.5, 0.009, 0.002, 245, 240, 225, 200)
                    if mount.type == 'machinegun' and IsControlJustPressed(0, 47) then
                        gun.mode = gun.mode == 'semi' and 'auto' or 'semi'
                        gunStatus(gun)
                    end
                    if not gun.lastKeepalive or GetGameTimer() - gun.lastKeepalive > 8000 then
                        gun.lastKeepalive = GetGameTimer()
                        TriggerServerEvent('SeaM_Vehicles:server:keepAim', gun.id, gun.key, gun.netId)
                    end
                    local held = mount.type == 'machinegun' and gun.mode == 'auto'
                    local pressed = held and IsDisabledControlPressed(0, 24)
                        or IsDisabledControlJustPressed(0, 24)
                    local now = GetGameTimer()
                    if pressed and not gun.pending and (not gun.last or now - gun.last >= (mount.cooldown or (mount.type == 'cannon' and 3000 or 160))) then
                        gun.last, gun.pending = now, true
                        local shot = { x = forward.x, y = forward.y, z = forward.z }
                        CreateThread(function()
                            local ok, rounds = exports.SeaM_Core:TriggerCallback('vehicles:fire',
                                gun.id, gun.key, gun.netId, shot)
                            if mountedGun == gun then
                                gun.pending = false
                                if ok then
                                    gun.rounds = rounds
                                    gunStatus(gun)
                                    if rounds <= 0 then
                                        notify('Mount empty. Load it again with third-eye.', 'inform')
                                        stopGun()
                                    end
                                elseif rounds ~= 'Mount is cooling down.' and rounds ~= 'Mount is busy.' then
                                    notify(rounds or 'Could not fire.')
                                    if rounds == 'Out of ammunition.' or rounds == 'Aim the mount first.' then stopGun() end
                                end
                            end
                        end)
                    end
                end
            end
        end
        Wait(wait)
    end
end)

local function cannonProjectile(vehicle, key, vector, owner)
    local settings = Config.Weapons.cannon
    local origin = muzzle(vehicle, key)
    if not origin then return end
    local dir = vector3(vector.x, vector.y, vector.z)
    local position = origin + dir * 1.3
    local velocity = dir * settings.speed + GetEntityVelocity(vehicle)
    local hash = joaat(settings.projectileModel)
    local object
    if IsModelInCdimage(hash) and IsModelValid(hash) then
        RequestModel(hash)
        local deadline = GetGameTimer() + 750
        while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
        if HasModelLoaded(hash) then
            object = CreateObjectNoOffset(hash, position.x, position.y, position.z, false, false, false)
            if object and object ~= 0 then SetEntityCollision(object, false, false) end
            SetModelAsNoLongerNeeded(hash)
        end
    end
    local startTime, previous = GetGameTimer(), GetGameTimer()
    while GetGameTimer() - startTime < (settings.range / settings.speed + 1) * 1000 do
        Wait(0)
        local now = GetGameTimer()
        local dt = math.min((now - previous) / 1000, 0.06)
        previous = now
        local nextPos = position + velocity * dt
        local handle = StartExpensiveSynchronousShapeTestLosProbe(
            position.x, position.y, position.z, nextPos.x, nextPos.y, nextPos.z,
            511, vehicle, 7)
        local status, hit, impact = GetShapeTestResult(handle)
        local attempts = 0
        while status == 1 and attempts < 3 do
            Wait(0)
            status, hit, impact = GetShapeTestResult(handle)
            attempts = attempts + 1
        end
        local waterHit, waterImpact = TestProbeAgainstAllWater(
            position.x, position.y, position.z, nextPos.x, nextPos.y, nextPos.z, 511)
        local struck = status == 2 and (hit == true or hit == 1)
        if waterHit and (not struck or #(waterImpact - position) < #(impact - position)) then
            struck, impact = true, waterImpact
        end
        if struck then
            if owner then
                AddExplosion(impact.x, impact.y, impact.z, settings.explosionType,
                    settings.explosionScale, true, false, 0.2)
            end
            break
        end
        position = nextPos
        velocity = velocity - vector3(0, 0, settings.gravity * dt)
        if object and DoesEntityExist(object) then
            SetEntityCoordsNoOffset(object, position.x, position.y, position.z, false, false, false)
        else
            DrawMarker(28, position.x, position.y, position.z, 0, 0, 0, 0, 0, 0,
                0.22, 0.22, 0.22, 30, 30, 30, 255, false, false, 2, false, nil, nil, false)
        end
        if #(position - origin) > settings.range then break end
    end
    if object and DoesEntityExist(object) then DeleteEntity(object) end
end

RegisterNetEvent('SeaM_Vehicles:client:shot', function(shooter, netId, key, vector)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle == 0 or not DoesEntityExist(vehicle) or not mountedEntry(vehicle, key)
        or type(vector) ~= 'table' or type(vector.x) ~= 'number' then return end
    local mount = mountFor(vehicle, key)
    if not mount then return end
    local isShooter = shooter == GetPlayerServerId(PlayerId())
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) > 230.0 then return end
    if mount.type == 'cannon' then
        CreateThread(function() cannonProjectile(vehicle, key, vector, isShooter) end)
    elseif mount.type == 'machinegun' and isShooter then
        local origin = muzzle(vehicle, key)
        if not origin then return end
        local settings = Config.Weapons.machinegun
        local hash = joaat('WEAPON_COMBATMG')
        if not HasWeaponAssetLoaded(hash) then
            RequestWeaponAsset(hash, 31, 0)
            local deadline = GetGameTimer() + 500
            while not HasWeaponAssetLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
            if not HasWeaponAssetLoaded(hash) then return end
        end
        local start = origin + vector3(vector.x, vector.y, vector.z) * 1.2
        local target = start + vector3(vector.x, vector.y, vector.z) * settings.range
        ShootSingleBulletBetweenCoords(start.x, start.y, start.z,
            target.x, target.y, target.z, settings.damage,
            true, hash, PlayerPedId(), true, false, 1000.0)
    end
end)

RegisterNetEvent('SeaM_Core:player:unloaded', stopGun)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopGun()
end)
