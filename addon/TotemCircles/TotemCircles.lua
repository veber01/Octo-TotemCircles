-- TotemCircles v0.4.9
TotemCirclesDB = TotemCirclesDB or {}
local db = TotemCirclesDB
local ELEMENTS = {"Fire", "Earth", "Water", "Air"}
local DEFAULT_COLORS = {"FF3030", "8B5A2B", "3090FF", "A0A0A0"}
local FALLBACK = 20

local ranges = {
  ["earthbind totem"] = 10,
  ["stoneclaw totem"] = 8,
  ["stoneskin totem"] = 20,
  ["strength of earth totem"] = 20,
  ["tremor totem"] = 20,
  ["searing totem"] = 20,
  ["fire nova totem"] = 10,
  ["magma totem"] = 8,
  ["flametongue totem"] = 20,
  ["frost resistance totem"] = 20,
  ["healing stream totem"] = 20,
  ["mana spring totem"] = 20,
  ["mana tide totem"] = 20,
  ["poison cleansing totem"] = 20,
  ["disease cleansing totem"] = 20,
  ["fire resistance totem"] = 20,
  ["windfury totem"] = 20,
  ["grace of air totem"] = 20,
  ["windwall totem"] = 20,
  ["grounding totem"] = 20,
  ["nature resistance totem"] = 20,
  ["tranquil air totem"] = 20,
  ["sentry totem"] = 20
}

local friendly = {
  ["stoneskin totem"]=true, ["strength of earth totem"]=true,
  ["tremor totem"]=true, ["flametongue totem"]=true,
  ["frost resistance totem"]=true, ["healing stream totem"]=true,
  ["mana spring totem"]=true, ["mana tide totem"]=true,
  ["poison cleansing totem"]=true, ["disease cleansing totem"]=true,
  ["fire resistance totem"]=true, ["windfury totem"]=true,
  ["grace of air totem"]=true, ["windwall totem"]=true,
  ["grounding totem"]=true, ["nature resistance totem"]=true,
  ["tranquil air totem"]=true
}
local elapsed = 0
local last = {}
local function say(s) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffTotemCircles:|r "..s) end
local function normalizeName(name)
  if not name then return "" end
  local n = string.lower(name)
  n = string.gsub(n,"%s*%([Rr]ank%s*[%w]+%)$","")
  n = string.gsub(n,"%s+[ivx]+$","")
  n = string.gsub(n,"%s+%d+$","")
  return n
end
local function validRadius(n) return n and n >= 1 and n <= 50 end

local function radiusInDescription(desc)
  if type(desc)~="string" then return nil end
  local t=string.lower(desc)
  local patterns={
    "within%s+(%d+)%s+yards?", "within%s+(%d+)%s+yds?",
    "in%s+a%s+(%d+)%s+yard%s+radius", "(%d+)%s+yard%s+radius",
    "radius%s+of%s+(%d+)%s+yards?", "up%s+to%s+(%d+)%s+yards?%s+away"
  }
  for _,pattern in ipairs(patterns) do
    local n=tonumber(string.match(t,pattern))
    if validRadius(n) then return n end
  end
  return nil
end

local function spellDesc(id)
  if not id or id<=0 or not C_Spell or type(C_Spell.GetSpellDescription)~="function" then return nil end
  local ok, desc=pcall(C_Spell.GetSpellDescription,id)
  if ok then return desc end
  return nil
end

local function masteryLearned()
  if db.mastery=="on" then return true end
  if db.mastery=="off" then return false end
  if type(GetNumTalentTabs)~="function" or type(GetNumTalents)~="function" or type(GetTalentInfo)~="function" then return false end
  local ok, found=pcall(function()
    for tab=1,GetNumTalentTabs() do
      for index=1,GetNumTalents(tab) do
        local name,_,_,_,rank=GetTalentInfo(tab,index)
        if name=="Totemic Mastery" and tonumber(rank) and tonumber(rank)>0 then return true end
      end
    end
    return false
  end)
  return ok and found or false
end

