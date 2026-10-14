fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'SeaM_Vehicles'
author 'SeaM'
description 'Persistent garages and per-vehicle mounted equipment for SeaM_Core'
version '1.0.0'

shared_scripts { 'shared/config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/ammo_inventory.lua', 'server/main.lua' }
client_scripts { 'client/main.lua', 'client/equipment.lua' }

ui_page 'html/index.html'
files { 'html/index.html' }

-- SeaM_Target is optional at runtime (zones register whenever it starts), so it
-- is not listed. Storing a vehicle and vessel holds call SeaM_Inventory directly.
dependencies {
    'oxmysql',
    'SeaM_Core',
    'SeaM_Inventory',
}
