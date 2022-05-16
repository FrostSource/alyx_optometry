---@diagnostic disable: lowercase-global

-- This file attempt to fix hold pose when taking off glasses. Doesn't work.
-- Maybe to do with hand position against face when grabbing in which case
-- I don't know how to fix.

--[[
    Glasses is prop_physics.
    Can send CallScriptFunction input to *alyx_glasses, e.g.

    *alyx_glasses > CallScriptFunction > DisablePickup

    List of script functions to call in map:
    WearGlasses       - Snaps the glasses to player head.
    DropGlasses       - Drops the glasses with a random forward velocity.
    EnableDrop        - Glasses are allowed to fall off face.
    DisableDrop       - Glasses are not allowed to fall off face.
    EnableBlur        - Enables blur postprocess. Will disable if player drops glasses.
    DisableBlur       - Disables blur postprocess. Will enable if player puts glasses off.
    EnableCollisions  - Enables glasses collisions with player entities.
    DisableCollisions - Disables glasses collisions with player entities.

    Also useful to send input DisablePickup/EnablePickup for certain areas like cutscenes.

]]

--local DROP_FROM_FALLING_CHANCE = 0.4
local DROP_FROM_DAMAGE_CHANCE = 0.25
local DROP_FROM_LOOK_DOWN_CHANCE = 0.05
--local DROP_FROM_PROPER_JUMP_EXTRA_CHANCE = 0.3

-- 1 = any movement, 0 = 90 degrees
-- current method of calculating means it needs
-- to be a high number
local HEAD_TWITCH_ANGLE = 0.9
-- disabled until a better method because quick turn
-- will consistently trigger this
local DROP_FROM_HEAD_TWITCH_CHANCE = 0--0.3

local DROP_FROM_BARNACLE_GRAB_CHANCE = 0.6

-- minimum damage player just recieve to drop glasses
-- for reference: grunt on story does 2, on hard 11
local MIN_DAMAGE_TO_DROP = 1

-- multiplier will be calculated based on jump height betwen these two values
local MIN_JUMP_HEIGHT_TO_DROP = 32
local MAX_JUMP_HEIGHT_TO_DROP = 176 -- roughly death height
-- will then be multiplied by this for final chance, this is essentially the max chance
local DROP_FROM_JUMP_DOWN_CHANCE = 0.5
-- multiplier will be calculated based on jump distance betwen these two values
local MIN_JUMP_FORWARD_TO_DROP = 100 -- just over the running sound dist
local MAX_JUMP_FORWARD_TO_DROP = 180 -- usually max jump dist
-- will then be multiplied by this for final chance, this is essentially the max chance
local DROP_FROM_JUMP_FORWARD_CHANCE = 0.02

local PROPER_JUMP_MULTIPLIER = 1.5
-- if player did an actual jump then we make sure there's never a 0% chance
local PROPER_JUMP_MIN_CHANCE = 0.1

local SKILL = Convars:GetInt("skill")

-- seconds before particle and sound hint start after dropping glasses
local HINT_POSITION_DELAY = 5 + (10 * SKILL)

local UP_BIAS = 0.8

local THINK_INTERVAL = 0.05

local DROP_SOUNDS = {
    "ScriptedSeq.Hideout_Vort_Sustenance_Throw",
    "ScriptedSeq.Russel_Move_Throw"
}
local ATTACH_SOUNDS = {
    "Inventory.GrabItem",
}
local COLLISION_ENTITIES = {
    "hmd_avatar",
    "_plr_hl_prop_vr_hand_0",
    "_plr_hl_prop_vr_hand_1"
}

local PP_TABLE = {
    class = "post_processing_volume",
    targetname = "2578210103_pp_glasses_blur",
    origin = Vector(-112,64,40),
    scale = 16,
    model = "maps/glasses_meshes/entities/pp_blur_mesh_2.vmdl",
    postprocessing = "materials/postprocessing/no_glasses_"..SKILL..".vpost",
    fadetime = 0.1,
    minexposure = 1,
    maxexposure = 1,
}

is_held_by_barnacle = is_held_by_barnacle or false
teleport_started_flag = teleport_started_flag or false
player_did_proper_jump = player_did_proper_jump or false
is_being_held = is_being_held or false
glasses_were_dropped_unintentionally = glasses_were_dropped_unintentionally or false
player_putting_glasses_on = player_putting_glasses_on or false
player_speaker = player_speaker or nil
game_event_listeners = game_event_listeners or {}
particle_hint = particle_hint or nil
-- used to get around event firing on grab AND release
player_was_grabbed_by_barnacle = player_was_grabbed_by_barnacle or false

