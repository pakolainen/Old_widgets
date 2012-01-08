--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    cmd_rector_automicro.lua
--  brief:   "Auto Repair & resurrect & reclaim for idle Rectors, also converts rector's additional fight commands to area repair & resurrect & reclaim"
-- bugs: uses area repair..bad for repairing moving units and repeatly try to area repair ally unit being reclaimed--> if multiple user have the widget may result to a slight command spam??
--TODO: convert fight command to a "resurrection fight", when rector is command to fight with other units should guard attacking unit and then commanded like a idle rector, should always try to reclaim near big enemy tanks because they have a low buildTime/HP ratio and cant shoot surrounding rectors, should reclaim the resurrected unit at low HP if not wanted unit or metal needed
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name      = "Rector Auto Micro",
    desc      = "[v2.1]Auto Repair&Resurrect&Reclaim for Idle Rectors; converts rector's additional fight command to area Repair&Resurrect&Reclaim; runs away from near enemy or reclaims the near enemy if under 200 hp",
    author    = "TheFatController..Pako",
    date      = "09.06.2009",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true  --  loaded by default?
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
local GetFeatureResources = Spring.GetFeatureResources

local RECTOR = UnitDefNames['armrectr'].id
local NECRO = UnitDefNames['cornecro'].id

local noReclaimList = {}
noReclaimList["Dragon's Teeth"] = true
noReclaimList["Shark's Teeth"] = true
noReclaimList["Fortification Wall"] = true
noReclaimList["Spike"] = true
noReclaimList["Commander Wreckage"] = true

local watchList = {}
local UPDATE = 1
local timeCounter = 0


function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
    return false
  end
  
  local teamUnits = GetTeamUnits(GetMyTeamID())
  for _,unitID in ipairs(teamUnits) do
    local unitDefID = GetUnitDefID(unitID)
    if (unitDefID == RECTOR or unitDefID == NECRO) then
      watchList[unitID] = 1
    end
  end

end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
  if (unitDefID == RECTOR or unitDefID == NECRO) and (unitTeam == GetMyTeamID()) then
    local curH = GetUnitHealth(unitID)
    watchList[unitID] = curH
  end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
  watchList[unitID] = nil
end

function widget:UnitTaken(unitID, unitDefID, unitTeam)
  watchList[unitID] = nil
end

local function getDistance(x1,z1,x2,z2)
  local dx,dz = x1-x2,z1-z2 
  return (dx*dx)+(dz*dz)
end

local enemySeekDistance = 375 --evade/reclaim
local repairSeekDistance = 375
local rezRecDistance = 375 

local function doSomething(unitID)
	local uOrders = GetUnitStates(unitID)
	local moveState = uOrders["movestate"]
		if (moveState > 0) then
		local repairSeekDistance = repairSeekDistance
		local rezRecDistance = rezRecDistance
		if moveState == 2 then
			rezRecDistance = rezRecDistance*2
			repairSeekDistance = repairSeekDistance*2
		end
        local nearEnemyID = GetUnitNearestEnemy(unitID,enemySeekDistance)
        if (nearEnemyID ~= nil) then
		  local hp,maxhp = GetUnitHealth(nearEnemyID)
		  if(hp and hp<200)then -- if hp/maxhp < 0.1
          GiveOrderToUnit(unitID, CMD.RECLAIM, {nearEnemyID}, {  })
		  else
		  local x1,_,z1 = GetUnitPosition(nearEnemyID)
		  local x2,y,z2 = GetUnitPosition(unitID)
		  GiveOrderToUnit(unitID, CMD.MOVE, {x2+(x2-x1), y, z2+(z2-z1)},{})
		  end
        else
          local x1,_,z1 = GetUnitPosition(unitID)
          local nearUnits = GetUnitsInCylinder(x1, z1, repairSeekDistance)
          local nearAlly = math.huge
          local nearAllyID = nil
		  local nearFeat = math.huge
          local nearFeatID = nil
		  local x,y,z
          for _,uID in pairs(nearUnits) do
            if (uID ~= unitID) then
			  local hp, maxhp,_,_,buildProgress = GetUnitHealth(uID)
              if (hp ~=nil and hp < maxhp and buildProgress==1) then
                local x2,y2,z2 = GetUnitPosition(uID)
                local dist = getDistance(x1,z1,x2,z2)
                if (dist < nearAlly) then
                  nearAllyID = uID
                  nearAlly = dist
				  x=x2
				  y=y2
				  z=z2
                end
              end
            end
			if (nearAllyID == nil) then
			local nearFeatures = GetFeaturesInRectangle(x1-rezRecDistance, z1-rezRecDistance, x1 + rezRecDistance, z1 + rezRecDistance)
			for _,fID in pairs(nearFeatures) do
			local x2,y2,z2 = GetFeaturePosition(fID)
			if(x2~=nil)then
			local dist = getDistance(x1,z1,x2,z2)
			if (dist < nearFeat) then
				local fdid = Spring.GetFeatureDefID(fID)
				local fdef = fdid and FeatureDefs[fdid]
				if fdef and(fdef.reclaimable) and (Spring.GetFeatureAllyTeam(fID)~=Spring.GetLocalAllyTeamID() or not noReclaimList[fdef.tooltip]) then
                  nearFeatID = fID
                  nearFeat= dist
				  x=x2
				  y=y2
				  z=z2
				  end
                end
			end
			end
			end
          end
          if (nearAllyID ~= nil) then
            GiveOrderToUnit(unitID, CMD.REPAIR, {x,y,z,40}, {"shift"}) -- arerepair to prevent repairing reclaimed building
		  elseif (nearFeatID ~= nil and nearFeat<(1000^2)) then  --there seems to some ''range bug in GetFeaturesInRectangle 
		   GiveOrderToUnit(unitID, CMD.RESURRECT, {nearFeatID+Game.maxUnits}, {"shift"})
		   --GiveOrderToUnit(unitID, CMD.RECLAIM, {x,y,z,20}, {"shift"}) --areareclaim to prevent reclaiming ally DT
		    GiveOrderToUnit(unitID, CMD.RECLAIM, {nearFeatID+Game.maxUnits}, {"shift"})
          end
        end
	end
