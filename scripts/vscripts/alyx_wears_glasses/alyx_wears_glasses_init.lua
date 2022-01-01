--2578210103
local player_listener = nil
-- maps to GetVRControllerType()
local CONTROLLER_TYPE_MODELS = {
    "models/wearable_glasses/wearable_glasses_rift_s.vmdl", -- 0
    "models/wearable_glasses/wearable_glasses.vmdl",        -- 1
    "models/wearable_glasses/wearable_glasses.vmdl",        -- 2
    "models/wearable_glasses/wearable_glasses.vmdl",        -- 3
    "models/wearable_glasses/wearable_glasses_rift_s.vmdl", -- 4
    "models/wearable_glasses/wearable_glasses.vmdl",        -- 5
    "models/wearable_glasses/wearable_glasses.vmdl",        -- 6
    "models/wearable_glasses/wearable_glasses.vmdl",        -- 7
    "models/wearable_glasses/wearable_glasses.vmdl",        -- 8
    "models/wearable_glasses/wearable_glasses.vmdl",        -- 9
    "models/wearable_glasses/wearable_glasses.vmdl",        -- 10
}

print("IsServer?", IsServer())
if IsServer() then
    print("Is server, listening for player spawn...")
    -- Why does giving the function handle not work but anonymous function does?
    player_listener = ListenToGameEvent("player_activate", function() OnPlayerSpawn() end, nil)
    --ListenToGameEvent("player_activate", function() print("activate", Entities:GetLocalPlayer()) end, nil)
end

function OnPlayerSpawn()
    print("Player spawned.")
    local player = Entities:GetLocalPlayer()
    -- hmd doesn't exist when any player events are fired...
    -- do hmd logic in glasses script
    --local hmd = player:GetHMDAvatar()

    -- Search range should include nearby if player lost glasses when transitioning
    -- so we don't spawn another pair on player face.
    local glasses_count = #Entities:FindAllByName("*_alyx_glasses")
    if glasses_count > 0 then
        print("Glasses do exist in map...")
    end
    print("Looking for existing glasses near player...")
    local glasses = Entities:FindByNameNearest("*_alyx_glasses", player:GetOrigin(), 400)
    if not glasses then
        print("No glasses nearby, spawning new glasses...")
        local model = CONTROLLER_TYPE_MODELS[player:GetVRControllerType()+1]
        print("CONTROLLER TYPE",player:GetVRControllerType())
        SpawnEntityFromTableAsynchronous("prop_physics",{
            --targetname = "2578210103_alyx_glasses",
            --origin = Vector(0,5,5),
            targetname = DoUniqueString("alyx_glasses"),
            vscripts = "alyx_wears_glasses/glasses",
            model = model,
            -- glow can be used to help player find glasses
            glowstate = "3",
            glowrange = "256",
            glowrangemin = "64",
            --glowcolor = "19 121 255 255",
            glowcolor = "255 18 18 255",
            rendercolor = "255 18 18 255",
            spawnflags = "16777473",
        },
        function(glass)
            print("New glasses name: "..glass:GetName())
            glass:SetContextThink("act", glass:GetPrivateScriptScope()._Activate, 0)
            glass:SetContextThink("wearglasses", glass:GetPrivateScriptScope().WearGlasses, 0.2)
        end,
        nil)
        -----@diagnostic disable-next-line: undefined-field
        --glasses:SetThink(glasses:GetPrivateScriptScope().FirstTimeSetup, "FirstTimeSetup", 0.1)
    else
        print("Glasses already exist nearby...")
        glasses:SetContextThink("act", glasses:GetPrivateScriptScope()._Activate, 0)
    end

    StopListeningToGameEvent(player_listener)
end
