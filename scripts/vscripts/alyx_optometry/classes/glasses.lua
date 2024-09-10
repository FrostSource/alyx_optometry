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

if thisEntity then
    -- Inherit this script if attached to entity
    -- Will also load the script at the same time if needed
    inherit(GetScriptFile())
    return
end

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

EasyConvars:RegisterConvar("glasses_wear_distance", 4, "Distance at which glasses will always be worn when released")
EasyConvars:SetPersistent("glasses_wear_distance", true)
EasyConvars:RegisterConvar("glasses_accurate_wear_distance", 10, "Distance at which glasses will be worn if accurately aligned with face")
EasyConvars:SetPersistent("glasses_accurate_wear_distance", true)

EasyConvars:RegisterCommand("glasses_show_hint", function ()
    if not AlyxGlasses then
        warn("Glasses prop could not be found!")
        return
    end

    AlyxGlasses:ShowHint()
end)

EasyConvars:RegisterConvar("glasses_drop_from_look_down_chance", 0.05)
EasyConvars:SetPersistent("glasses_drop_from_look_down_chance", true)

EasyConvars:RegisterConvar("glasses_drop_from_barnacle_grab_chance", 0.6)
EasyConvars:SetPersistent("glasses_drop_from_barnacle_grab_chance", true)

EasyConvars:RegisterConvar("glasses_drop_from_head_twitch_chance", 0.0)
EasyConvars:SetPersistent("glasses_drop_from_head_twitch_chance", true)

EasyConvars:RegisterConvar("glasses_drop_from_jump_forward_chance", 0.02)
EasyConvars:SetPersistent("glasses_drop_from_jump_forward_chance", true)

EasyConvars:RegisterConvar("glasses_drop_from_jump_down_chance", 0.5)
EasyConvars:SetPersistent("glasses_drop_from_jump_down_chance", true)

EasyConvars:RegisterConvar("glasses_drop_from_damage_chance", 0.25)
EasyConvars:SetPersistent("glasses_drop_from_damage_chance", true)

EasyConvars:RegisterConvar("glasses_use_hint_sound", 1)
EasyConvars:SetPersistent("glasses_use_hint_sound", true)

EasyConvars:RegisterConvar("glasses_use_hint_particle", 1)
EasyConvars:SetPersistent("glasses_use_hint_particle", true)

EasyConvars:RegisterConvar("glasses_hint_delay", function ()
    -- Initializer
    SKILL = Convars:GetInt("skill")
    print(5 + (10 * SKILL))
    return 5 + (10 * SKILL)
end)
EasyConvars:SetPersistent("glasses_hint_delay", true)

EasyConvars:RegisterConvar("glasses_blur_amount", function ()
    -- Initializer
    SKILL = Convars:GetInt("skill")
    return SKILL
end, "", 0, function (newVal, oldVal)
    local val = tonumber(newVal)
    if val ~= 0 and val ~= 1 and val ~= 2 and val ~= 3 then
        Msg("Blur amount must be 0, 1, 2 or 3!\n")
        EasyConvars:SetRaw("glasses_blur_amount", oldVal)
        return
    end

    if not AlyxGlasses then
        warn("Glasses prop could not be found!")
        return
    end

    AlyxGlasses:SetBlurAmount(val)
end)
EasyConvars:SetPersistent("glasses_blur_amount", true)

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

local POSTPROCESS_BLUR_NAME = "alyx_optometry_pp_glasses_blur"

local PP_TABLE = {
    class = "post_processing_volume",
    targetname = POSTPROCESS_BLUR_NAME,
    origin = Vector(-112,64,40),
    scale = 16,
    --model = "maps/glasses_meshes/entities/pp_blur_mesh_2.vmdl",
    model = "models/brushes/postprocess_blur_hull.vmdl",
    postprocessing = "materials/postprocessing/no_glasses_"..SKILL..".vpost",
    fadetime = 0.1,
    minexposure = 1,
    maxexposure = 1,
}

local playerIsHeldByBarnacle = false
local teleportStartedFlag = false
local playerDidProperJump = false
local isBeingHeld = false
-- local glassesWereDroppedUnintentionally = false
---Player is putting glasses on manually by dropping onto head
local playerPuttingGlassesOn = false
---ID of particle
local particleHint = -1
-- used to get around event firing on grab AND release
local playerWasGrabbedByBarnacle = false
local playerPreviousHealth = 0
---@type Vector
local playerPreviousPos
local playerIsLookingDown = false
---@type Vector
local playerPreviousHeadForward
---@type EntityHandle
local playerSpeaker
---The server time which the glasses were last dropped
local glassesDropTime = 0

