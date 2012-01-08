--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    cmd_rector_automicro.lua
--  brief:   V1.0 Auto Capture & Repair for Idle Rectors
--  author:  OWen Martindell
--
--  Copyright (C) 2008.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name      = "Sniper auto micro",
    desc      = "Increases snipers effective damage by only attacking high HP units",
    author    = "TheFatController..Pako",
    date      = "09.06.2009",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = false  --  loaded by default?
  }
end

local GetCommandQueue = Spring.GetCommandQueue
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitAllyTeam = Spring.GetUnitAllyTeam
local GetMyAllyTeamID = Spring.GetMyAllyTeamID
local GetMyTeamID = Spring.GetMyTeamID
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GiveOrderToUnit = Spring.GiveOrderToUnit
local GetUnitHealth = Spring.GetUnitHealth
local GetTeamUnits = Spring.GetTeamUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitStates = Spring.GetUnitStates
local GetUnitNearestEnemy = Spring.GetUnitNearestEnemy
local GetFeaturesInRectangle = Spring.GetFeaturesInRectangle
local GetFeaturePosition = Spring.GetFeaturePosition
local udefTab = UnitDefs

local SNIPER = UnitDefNames['armsnipe'].id
local ASPY = UnitDefNames['armspy'].id
local CSPY = UnitDefNames['corspy'].id
local ATARG = UnitDefNames['armtarg'].id
local CTARG = UnitDefNames['cortarg'].id

local SnipeRange = 900
local SnipeRangeSqr = 900*900
local SniperRetreatRange = 300 --oikeesti auto_skirm hoitaa per‰‰ntymisen--poistetaan vaan attack komento ja laitetaan fire at will jos tarpeeks energiaa
local minHPtoAttack = 800

local snipers = {}
local spys = {}
local enemies = {}
local targeting = 0

local UPDATE = 0.63
local timeCounter = 0



function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
    return false
  end
  local myTeam = GetMyTeamID()
  local teamUnits = GetTeamUnits(myTeam)
  for _,unitID in ipairs(teamUnits) do
    local unitDefID = GetUnitDefID(unitID)
    UnitFinished(unitID, unitDefID, myTeam)
  end
  
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
if(unitTeam == GetMyTeamID()) then
  if (unitDefID == SNIPER) then
  Spring.GiveOrderToUnit(unitID, CMD.MOVE_STATE, {0}, {} )
  Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, {0}, {} )
    snipers[unitID] = {}
	snipers[unitID].fighting = false
	snipers[unitID].retreating = false
	snipers[unitID].enemy = nil
  end
  if (unitDefID == ASPY)or(unitDefID == CSPY) then
  spys[unitID] = {}
  spys[unitID].fighting = false
  spys[unitID].evading = false
  spys[unitID].waiting = false
  end
  if (unitDefID == ATARG)or(unitDefID == ATARG) then
  targeting = targeting + 1
  end
  
  end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
end

function widget:UnitTaken(unitID, unitDefID, unitTeam)
end

local function distance(dx,dz)
  return (dx*dx)+(dz*dz)
end

local function updateSniper(unitID, snipe)

local x, y, z = Spring.GetUnitPosition(unitID)
if not x then 
snipers[unitID]=nil 
return 
end
local cQueue = Spring.GetCommandQueue(unitID)
		  