--local analytic_max_jump_height = 0
--local analytic_max_jump_distance = 0

player = player or
{
    ---@type CHL2_Player
    handle = nil,
    ---@type CPropHMDAvatar
    hmd = nil,
    ---@type Vector
    pos_cached = Vector(0,0,0),
    ---@type boolean
    novr = false,
    ---@type boolean
    looking_down = false,
    ---@type number
    hp_cache = 0,
    ---@type Vector
    head_forward_cache = Vector(0,1,0)
}

local function playerHeadForward()
    if player.hmd then
        return player.hmd:GetForwardVector()
    else
        return AnglesToVector(player.handle:EyeAngles())
    end
end

local function randomChance(chance)
    return RandomFloat(0, 1) <= chance
end

local function randomHeadForward(max_angle)
    max_angle = max_angle or 40
    local yaw = RandomInt(-max_angle, max_angle)
    local pitch = RandomInt(-max_angle, max_angle)
    local dir = RotatePosition(Vector(0,0,0), QAngle(pitch, 0, yaw), playerHeadForward())
    --local bias = (1 - RemapVal(dir.z, -1, 1, 0, 1)) --* UP_BIAS
    --print("BIAS", bias)
    --dir = RotatePosition(Vector(0,0,0), QAngle(-180*bias,0,0), dir)
    return dir
end

--local function randomVelocity()
--
--end

local function printChance(chance)
    print("Chance to drop: "..  math.floor((chance * 100) + 0.5) .."%")
end

local function playerSpeak(concept, delay)
    delay = delay or 0
    if player_speaker then
        DoEntFireByInstanceHandle(player_speaker, "SpeakConcept", "speech:"..concept, delay, thisEntity, thisEntity)
    end
end