local function playerHeadForward()
    return Player:EyeAngles():Forward()
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

local function printChance(chance)
    print("Chance to drop: "..  math.floor((chance * 100) + 0.5) .."%")
end

local function playerSpeak(concept, delay)
    if playerSpeaker then
        playerSpeaker:EntFire("SpeakConcept", "speech:"..concept, delay or 0)
    end
end

---Play random sound from table on player.
---@param tbl table # Table containing sound names.
local function randomSound(tbl)
    EmitSoundOn(tbl[RandomInt(1, #tbl)], Player)
end

---@class GlassesProp : EntityClass
local base = entity("GlassesProp")

base.glassesWereDroppedUnintentionally = false

function base:Precache(context)
    -- print("PRECACHE")
    -- PrecacheModel("maps/glasses_meshes/entities/pp_blur_mesh_2.vmdl", context)
    PrecacheModel("models/wearable_glasses/wearable_glasses.vmdl", context)
    PrecacheModel("models/wearable_glasses/wearable_glasses_rift_s.vmdl", context)
    -- PrecacheModel("models/brushes/postprocess_blur_hull.vmdl", context)

    for i = 0, 3 do
        PP_TABLE.postprocessing = "materials/postprocessing/no_glasses_"..i..".vpost"
        PrecacheEntityFromTable(PP_TABLE.class,PP_TABLE,context)
    end
end

---Called automatically on spawn
---@param spawnkeys CScriptKeyValues
function base:OnSpawn(spawnkeys)
end

---Called automatically on player activate.
---@param readyType OnReadyType
function base:OnReady(readyType)
    --local a_pp = Entities:FindByClassname(nil, "post_processing_volume")
    -- Uses existing postprocess model to work!
    --if not a_pp then
    --    error("Map must have at least one post_processing_volume!")
    --end

    -- FirstTimeSetup()
    print("Glasses OnReady")
    ---@TODO Find a better method for waiting for player while integrating with OnReady
    self:Delay(function ()


        playerPreviousPos = Player:GetOrigin()
        playerPreviousHeadForward = playerHeadForward()
        playerPreviousHealth = Player:GetHealth()

        self:SetBlurAmount()

        -- local pp = Entities:FindByName(nil, "2578210103_pp_glasses_blur")
        -- if not pp then
        --     pp = SpawnEntityFromTableSynchronous(PP_TABLE.class,PP_TABLE)
        -- end

        -- if pp:GetMoveParent() ~= Player then
        --     pp:SetParent(Player, "")
        --     pp:SetLocalOrigin(Vector(0,0,0))
        --     pp:SetLocalAngles(0,0,0)
        -- end
        -- devprints("Created PP blur", pp, pp:GetModelName())

        if self:IsWearingGlasses() then
            --DisableBlur()
            self:WearGlasses()
        end

        playerSpeaker = Entities:FindByClassname(nil, "point_player_speak")
        if not playerSpeaker then
            playerSpeaker = SpawnEntityFromTableSynchronous("point_player_speak",{})
        end
    end)
end

---Set the amount of blur post processing shown when glasses are taken off.
---This kills and spawns a new postprocessing entity.
---@param amount 0|1|2|3|nil # If nil the current value will be reused.
function base:SetBlurAmount(amount)
    if amount == nil then
        amount = EasyConvars:GetInt("glasses_blur_amount")
    end

    if amount ~= 0 and amount ~= 1 and amount ~= 2 and amount ~= 3 then
        warn("Blur amount must be 0, 1, 2 or 3!")
        return
    end

    local pp = Entities:FindByName(nil, POSTPROCESS_BLUR_NAME)
    if pp then
        pp:Kill()
    end

    pp = SpawnEntityFromTableSynchronous(PP_TABLE.class,
        vlua.tableadd(PP_TABLE, {postprocessing = "materials/postprocessing/no_glasses_"..amount..".vpost",})
    )

    pp:SetParent(Player, "")
    pp:SetLocalOrigin(Vector(0,0,0))
    pp:SetLocalAngles(0,0,0)
end

function base:IsWearingGlasses()
    -- return self:GetMoveParent() == Player.HMDAvatar
    return self:GetOwner() == Player
end

function base:IsAllowedToDropGlasses()
    local context = self:GetContext("is_allowed_to_drop_glasses")
    return context == 1 or context == nil
end

function base:EnableBlur()
    devprints("Enable blur", Entities:FindByName(nil, POSTPROCESS_BLUR_NAME))
    DoEntFire(POSTPROCESS_BLUR_NAME, "Enable", "", 0, nil, nil)
end
function base:DisableBlur()
    devprints("Disable blur", Entities:FindByName(nil, POSTPROCESS_BLUR_NAME))
    DoEntFire(POSTPROCESS_BLUR_NAME, "Disable", "", 0, nil, nil)
end

function base:EnableDrop()
    self:EntFire("EnablePickup")
    self.isAllowedToDropGlasses = true
    devprints("Disabled drop")
end
function base:DisableDrop()
    self:EntFire("DisablePickup")
    self.isAllowedToDropGlasses = false
    devprints("Enabled drop")
end

---Instantly wears the glasses.
---@param silent? boolean # if true, no attach or relief sound will play
function base:WearGlasses(silent)
    -- stops the chance of glasses instantly falling off when put on
    devprint("Putting glasses on")

    -- if playerPuttingGlassesOn then
    if not silent then
        -- playerPuttingGlassesOn = false
        randomSound(ATTACH_SOUNDS)
        if self.glassesWereDroppedUnintentionally then
            self.glassesWereDroppedUnintentionally = false
            playerSpeak("alyx_combat_relief", 0.4)
        end
    end

    -- Make glasses think player was looking down so they won't fall off when putting on while looking down
    playerIsLookingDown = true

    self:SetGlassesOnHead(true)
    -- self:StopThink("GlassesOnGroundThink")
    -- self:SetThink(GlassesThink, "PlayerThink", THINK_INTERVAL)
    self:ResumeThink()
end

---Drops the glasses in a direction, or random forward if called without values.
---@param direction? Vector
---@param velocity? number
---@param angularVelocity? number
---@param silent? boolean # if true, no drop sounds will play
function base:DropGlasses(direction, velocity, angularVelocity, silent)
    -- if not self:GetMoveParent() then return end
    if not self:IsWearingGlasses() then return end
    if not self:IsAllowedToDropGlasses() then
        warn("Glasses tried to drop while dropping is disabled.")
        return
    end

    if self.glassesWereDroppedUnintentionally and not silent then
        randomSound(DROP_SOUNDS)
        -- possible responses
        -- speech:alyx_startled
        -- speech:alyx_exhale
        -- speech:alyx_gasp
        playerSpeak("alyx_startled", 0)
        devprint("GlASSES DROPPED!")
        self:ResumeThink()
        -- self:SetThink(GlassesOnGroundThink, "GlassesOnGroundThink", HINT_POSITION_DELAY)
    end

    self:SetGlassesOnHead(false)

    direction = direction or randomHeadForward()
    velocity = velocity or RandomInt(100, 200)
    angularVelocity = angularVelocity or RandomInt(90, 180)

    self:ApplyAbsVelocityImpulse(direction * velocity)
    self:ApplyLocalAngularVelocityImpulse(Vector(angularVelocity,angularVelocity,angularVelocity))
    -- self:StopThink("PlayerThink")
    --debugoverlay:VertArrow(player.hmd:GetOrigin(), player.hmd:GetOrigin() + direction * 32, 2, 255, 0, 0, 255, false, 10)
    glassesDropTime = Time()
end

function base:SetGlassesOnHead(onHead)
    if onHead then
        -- Glasses are invisible while on player
        self:SetRenderingEnabled(false)
        self:SetParent(Player.HMDAvatar or Player, "")
        self:SetLocalOrigin(Vector(0,0,0))
        self:SetLocalAngles(0,0,0)
        -- self:SetRenderAlpha(0)
        -- DisableCollisions()
        self:EntFire("DisablePhyscannonPickup")
        self:DisableBlur()
        self:SetOwner(Player)
    else
        self:SetRenderingEnabled(true)
        self:SetParent(nil, "")
        -- self:SetRenderAlpha(255)
        self:EntFire("EnablePhyscannonPickup")
        -- DoEntFireByInstanceHandle(self, "EnablePhyscannonPickup", "", 0, nil, nil)
        self:EnableBlur()
        self:SetOwner(nil)
    end
end

-- function base:GlassesOnGroundThink()
--     self:CatchFallThroughWorld()

--     self:EmitSoundParams("AlyxGlasses.NotifyPosition", 0, 4, 0)
--     if particleHint == nil then
--         particleHint = ParticleManager:CreateParticle("particles/instanced/vort_menacea/shot6/grabbity_gloves_glow_c_instance1.vpcf", 1, self)
--     end
--     return 3
-- end

---Check if glasses are too far below player, and if so put back on player (assume have fallen through world)
function base:CatchFallThroughWorld()
    if abs(self:GetOrigin().z - Player:GetOrigin().z) > 4096 then
        warn("Glasses fell through the world or became too far from player z position!")
        self:WearGlasses()
    end
end

local grabFix = false

---Glasses are picked up
---@param params PLAYER_EVENT_ITEM_PICKUP
base:PlayerEvent("item_pickup", function (self, params)
    ---@cast self GlassesProp

    if grabFix then
        print('grab fix pickip')
        grabFix = false
        return
    end

    local coughpose = Player.HMDAvatar:GetFirstChildWithClassname("prop_handpose")
    if coughpose then
        coughpose:EntFire("Disable")
        coughpose:EntFire("Enable", nil, 0.1)
    end

    -- Early exit if glasses are not allowed to leave head
    if not self:IsAllowedToDropGlasses() then return end

    if params.item_name == self:GetName() then
        self:EndHint()
        isBeingHeld = true
        if self:GetMoveParent() == Player.HMDAvatar then
            devprint("Player took glasses off face")
            -- self:DropGlasses(Vector(0,0,0),0,0)
            self:SetGlassesOnHead(false)
            self:SetOrigin(params.hand:GetOrigin())
            grabFix = true
            self:Drop()
            -- self:Delay(function()
                self:Grab(params.hand)
            -- end, 0.1)
        end
    end
end)

---Attempt to stop the invalid storage message pop up when throwing glasses onto face
---@param params GAME_EVENT_PLAYER_ATTEMPTED_INVALID_STORAGE
base:GameEvent("player_attempted_invalid_storage", function (self, params)
    ---@cast self GlassesProp

    if Player.LastItemDropped == self then
        local instructorEnabled = Convars:GetStr("gameinstructor_enable")
        SendToConsole("gameinstructor_enable 0")
        SendToConsole("gameinstructor_enable " .. instructorEnabled)
    end
end)

---@param params GAME_EVENT_ITEM_RELEASED
base:PlayerEvent("item_released", function (self, params)
    ---@cast self GlassesProp

    if grabFix then
        print('grab fix release')
        return
    end

    -- if not self:IsAllowedToDropGlasses() then return end
    if params.item_name == self:GetName() then
        isBeingHeld = false
        devprints("Player trying to put glasses on", self:GetForwardVector():Dot(playerHeadForward()), VectorDistance(self:GetOrigin(), Player:EyePosition()))
        local dist = VectorDistance(self:GetOrigin(), Player:EyePosition())
        if dist <= EasyConvars:GetFloat("glasses_wear_distance")
            or (dist < EasyConvars:GetFloat("glasses_accurate_wear_distance") and self:GetForwardVector():Dot(playerHeadForward()) > 0.4)
        then
            -- playerPuttingGlassesOn = true
            self:WearGlasses()
        end
    end
end)

---Main entity think function. Think state is saved between loads
function base:Think()

    -- Detect flinging
    if self:IsWearingGlasses() then
        if playerPreviousHeadForward ~= nil then
            local head_forward = playerHeadForward()
            -- Determine if player has looked down.
            local playerFacingZ = head_forward.z
            if not playerIsLookingDown and playerFacingZ < -0.8 then
                playerIsLookingDown = true
                -- print("Player looked down.")
                printChance(EasyConvars:GetFloat("glasses_drop_from_look_down_chance"))
                if randomChance(EasyConvars:GetFloat("glasses_drop_from_look_down_chance")) then
                    devprint("Dropped glasses from looking down")
                    self.glassesWereDroppedUnintentionally = true
                    self:DropGlasses(head_forward, 50, 0)
                    --return 1
                end
            elseif playerFacingZ > -0.3 then
                playerIsLookingDown = false
            end

            -- Determine if player moved head quickly
            --print(head_forward:Dot(player.head_forward_cache))
            if head_forward:Dot(playerPreviousHeadForward) < HEAD_TWITCH_ANGLE then
                --print("HEAD TWITCHED", head_forward:Dot(player.head_forward_cache))
                if randomChance(EasyConvars:GetFloat("glasses_drop_from_head_twitch_chance")) then
                    devprint("Dropped glasses from shaking head")
                    self.glassesWereDroppedUnintentionally = true
                    self:DropGlasses(head_forward, RandomInt(125, 200), RandomInt(20, 200))
                end
            end
            playerPreviousHeadForward = head_forward
        end

    -- Glasses on ground, help player find glasses
    else
        self:CatchFallThroughWorld()

        if self.glassesWereDroppedUnintentionally and Time() - glassesDropTime > EasyConvars:GetFloat("glasses_hint_delay") then
            self:ShowHint()
            glassesDropTime = Time()
            print("HINT", Time() - glassesDropTime, EasyConvars:GetFloat("glasses_hint_delay"))
        end
    end

    -- Think interval
    return THINK_INTERVAL
end

---Show a hint for the glasses position using sound and particle.
function base:ShowHint()
    if EasyConvars:GetBool("glasses_use_hint_sound") then
        self:EmitSoundParams("AlyxGlasses.NotifyPosition", 0, 4, 0)
    end

    if EasyConvars:GetBool("glasses_use_hint_particle") then
        if particleHint == -1 then
            particleHint = ParticleManager:CreateParticle("particles/instanced/vort_menacea/shot6/grabbity_gloves_glow_c_instance1.vpcf", 1, self)
        end
    end
end

function base:EndHint()
    if particleHint ~= -1 then
        ParticleManager:DestroyParticle(particleHint, false)
        particleHint = -1
    end
end

--#region Dropping event functions

---Player teleport start game event.
---This fires when player releases thumbstick and starts teleport.
---Position is where teleport marker is, not player.
---@param params GAME_EVENT_PLAYER_TELEPORT_START
base:GameEvent("player_teleport_start", function(self, params)
    ---@cast self GlassesProp

    --data.userid
    --data.positionX
    --data.positionY
    --data.positionZ
    --data.map_name
    -- print("GameEvent: PlayerTeleportStart")
    teleportStartedFlag = true
    local playerPos = Player:GetOrigin()
    playerPreviousPos = Vector(playerPos.x, playerPos.y, playerPos.z)
end)

---Player teleport finish event.
---This fires when player finishes teleport or moves with continuous.
---@param params GAME_EVENT_PLAYER_TELEPORT_FINISH
base:GameEvent("player_teleport_finish", function (self, params)
    ---@cast self GlassesProp
    --data.userid
    --data.positionX
    --data.positionY
    --data.positionZ
    --data.map_name

    -- since this fires for continuous we only want to calculate if its preceeded by a tp start
    if not teleportStartedFlag or not self:IsWearingGlasses() then return end
    teleportStartedFlag = false
    -- print("GameEvent: PlayerTeleportFinish")
    local playerPos = Player:GetOrigin()
    -- Calculate distance
    local jumpDistance = VectorDistance(
        Vector(playerPreviousPos.x, playerPreviousPos.y, 0),
        Vector(playerPos.x, playerPos.y, 0)
    )
    local jumpForwardChance = RemapValClamped(jumpDistance, MIN_JUMP_FORWARD_TO_DROP, MAX_JUMP_FORWARD_TO_DROP, 0, 1)
    jumpForwardChance = jumpForwardChance * EasyConvars:GetFloat("glasses_drop_from_jump_forward_chance")
    -- Calculate height
    -- abs in case player jumps up
    local jumpHeight = abs(playerPos.z - playerPreviousPos.z)
    local jumpDownChance = RemapValClamped(jumpHeight, MIN_JUMP_HEIGHT_TO_DROP, MAX_JUMP_HEIGHT_TO_DROP, 0, 1)
    jumpDownChance = jumpDownChance * EasyConvars:GetFloat("glasses_drop_from_jump_down_chance")

    -- Should combine the chances or choose the max?
    local finalChance = max(jumpForwardChance, jumpDownChance)
    devprint(jumpForwardChance, jumpDownChance)
    if playerDidProperJump then
        finalChance = max(finalChance * PROPER_JUMP_MULTIPLIER, PROPER_JUMP_MIN_CHANCE)
        playerDidProperJump = false
        --print("was proper jump")
    end

    --analytic_max_jump_distance = max(analytic_max_jump_distance, jump_distance)
    --analytic_max_jump_height = max(analytic_max_jump_height, jump_height)
    --print("distance: "..jump_distance, "max: "..analytic_max_jump_distance)
    --print("height: "..jump_height, "max: "..analytic_max_jump_height)
    printChance(finalChance)
    if randomChance(finalChance) then
        devprint("Dropped glasses from movement")
        self.glassesWereDroppedUnintentionally = true
        self:DropGlasses(randomHeadForward(30), RandomInt(120, 200), RandomInt(0, 80))
    end
end)

---Player continuous jump event.
---This fires when player jumps across a gap or down a large height.
---This isn't consistently registered so should be used as an extra chance.
---@param params GAME_EVENT_PLAYER_CONTINUOUS_JUMP_FINISH
base:GameEvent("player_continuous_jump_finish", function (self, params)
    ---@cast self GlassesProp
    --data.userid
    -- print("GameEvent: PlayerContinousJumpFinish")
    playerDidProperJump = true
end)

---Player hurt game event.
---@param params GAME_EVENT_PLAYER_HURT
base:GameEvent("player_hurt", function (self, params)
    ---@cast self GlassesProp
    --data.userid
    --data.attacker
    --data.health # remaining hp

    -- Don't have a chance to drop glasses if they didn't fall off the first time player was grabbed by barnacle.
    if not self:IsWearingGlasses() or playerIsHeldByBarnacle then return end

    local hp_lost = playerPreviousHealth - params.health
    -- print("GameEvent: PlayerHurt", data.health, hp_lost)
    if hp_lost >= MIN_DAMAGE_TO_DROP then
        local mult = 1 + (hp_lost / Player:GetMaxHealth())
        local final_chance = EasyConvars:GetFloat("glasses_drop_from_damage_chance") * mult
        if hp_lost >= Convars:GetInt("sk_headcrab_melee_dmg") then
            -- print("Headcrab attached to face!")
            final_chance = 1
        end
        printChance(final_chance)
        if randomChance(final_chance) then
            devprints("Dropped glasses from damage", hp_lost)
            self.glassesWereDroppedUnintentionally = true
            self:DropGlasses(randomHeadForward(), RandomInt(100,200), RandomInt(10,200))
        end
    end
    playerPreviousHealth = params.health
    -- -- debug infinite health
    -- player.handle:SetHealth(player.handle:GetMaxHealth())
    -- player.hp_cache = player.handle:GetHealth()
end)

-- did 7, max 100, chance 52%, default chance 25%

---Player grabbed by barnacle event.
---@param params GAME_EVENT_PLAYER_GRABBED_BY_BARNACLE
base:GameEvent("player_grabbed_by_barnacle", function (self, params)
    ---@cast self GlassesProp
    --data.userid
    if playerWasGrabbedByBarnacle then
        --print("","!!!!!!!!!!!PLAYER WAS RELEASED!!!!!!!!")
        playerWasGrabbedByBarnacle = false
        return
    end

    playerWasGrabbedByBarnacle = true
    if not self:IsWearingGlasses() then return end
    -- print("GameEvent: PlayerGrabbedByBarnacle")
    --print("","!!!!!!!!!!!PLAYER WAS GRABBED!!!!!!!!")
    playerIsHeldByBarnacle = true
    printChance(EasyConvars:GetFloat("glasses_drop_from_barnacle_grab_chance"))
    if randomChance(EasyConvars:GetFloat("glasses_drop_from_barnacle_grab_chance")) then
        devprint("Dropped glasses from barnacle")
        self.glassesWereDroppedUnintentionally = true
        --local dir = randomHeadForward(45)
        --dir.z = RandomFloat(0.8, 1)
        local dir = Vector(RandomFloat(-1,1),RandomFloat(-1,1),RandomFloat(0.8, 1))
        self:DropGlasses(dir, RandomInt(100,200), RandomInt(10,200))
    end
end)

--#endregion

--Used for classes not attached directly to entities
return base