local function getRange(slot, name, spellID)
  if db.slotOverride[slot] then return db.slotOverride[slot], "slot override" end
  if db.globalRadius then return db.globalRadius, "global override" end
  local id=tonumber(spellID)
  if id and (db.spellOverride[id] or db.spellOverride[tostring(id)]) then return db.spellOverride[id] or db.spellOverride[tostring(id)], "spell override" end
  local normalized=normalizeName(name)
  if db.nameOverride[normalized] then return db.nameOverride[normalized], "name override" end
  local desc=spellDesc(id)
  local fromText=radiusInDescription(desc)
  if fromText then return fromText, "summon description" end
  if friendly[normalized] and masteryLearned() then
    return 30, "Totemic Mastery fallback (verify)"
  end
  if ranges[normalized] then return ranges[normalized], "range table (verify)" end
  if id and id>0 and C_Spell and type(C_Spell.GetSpellRadius)=="function" then
    local ok,base,modified=pcall(C_Spell.GetSpellRadius,id)
    if ok then
      local candidate=tonumber(modified) or tonumber(base)
      if validRadius(candidate) then return candidate,"summon DBC (unverified)" end
    end
  end
  return FALLBACK, "fallback (unverified)"
end

local function getInfo(slot)
  if type(GetTotemInfo)~="function" then return nil end
  local have,name,start,duration,icon,modRate,spellID=GetTotemInfo(slot)
  if not name or name=="" then return nil end
  return name,spellID
end

local function init()
  if db.enabled==nil then db.enabled=true end
  if type(db.colors)~="table" then db.colors={} end
  if type(db.visible)~="table" then db.visible={} end
  if type(db.slotOverride)~="table" then db.slotOverride={} end
  if type(db.spellOverride)~="table" then db.spellOverride={} end
  if type(db.nameOverride)~="table" then db.nameOverride={} end
  if db.height==nil then db.height=0.35 end
  if db.thickness==nil then db.thickness=0.10 end
  if db.segments==nil then db.segments=96 end
  if db.terrain==nil then db.terrain=true end
  if db.occlusion==nil then db.occlusion=true end
  if db.mastery==nil then db.mastery="auto" end
  if db.performance==nil then db.performance="high" end
  for i=1,4 do
    if not db.colors[i] then db.colors[i]=DEFAULT_COLORS[i] end
    if db.visible[i]==nil then db.visible[i]=true end
  end
end

local function sync()
  if type(TCR_SetTotem)~="function" then return end
  if type(GetTotemInfo)=="function" then
    for slot=1,4 do
      local name,id=getInfo(slot)
      local radius,source=FALLBACK,"inactive"
      if name then radius,source=getRange(slot,name,id) end
      TCR_SetTotem(slot,(db.visible[slot]~=false) and (name or "") or "",radius)
      last[slot]={name=name or "",id=id or 0,radius=radius,source=source}
    end
  end
  if type(TCR_Enable)=="function" then TCR_Enable(db.enabled and 1 or 0) end
  if type(TCR_SetMeshConfig)=="function" then TCR_SetMeshConfig(db.height,db.thickness,db.segments,db.terrain and 1 or 0) end
  if type(TCR_SetOcclusion)=="function" then TCR_SetOcclusion(db.occlusion and 1 or 0) end
  if type(TCR_SetPerformance)=="function" then
    local levels={low=0,balanced=1,high=2}
    TCR_SetPerformance(levels[db.performance] or 2)
  end
  if type(TCR_SetColor)=="function" then
    for slot=1,4 do TCR_SetColor(slot,db.colors[slot]) end
  end
end

local f=CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_TOTEM_UPDATE")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent",function() init();sync() end)
f:SetScript("OnUpdate",function()
  elapsed=elapsed+(arg1 or 0)
  if elapsed>=0.5 then elapsed=0;sync() end
end)

init()
local function numRadius(s) local n=tonumber(s); if validRadius(n) then return n end end
local function colorInput(s)
  if not s then return nil end
  s=string.gsub(s,"^#","")
  s=string.gsub(s,"^0[xX]","")
  if (string.len(s)~=6 and string.len(s)~=8) or string.find(s,"[^0-9a-fA-F]") then return nil end
  return string.upper(s)
end