local findTarget = true  -- Need to find (new) target?
  
  if snipe.enemy then  -- vois kyll‰ melkein joka kerta etsi‰ parhaan enemyn mutta sniping menee liian suureks?
    local x2, y2, z2 = Spring.GetUnitPosition(snipe.enemy)
    if x2 then
      local dist=distance(x - x2, z - z2)
	  if dist < SnipeRangeSqr or (snipe.fighting == true and dist < (SnipeRangeSqr*(2*2)))then
        findTarget = false  -- Enemy in range
		if #cQueue == 0 then
		Spring.GiveOrderToUnit(unitID, CMD.ATTACK, {snipe.enemy}, CMD.OPT_RIGHT)
		end
	  else
	  if #cQueue > 0 and cQueue[1].id == CMD.ATTACK and cQueue[1].id.params[1] == snipe.enemy then
	  Spring.GiveOrderToUnit(unit, CMD.REMOVE, {cQueue[1].tag}, {} )
	  end
	  snipe.enemy = nil
      end
	  else
	  snipe.enemy = nil
    end
  end

  local e = Spring.GetUnitNearestEnemy(unitID, SniperRetreatRange)
  if(e)then
  local x2, y2, z2 = Spring.GetUnitPosition(e)
  if x2 then
      local dist=distance(x - x2, z - z2)
   if dist < SniperRetreatRange*SniperRetreatRange then
	 --[[ if cQueue[1].id == CMD.ATTACK and cQueue[1].id.params[1] == snipe.enemy then
	  Spring.GiveOrderToUnit(unit, CMD.REMOVE, {cQueue[1].tag}, {} )
	  end--]]
	  Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, {2}, {} )
	  Spring.GiveOrderToUnit(unitID, CMD.CLOAK, {1}, {})
	  Spring.GiveOrderToUnit(unitID, CMD.FIGHT, {x2,y2,z2}, CMD.OPT_RIGHT)	  
	  snipe.retreating = true
  else
  if snipe.retreating == true then
  Spring.GiveOrderToUnit(unitID, CMD.CLOAK, {0}, {})	 
  Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, {0}, {} )
  snipe.retreating=false
  snipe.fighting = true --?????????????????????????
  end
  end
  end
  end
  
  if snipe.retreating == true then
  findTarget = false
  end
  
  if findTarget == true then
  
		  local range
		  if snipe.fighting == true then range = SnipeRange*2 else range = SnipeRange end
          local nearUnits = Spring.GetUnitsInCylinder(x, z, range)
		  local bestEnemy
		  local bestEnemyHP = 0
		  
		  local xe,ye,ze
			local allyTeam = Spring.GetMyAllyTeamID()
            for _,uID in pairs(nearUnits) do
			
			local health
			local enemy = enemies[uID]
            if (allyTeam ~= Spring.GetUnitAllyTeam(uID)) then
			
                local x2,y2,z2 = GetUnitPosition(uID)
                if(x2) then
				if enemy and enemy.maxHealth and enemy.maxHealth >= minHPtoAttack then
				if(enemy.los == true) then
				local hp, maxhp = Spring.GetUnitHealth(uID)
				enemy.health = hp
				end
				 health = enemy.health
				 if(enemy.sniping) then health = health/enemy.sniping end
				 
				else
				local dist = distance(x-x2,z-z2)
				if(targeting>1 and dist<SnipeRangeSqr) then
				local cvx, cvy, cvz = Spring.GetUnitVelocity(uID)--radar dotteihin ammutaan hitauden perusteella jos pari targeting fac.
				if cvx then
				health = 300/(cvx+cvy+cvz+1)
				else
				health = 50
				end
				end
				end
				end
				end
				
				if(health and health > bestEnemyHP)then 
				   bestEnemyHP=health 
				   bestEnemy = uID
				   end
				   end
				
				
if(bestEnemy) then 
snipe.enemy=bestEnemy
if enemies[bestEnemy] then
if enemies[bestEnemy].sniping then
enemies[bestEnemy].sniping = enemies[bestEnemy].sniping + 1 
else
enemies[bestEnemy].sniping = 2
end
end
if #cQueue == 0 or cQueue[1].id == CMD.FIGHT then
Spring.GiveOrderToUnit(unitID, CMD.ATTACK, {bestEnemy}, CMD.OPT_RIGHT) ---------------INSERT--ei insert ett‰ pys‰htyy latauksen ajaksi...
end
end
				
  
  end
  
end

function widget:Update(deltaTime)
  if (next(snipers) == nil) then return false end
    
  if (timeCounter > UPDATE) then
    timeCounter = 0

	if Spring.GetSpectatingState() then
    widgetHandler:RemoveWidget()
    return false
	end
    
    for unitID, snipe in pairs(snipers) do
      updateSniper(unitID, snipe)
	 end
	 --for unitID, spy in pairs(spys) do
      --updateSpy(unitID, spy)
	 --end
  else
    timeCounter = (timeCounter + deltaTime)
  end
end


function widget:CommandNotify(commandID, params, options)
  local selUnits = Spring.GetSelectedUnits()
  local count = #selUnits

   for k,unitID in pairs(selUnits) do
    local snipe = snipers[unitID]
	local spy = spys[unitID]
		if(snipe~=nil)then
			if (commandID == CMD.FIGHT) then
				snipe.fighting=true --may not be the current command but only seeking enemies from extended area
			else
				if (commandID == CMD.MOVE) then
					--Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, {2}, {} )
					snipe.fighting=false
					snipe.enemy=nil
				end
			end
		end
				if(spy~=nil)then
					if (commandID == CMD.FIGHT) then
						spy.fighting=true --may not be the current command but only seeking enemies from extended area
					else
						spy.fighting=false
					end
				end
	end  
end


function widget:UnitEnteredRadar(unitID, allyTeam)
	if ( enemies[unitID] ~= nil ) then
		enemies[unitID]["radar"] = true
	end
end

function widget:UnitEnteredLos(unitID, allyTeam )
	--update unitID info, ID could have been reused already!
	local udefID = Spring.GetUnitDefID(unitID)
	local hp, maxhp = GetUnitHealth(unitID)
	
		enemies[unitID] = {}
		enemies[unitID]["unitDefId"] = udefID
		enemies[unitID]["teamId"] = allyTeam
		enemies[unitID]["radar"] = true
		enemies[unitID]["los"] = true
		enemies[unitID]["maxHealth"] = maxhp
		enemies[unitID]["health"] = hp
		enemies[unitID]["sniping"] = 1
end


function widget:UnitCreated(unitID, allyTeam)
	--kill the dot info if this unitID gets reused on own team
	if ( enemies[unitID] ~= nil ) then
		enemies[unitID] = nil
	end
end


function widget:UnitLeftRadar(unitID, allyTeam)
	if ( enemies[unitID] ~= nil ) then
		enemies[unitID]["radar"] = false
	end
end

function widget:UnitLeftLos(unitID, allyTeam)
	if ( enemies[unitID] ~= nil ) then
		enemies[unitID]["los"] = false
	end
end