end

local idle = false

function widget:UnitIdle(unitID, unitDefID, unitTeam)
	if watchList[unitID] and watchList[unitID] == 0 then
		--doSomething(unitID)
		--local cQueue = GetCommandQueue(unitID)
      --if cQueue and (#cQueue == 0) then
	  --  doSomething(unitID)
	  --end
		watchList[unitID] = 1
		if not idle then
		idle = Spring.GetGameFrame() + 10
		end
	end
end

function widget:Update(deltaTime)
  if (next(watchList) == nil) then return false end
    
  if idle == Spring.GetGameFrame() or (timeCounter > UPDATE) then
    timeCounter = 0
	
  if Spring.GetSpectatingState() then
    widgetHandler:RemoveWidget()
    return false
  end
    
    for unitID,_ in pairs(watchList) do
      --local curH = GetUnitHealth(unitID)
      --watchList[unitID] = curH
	 
      local cQueue = GetCommandQueue(unitID)

      if cQueue and (#cQueue == 0) and ((not idle) or (idle and watchList[unitID] == 1)) then
	    doSomething(unitID) 
		watchList[unitID] = 0
      elseif (cQueue == nil) then
        watchList[unitID] = nil
	  end
	  --[[
	  ---rez bug
	  --dont resurrect partially reclaimed wrecks
	  cQueue = GetCommandQueue(unitID)
	  if(cQueue and #cQueue>0 and cQueue[1].id == CMD.RESURRECT) then
	  _,_,_,_,reclaimLeft        = GetFeatureResources(cQueue[1].params[1]-Game.maxUnits)
	  if(reclaimLeft and reclaimLeft~=1.0)then
	  GiveOrderToUnit(unitID, CMD.REMOVE, {cQueue[1].tag}, {})
	  GiveOrderToUnit(unitID, CMD.INSERT, {0, CMD.RECLAIM, CMD.OPT_SHIFT, cQueue[1].params[1]}, {"alt"})
	  end
	  end
	  --rez bug
	  --]]	  
    end
	
	idle = false
	
  else
    timeCounter = (timeCounter + deltaTime)
  end
end

function widget:CommandNotify(commandID, params, options)
  local selUnits = Spring.GetSelectedUnits()
  local count = #selUnits

  if (commandID == CMD.FIGHT) then
   for k,unitID in pairs(selUnits) do
    local rect = watchList[unitID]
	if(rect~=nil)then
	local cQueue = Spring.GetCommandQueue(unitID)
	local x1,y1,z1
	local x2,y2,z2 = params[1],params[2],params[3]
	if(cQueue~=nil and (#cQueue)>1)then
	 x1 = cQueue[#cQueue-1]["params"][1]
	 y1 = cQueue[#cQueue-1]["params"][2]
	 z1 = cQueue[#cQueue-1]["params"][3]
	end
	if(z1==nil)then
	x1,y1,z1 = GetUnitPosition(unitID)
	end
	local dist = getDistance(x1,z1,x2,z2)^0.5
	
	--local xcenter=(x1-x2)/2 + x2
	--local zcenter=(z1-z2)/2 + z2
	
	local xcenter=x1
	local zcenter=z1

	GiveOrderToUnit(unitID, CMD.INSERT, {-1, CMD.REPAIR, CMD.OPT_SHIFT, xcenter, y1, zcenter, dist}, {"alt"})	
	GiveOrderToUnit(unitID, CMD.INSERT, {-1, CMD.RESURRECT, CMD.OPT_SHIFT, xcenter, y1, zcenter, dist}, {"alt"})
	GiveOrderToUnit(unitID, CMD.INSERT, {-1, CMD.RECLAIM, CMD.OPT_SHIFT, xcenter, y1, zcenter, dist}, {"alt"})
	GiveOrderToUnit(unitID, CMD.INSERT, {-1, CMD.REPAIR, CMD.OPT_SHIFT, xcenter, y1, zcenter, dist}, {"alt"})
	end
	end  
  end
end