SLASH_TOTEMCIRCLES1="/tcr"
SlashCmdList["TOTEMCIRCLES"]=function(msg)
  local cmd,a,b=string.match(msg or "","^(%S*)%s*(%S*)%s*(%S*)")
  if cmd=="hide" or cmd=="show" then
    local show=(cmd=="show")
    local slot=tonumber(a)
    if a=="all" then
      for i=1,4 do db.visible[i]=show end
      sync();say("All element rings "..(show and "shown" or "hidden"))
    elseif slot and slot==math.floor(slot) and slot>=1 and slot<=4 then
      db.visible[slot]=show
      sync();say(ELEMENTS[slot].." ring "..(show and "shown" or "hidden"))
    else
      say("Usage: /tcr "..cmd.." <1-4|all> (1=Fire 2=Earth 3=Water 4=Air)")
    end
  elseif cmd=="visibility" then
    for i=1,4 do say(i.." "..ELEMENTS[i]..": "..(db.visible[i]~=false and "shown" or "hidden")) end
  elseif cmd=="on" or cmd=="off" then
    db.enabled=cmd=="on";sync();say(db.enabled and "Enabled" or "Disabled")
  elseif cmd=="color" then
    local slot=tonumber(a);local hex=colorInput(b)
    if not slot or slot~=math.floor(slot) or slot<1 or slot>4 or not hex then
      say("Usage: /tcr color <1-4> <RRGGBB or AARRGGBB>; Fire=1 Earth=2 Water=3 Air=4") return end
    db.colors[slot]=hex;sync();say(ELEMENTS[slot].." color: #"..hex)
  elseif cmd=="colors" then
    for i=1,4 do say(i.." "..ELEMENTS[i].." #"..db.colors[i]) end
  elseif cmd=="colorreset" then
    local slot=tonumber(a)
    if slot and slot>=1 and slot<=4 and slot==math.floor(slot) then
      db.colors[slot]=DEFAULT_COLORS[slot]
    elseif a=="all" then
      for i=1,4 do db.colors[i]=DEFAULT_COLORS[i] end
    else say("Usage: /tcr colorreset 1-4|all");return end
    sync();say("Color defaults restored")
  elseif cmd=="radius" then
    local n=numRadius(a)
    if not n then say("Usage: /tcr radius <1-50> (sets global override do | /tcr auto | to reset)") return end
    db.globalRadius=n;sync();say("All circles overridden to "..n.." yd")
  elseif cmd=="auto" then
    db.globalRadius=nil;db.slotOverride={};sync();say("Auto range enabled")
  elseif cmd=="slot" then
    local slot=tonumber(a);local n=numRadius(b)
    if not slot or slot~=math.floor(slot) or slot<1 or slot>4 or not n then
      say("Usage: /tcr slot 1-4 <1-50>; /tcr auto to clear overrides") return end
    db.slotOverride[slot]=n;sync();say(ELEMENTS[slot].." slot: "..n.." yd override")
  elseif cmd=="spell" then
    local id=tonumber(a);local n=numRadius(b)
    if not id or id<1 or id~=math.floor(id) or not n then say("Usage: /tcr spell <summonSpellID> <yards>") return end
    db.spellOverride[id]=n;sync();say("Spell "..id.." override: "..n.." yd")
  elseif cmd=="name" then
    local n=numRadius(b)
    if not n or not a or a=="" then
      say("Usage: /tcr name <activeSlot 1-4> <yards> (saves by totem name)");return end
    local slot=tonumber(a)
    if not slot or slot<1 or slot>4 or slot~=math.floor(slot) then say("Slot must be 1-4"); return end
    local info=last[slot]
    if not info or info.name=="" then say("No active totem in that slot");return end
    db.nameOverride[normalizeName(info.name)]=n
    sync();say("Saved "..info.name.." = "..n.." yd for all ranks")
  elseif cmd=="mastery" then
    if a~="on" and a~="off" and a~="auto" then
      say("Usage: /tcr mastery auto|on|off");return end
    db.mastery=a;sync();say("Totemic Mastery setting: "..a.." (detected="..tostring(masteryLearned())..")")
  elseif cmd=="rangecheck" then
    for slot=1,4 do
      local info=last[slot]
      if info and info.name~="" then
        local desc=spellDesc(tonumber(info.id))
        local parsed=radiusInDescription(desc)
        say(info.name.." ["..tostring(info.id).."] selected="..tostring(info.radius).." yd source="..info.source.." parsed="..tostring(parsed).." mastery="..tostring(masteryLearned()))
        if desc then say("Spell description: "..string.sub(desc,1,220)) end
      end
    end
  elseif cmd=="clear" then
    if a=="spell" then
      local id=tonumber(b)
      if not id or id<1 or id~=math.floor(id) then say("Usage: /tcr clear spell <spellID>");return end
      db.spellOverride[id]=nil
      db.spellOverride[tostring(id)]=nil
      sync();say("Removed spell override for "..id)
    elseif a=="slot" then
      local slot=tonumber(b)
      if not slot or slot<1 or slot>4 or slot~=math.floor(slot) then say("Usage: /tcr clear slot <1-4>");return end
      db.slotOverride[slot]=nil
      sync();say("Removed "..ELEMENTS[slot].." slot override")
    elseif a=="name" then
      local slot=tonumber(b)
      if not slot or slot<1 or slot>4 or slot~=math.floor(slot) then say("Usage: /tcr clear name <active slot 1-4>");return end
      local info=last[slot]
      if not info or info.name=="" then say("No active totem in slot "..slot);return end
      db.nameOverride[normalizeName(info.name)]=nil
      sync();say("Removed name override for "..info.name)
    elseif a=="global" then
      db.globalRadius=nil
      sync();say("Removed global radius override")
    else
      say("Usage: /tcr clear spell <ID> | slot <1-4> | name <active slot> | global")
    end
  elseif cmd=="overrides" then
    say("Global radius: "..tostring(db.globalRadius or "auto"))
    for slot=1,4 do
      if db.slotOverride[slot] then say(ELEMENTS[slot].." slot="..db.slotOverride[slot].." yd") end
    end
    local count=0
    for id,radius in pairs(db.spellOverride) do
      say("Spell "..tostring(id).."="..tostring(radius).." yd");count=count+1
    end
    for name,radius in pairs(db.nameOverride) do
      say("Name "..name.."="..tostring(radius).." yd");count=count+1
    end
    if count==0 then say("No spell/name overrides saved") end
  elseif cmd=="height" or cmd=="thickness" then
    local n=tonumber(a);local lo=cmd=="height" and 0.02 or 0.01
    local hi=cmd=="height" and 5 or 2
    if not n or n<lo or n>hi then say("Usage: /tcr "..cmd.." <"..lo.."-"..hi..">") return end
    db[cmd]=n;sync();say(cmd.." = "..n.." yd")
  elseif cmd=="segments" then
    local n=tonumber(a)
    if not n or n~=math.floor(n) or n<12 or n>192 then say("Usage: /tcr segments 12-192") return end
    db.segments=n;sync();say("Segments: "..n)
  elseif cmd=="terrain" then
    if a~="on" and a~="off" then say("Usage: /tcr terrain on|off") return end
    db.terrain=a=="on";sync();say("Terrain following: "..a)
  elseif cmd=="occlusion" then
    if a~="on" and a~="off" then say("Usage: /tcr occlusion on|off") return end
    db.occlusion=a=="on";sync();say("Wall occlusion: "..a)
  elseif cmd=="performance" then
    if a~="low" and a~="balanced" and a~="high" then
      say("Usage: /tcr performance low|balanced|high");return end
    db.performance=a;sync()
    say("Performance: "..a)
  elseif cmd=="status" then
    say("DLL: "..tostring(type(TCR_IsReady)=="function" and TCR_IsReady() or false)..", enabled="..tostring(db.enabled)..", terrain="..tostring(db.terrain)..", occlusion="..tostring(db.occlusion)..", mastery="..tostring(db.mastery).." (learned="..tostring(masteryLearned()).."), height="..db.height..", thickness="..db.thickness..", segments="..db.segments..", performance="..db.performance)
    for slot=1,4 do
      local info=last[slot]
      if info and info.name~="" then
        say(ELEMENTS[slot].." ["..(db.visible[slot]~=false and "shown" or "hidden").."]: "..info.name.." spellID="..tostring(info.id).." radius="..info.radius.." yd ("..info.source..") #"..db.colors[slot])
      end
    end
  else
    say("/tcr color <1-4> <hex> | colors | colorreset <1-4|all> | radius <yards> | auto | slot <1-4> <yards> | spell <spellID> <yards>")
    say("/tcr name <activeSlot> <yards> | clear spell|slot|name|global <id/slot> | overrides | mastery auto|on|off | rangecheck")
    say("/tcr on|off | hide|show <1-4|all> | visibility | height <yards> | thickness <yards> | segments <n> | terrain on|off | occlusion on|off | performance low|balanced|high | status")
  end
end