---Play random sound from table on player.
---@param tbl table # Table containing sound names.
local function randomSound(tbl)
    EmitSoundOn(tbl[RandomInt(1, #tbl)], player.hmd)
end

local function isWearingGlasses()
    return thisEntity:GetMoveParent() == player.hmd
end

local function isAllowedToDropGlasses()
    local context = thisEntity:GetContext("is_allowed_to_drop_glasses")
    return context == 1 or context == nil
end

function _Activate(activateType)
    print("Glasses _activate")
    -- Listeners for glasses interaction
    game_event_listeners[1] = ListenToGameEvent("item_pickup", OnItemPickup, thisEntity)
    game_event_listeners[2] = ListenToGameEvent("item_released", OnItemReleased, thisEntity)
    -- Listeners for dropping events
    game_event_listeners[3] = ListenToGameEvent("player_teleport_start", PlayerTeleportStart, thisEntity)
    game_event_listeners[4] = ListenToGameEvent("player_teleport_finish", PlayerTeleportFinish, thisEntity)
    game_event_listeners[5] = ListenToGameEvent("player_continuous_jump_finish", PlayerContinousJumpFinish, thisEntity)
    game_event_listeners[6] = ListenToGameEvent("player_hurt", PlayerHurt, thisEntity)
    game_event_listeners[7] = ListenToGameEvent("player_grabbed_by_barnacle", PlayerGrabbedByBarnacle, thisEntity)
    game_event_listeners[8] = ListenToGameEvent("player_released_by_barnacle", PlayerGrabbedByBarnacle, thisEntity)
    --thisEntity:SetThink(FirstTimeSetup, "SetupPlayer", 0.1)
    thisEntity:SetThink(GlassesThink, "PlayerThink", 1)

    thisEntity:SetThink(function()
        --local a_pp = Entities:FindByClassname(nil, "post_processing_volume")
        -- Uses existing postprocess model to work!
        --if not a_pp then
        --    error("Map must have at least one post_processing_volume!")
        --end
        FirstTimeSetup()
        local pp = Entities:FindByName(nil, "2578210103_pp_glasses_blur")
        if not pp then
            pp = SpawnEntityFromTableSynchronous(PP_TABLE.class,PP_TABLE)
        end

        if pp:GetMoveParent() ~= player.handle then
            pp:SetParent(player.handle, "")
            pp:SetLocalOrigin(Vector(0,0,0))
            pp:SetLocalAngles(0,0,0)
        end
        print("Created PP blur", pp, pp:GetModelName())
        if isWearingGlasses() then
            --DisableBlur()
            WearGlasses()
        end
    end, "playerdelay", 0.12)
end

function Precache(context)
    print("PRECACHE")
    PrecacheModel("maps/glasses_meshes/entities/pp_blur_mesh_2.vmdl", context)
    PrecacheModel("models/wearable_glasses/wearable_glasses.vmdl", context)
    PrecacheModel("models/wearable_glasses/wearable_glasses_rift_s.vmdl", context)
    PrecacheEntityFromTable(PP_TABLE.class,PP_TABLE,context)
end

function UpdateOnRemove()
    print("UPDATE ON REMOVE")
    for _, listener in ipairs(game_event_listeners) do
        StopListeningToGameEvent(listener)
    end
end

function FirstTimeSetup()
    print("First time glasses setup", thisEntity:GetName())
    UpdatePlayer()

    player_speaker = Entities:FindByClassname(nil, "point_player_speak")
    if not player_speaker then
        player_speaker = SpawnEntityFromTableSynchronous("point_player_speak",{})
    end

    player.hmd:GetVRHand(0):SetEntityName("_plr_hl_prop_vr_hand_0")
    player.hmd:GetVRHand(1):SetEntityName("_plr_hl_prop_vr_hand_1")

    local plr_name = thisEntity:GetName()
    for _, name in ipairs(COLLISION_ENTITIES) do
        local target_name = plr_name.."_logic_collision_"..name
        if not Entities:FindByName(nil, target_name) then
            SpawnEntityFromTableSynchronous("logic_collision_pair",{
                targetname = target_name,
                attach1 = name,
                attach2 = plr_name,
                startdisabled = 0
            })
        end
    end

end

function EnableCollisions()
    for _, name in ipairs(COLLISION_ENTITIES) do
        local target_name = thisEntity:GetName().."_logic_collision_"..name
        DoEntFire(target_name, "EnableCollisions", "", 0, thisEntity, thisEntity)
    end
end
function DisableCollisions()
    for _, name in ipairs(COLLISION_ENTITIES) do
        local target_name = thisEntity:GetName().."_logic_collision_"..name
        DoEntFire(target_name, "DisableCollisions", "", 0, thisEntity, thisEntity)
    end
end

function EnableBlur()
    print("Enable blur", Entities:FindByName(nil, "2578210103_pp_glasses_blur"))
    --local pp = Entities:FindByName(nil, "2578210103_pp_glasses_blur")
    --if pp then
    --    --pp:SetParent(player.handle, "")
    --    pp:SetLocalOrigin(Vector(0,0,0))
    --end
    DoEntFire("2578210103_pp_glasses_blur", "Enable", "", 0, nil, nil)
end
function DisableBlur()
    print("Disable blur", Entities:FindByName(nil, "2578210103_pp_glasses_blur"))
    --local pp = Entities:FindByName(nil, "2578210103_pp_glasses_blur")
    --print(pp:GetOrigin())
    --if pp then
    --    pp:SetLocalOrigin(Vector(9999,9999,9999))
    --    --pp:SetParent(nil, "")
    --end
    DoEntFire("2578210103_pp_glasses_blur", "Disable", "", 0, nil, nil)
end

function EnableDrop()
    DoEntFireByInstanceHandle(thisEntity, "EnablePickup", "", 0, thisEntity, thisEntity)
    thisEntity:SetContextNum("is_allowed_to_drop_glasses", 1, 0)
    print("Disabled drop")
end
function DisableDrop()
    DoEntFireByInstanceHandle(thisEntity, "DisablePickup", "", 0, thisEntity, thisEntity)
    thisEntity:SetContextNum("is_allowed_to_drop_glasses", 0, 0)
    print("Enabled drop")
end

function UpdatePlayer()
    print("UPdated player")
    player.handle = Entities:GetLocalPlayer()
    player.hmd = player.handle:GetHMDAvatar()
    if player.hmd == nil then
        player.novr = true
    end
    player.pos_cached = player.handle:GetOrigin()
    player.hp_cache = player.handle:GetHealth()
    player.head_forward_cache = player.hmd:GetForwardVector()
end

---Attemps to wear the glasses, attaching to face if close enough.
function AttemptWear()
end

---Instantly wears the glasses.
function WearGlasses()
    -- stops the chance of glasses instantly falling off when put on
    print("Putting glasses on.")

    if player_putting_glasses_on then
        player_putting_glasses_on = false
        randomSound(ATTACH_SOUNDS)
        if glasses_were_dropped_unintentionally then
            glasses_were_dropped_unintentionally = false
            playerSpeak("alyx_combat_relief", 0.4)
        end
    end
    player.looking_down = true
    -- glasses are invisible while on player
    -- thisEntity:SetParent(player.hmd, "")
    -- thisEntity:SetLocalOrigin(Vector(0,0,0))
    -- thisEntity:SetLocalAngles(0,0,0)
    -- thisEntity:SetAbsScale(0.01)
    -- thisEntity:SetRenderAlpha(0)
    -- thisEntity:SetOrigin(Vector(99999,99999,99999))
    thisEntity:SetOrigin(Vector(0,0,0))
    thisEntity:StopThink("GlassesOnGroundThink")
    thisEntity:SetThink(GlassesThink, "PlayerThink", THINK_INTERVAL)
    -- DisableCollisions()
    -- thisEntity:DisableMotion()
    DoEntFireByInstanceHandle(thisEntity, "DisablePhyscannonPickup", "", 0, nil, nil)
    DisableBlur()
    debugoverlay:Sphere(thisEntity:GetOrigin(),5,255,0,0,255,true,20)
end

function DropTest()
    DropGlasses(playerHeadForward(), 100, 100)
end

---Drops the glasses in a direction.
---@param direction? Vector
---@param velocity? Vector
---@param angular_velocity? Vector
function DropGlasses(direction, velocity, angular_velocity)
    -- if not thisEntity:GetMoveParent() then return end
    if not isAllowedToDropGlasses() then
        print("Glasses tried to drop while dropping is disabled.")
        return
    end
    if glasses_were_dropped_unintentionally then
        randomSound(DROP_SOUNDS)
        -- possible responses
        -- speech:alyx_startled
        -- speech:alyx_exhale
        -- speech:alyx_gasp
        playerSpeak("alyx_startled", 0)
        print("GlASSES DROPPED!")
        thisEntity:SetThink(GlassesOnGroundThink, "GlassesOnGroundThink", HINT_POSITION_DELAY)
    end
    direction = direction or randomHeadForward()
    velocity = velocity or RandomInt(100, 200)
    angular_velocity = angular_velocity or RandomInt(90, 180)
    thisEntity:SetParent(nil, "")
    thisEntity:SetOrigin(player.hmd:GetOrigin())
    local a = player.hmd:GetAngles()
    thisEntity:SetAngles(a.x,a.y,a.z)
    thisEntity:SetRenderAlpha(255)
    thisEntity:SetAbsScale(1)
    -- thisEntity:EnableMotion()
    thisEntity:ApplyAbsVelocityImpulse(direction * velocity)
    thisEntity:ApplyLocalAngularVelocityImpulse(Vector(angular_velocity,angular_velocity,angular_velocity))
    thisEntity:StopThink("PlayerThink")
    --debugoverlay:VertArrow(player.hmd:GetOrigin(), player.hmd:GetOrigin() + direction * 32, 2, 255, 0, 0, 255, false, 10)
    DoEntFireByInstanceHandle(thisEntity, "EnablePhyscannonPickup", "", 0, nil, nil)
    EnableBlur()
    debugoverlay:Sphere(thisEntity:GetOrigin(),5,255,0,0,255,true,20)
end

function GlassesThink()
    local head_forward = playerHeadForward()
    -- Determine if player has looked down.
    local player_facing = head_forward.z
    if not player.looking_down and player_facing < -0.8 then
        player.looking_down = true
        -- print("Player looked down.")
        printChance(DROP_FROM_LOOK_DOWN_CHANCE)
        if randomChance(DROP_FROM_LOOK_DOWN_CHANCE) then
            print("Dropped glasses from looking down.")
            glasses_were_dropped_unintentionally = true
            DropGlasses(head_forward, 50, 0)
            --return 1
        end
    elseif player_facing > -0.3 then
        player.looking_down = false
    end

    -- Determine if player moved head quickly
    --print(head_forward:Dot(player.head_forward_cache))
    if head_forward:Dot(player.head_forward_cache) < HEAD_TWITCH_ANGLE then
        --print("HEAD TWITCHED", head_forward:Dot(player.head_forward_cache))
        if randomChance(DROP_FROM_HEAD_TWITCH_CHANCE) then
            print("Dropped glasses from shaking head.")
            glasses_were_dropped_unintentionally = true
            DropGlasses(head_forward, RandomInt(125, 200), RandomInt(20, 200))
        end
    end
    player.head_forward_cache = head_forward

    -- Pickup off head test
    for i = 0, 1 do
        local hand = player.hmd:GetVRHand(i)
        if player.handle:IsDigitalActionOnForHand(hand:GetLiteralHandType(), 3)
        and VectorDistance(hand:GetOrigin(),player.hmd:GetOrigin()) < 32 then
            TakeOffGlasses(i)
            return
        end
    end

    -- Think interval
    return THINK_INTERVAL
end

function GlassesOnGroundThink()
    CatchFallThroughWorld()

    thisEntity:EmitSoundParams("AlyxGlasses.NotifyPosition", 0, 4, 0)
    if particle_hint == nil then
        particle_hint = ParticleManager:CreateParticle("particles/instanced/vort_menacea/shot6/grabbity_gloves_glow_c_instance1.vpcf", 1, thisEntity)
    end
    return 3
end

function CatchFallThroughWorld()
    if abs(thisEntity:GetOrigin().z - player.handle:GetOrigin().z) > 4096 then
        Warning("Glasses fell through the world or became too far from player z position!")
        WearGlasses()
    end
end

--#region Interaction event functions

---Convert vr_tip_attachment from a game event [1,2] into a hand id [0,1] taking into account left handedness.
---@param vr_tip_attachment "1"|"2"
---@return "0"|"1"
local function GetHandIdFromTip(vr_tip_attachment)
    local handId = vr_tip_attachment - 1
    if not Convars:GetBool("hlvr_left_hand_primary") then
        handId = 1 - handId
    end
    return handId
end

function TakeOffGlasses(hand)
    print("Player took glasses off face.")
    DropGlasses(Vector(0,0,0),0,0)
    DoEntFireByInstanceHandle(thisEntity,"Use",tostring(hand),2,nil,nil)
end

function OnItemPickup(_, data)
    if not isAllowedToDropGlasses() then return end
    if data.item_name == thisEntity:GetName() then
        if particle_hint ~= nil then
            thisEntity:StopThink("GlassesOnGroundThink")
            ParticleManager:DestroyParticle(particle_hint, false)
            particle_hint = nil
        end
        is_being_held = true
        -- if thisEntity:GetMoveParent() == player.hmd then
        --     print("Player took glasses off face.")
        --     DropGlasses(Vector(0,0,0),0,0)
        -- end
    end
end

function OnItemReleased(_, data)
    if not isAllowedToDropGlasses() then return end
    if data.item_name == thisEntity:GetName() then
        is_being_held = false
        print("Player trying to put glasses on", thisEntity:GetForwardVector():Dot(playerHeadForward()), VectorDistance(thisEntity:GetOrigin(), player.hmd:GetOrigin()))
        local dist = VectorDistance(thisEntity:GetOrigin(), player.hmd:GetOrigin())
        if dist < 4
            or (dist < 10 and thisEntity:GetForwardVector():Dot(playerHeadForward()) > 0.4)
        then
            player_putting_glasses_on = true
            WearGlasses()
        end
    end
end

--#endregion

--#region Dropping event functions

---Player teleport start game event.
---This fires when player releases thumbstick and starts teleport.
---Position is where teleport marker is, not player.
---@param _ unknown
---@param data table
function PlayerTeleportStart(_, data)
    --data.userid
    --data.positionX
    --data.positionY
    --data.positionZ
    --data.map_name
    -- print("GameEvent: PlayerTeleportStart")
    teleport_started_flag = true
    local player_pos = player.handle:GetOrigin()
    player.pos_cached = Vector(player_pos.x, player_pos.y, player_pos.z)
end
---Player teleport finish event.
---This fires when player finishes teleport or moves with continuous.
---@param _ unknown
---@param data table
function PlayerTeleportFinish(_, data)
    --data.userid
    --data.positionX
    --data.positionY
    --data.positionZ
    --data.map_name
    -- since this fires for continuous we only want to calculate
    -- if its preceeded by a tp start
    if not teleport_started_flag or not isWearingGlasses() then return end
    teleport_started_flag = false
    -- print("GameEvent: PlayerTeleportFinish")
    local player_pos = player.handle:GetOrigin()
    -- Calculate distance
    local jump_distance = VectorDistance(
        Vector(player.pos_cached.x, player.pos_cached.y, 0),
        Vector(player_pos.x, player_pos.y, 0)
    )
    local jump_forward_chance = RemapValClamped(jump_distance, MIN_JUMP_FORWARD_TO_DROP, MAX_JUMP_FORWARD_TO_DROP, 0, 1)
    jump_forward_chance = jump_forward_chance * DROP_FROM_JUMP_FORWARD_CHANCE
    -- Calculate height
    -- abs in case player jumps up
    local jump_height = abs(player_pos.z - player.pos_cached.z)
    local jump_down_chance = RemapValClamped(jump_height, MIN_JUMP_HEIGHT_TO_DROP, MAX_JUMP_HEIGHT_TO_DROP, 0, 1)
    jump_down_chance = jump_down_chance * DROP_FROM_JUMP_DOWN_CHANCE

    -- Should combine the chances or choose the max?
    local final_chance = max(jump_forward_chance, jump_down_chance)
    print(jump_forward_chance, jump_down_chance)
    if player_did_proper_jump then
        final_chance = max(final_chance * PROPER_JUMP_MULTIPLIER, PROPER_JUMP_MIN_CHANCE)
        player_did_proper_jump = false
        --print("was proper jump")
    end

    --analytic_max_jump_distance = max(analytic_max_jump_distance, jump_distance)
    --analytic_max_jump_height = max(analytic_max_jump_height, jump_height)
    --print("distance: "..jump_distance, "max: "..analytic_max_jump_distance)
    --print("height: "..jump_height, "max: "..analytic_max_jump_height)
    printChance(final_chance)
    if randomChance(final_chance) then
        print("Dropped glasses from movement.")
        glasses_were_dropped_unintentionally = true
        DropGlasses(randomHeadForward(30), RandomInt(120, 200), RandomInt(0, 80))
    end
end
---Player continuous jump event.
---This fires when player jumps across a gap or down a large height.
---This isn't consistently registered so should be used as an extra chance.
---@param _ unknown
---@param data table
function PlayerContinousJumpFinish(_, data)
    --data.userid
    -- print("GameEvent: PlayerContinousJumpFinish")
    player_did_proper_jump = true
end

---Player hurt game event.
---@param _ unknown
---@param data table
function PlayerHurt(_, data)
    --data.userid
    --data.attacker
    --data.health # remaining hp
    -- Don't have a chance to drop glasses if they didn't fall off
    -- the first time player was grabbed by barnacle.
    if not isWearingGlasses() or is_held_by_barnacle then return end
    local hp_lost = player.hp_cache - data.health
    -- print("GameEvent: PlayerHurt", data.health, hp_lost)
    if hp_lost >= MIN_DAMAGE_TO_DROP then
        local mult = 1 + (hp_lost / player.handle:GetMaxHealth())
        local final_chance = DROP_FROM_DAMAGE_CHANCE * mult
        if hp_lost >= Convars:GetInt("sk_headcrab_melee_dmg") then
            -- print("Headcrab attached to face!")
            final_chance = 1
        end
        printChance(final_chance)
        if randomChance(final_chance) then
            print("Dropped glasses from damage", hp_lost)
            glasses_were_dropped_unintentionally = true
            DropGlasses(randomHeadForward(), RandomInt(100,200), RandomInt(10,200))
        end
    end
    player.hp_cache = data.health
    -- debug infinite health
    player.handle:SetHealth(player.handle:GetMaxHealth())
    player.hp_cache = player.handle:GetHealth()
end

-- did 7, max 100, chance 52%, default chance 25%

---Player grabbed by barnacle event.
---@param _ unknown
---@param data table
function PlayerGrabbedByBarnacle(_, data)
    --data.userid
    if player_was_grabbed_by_barnacle then
        --print("","!!!!!!!!!!!PLAYER WAS RELEASED!!!!!!!!")
        player_was_grabbed_by_barnacle = false
        return
    end
    player_was_grabbed_by_barnacle = true
    if not isWearingGlasses() then return end
    -- print("GameEvent: PlayerGrabbedByBarnacle")
    --print("","!!!!!!!!!!!PLAYER WAS GRABBED!!!!!!!!")
    is_held_by_barnacle = true
    printChance(DROP_FROM_BARNACLE_GRAB_CHANCE)
    if randomChance(DROP_FROM_BARNACLE_GRAB_CHANCE) then
        print("Dropped glasses from barnacle.")
        glasses_were_dropped_unintentionally = true
        --local dir = randomHeadForward(45)
        --dir.z = RandomFloat(0.8, 1)
        local dir = Vector(RandomFloat(-1,1),RandomFloat(-1,1),RandomFloat(0.8, 1))
        DropGlasses(dir, RandomInt(100,200), RandomInt(10,200))
    end
end

--#endregion
