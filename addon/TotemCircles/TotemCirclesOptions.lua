local db=TotemCirclesDB
local names={"Fire","Earth","Water","Air"}
local defaults={"FF3030","8B5A2B","3090FF","A0A0A0"}
local palettes={"FF3030","FF8800","FFD43B","8B5A2B","36B66B","3090FF","8060E8","A0A0A0","FFFFFF","101010"}
local pages={}
local controls={}
local activePage="General"
local refreshAll
local setting=false

local function command(s)
  if setting then return end
  SlashCmdList["TOTEMCIRCLES"](s)
  if refreshAll then refreshAll() end
end

local function backdrop(frame,r,g,b,a)
  frame:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=13,insets={left=3,right=3,top=3,bottom=3}})
  frame:SetBackdropColor(r or 0.06,g or 0.075,b or 0.095,a or 0.96)
  frame:SetBackdropBorderColor(0.26,0.36,0.44,1)
end

local function label(parent,text,x,y,width,size,color)
  local fs=parent:CreateFontString(nil,"OVERLAY",size or "GameFontNormal")
  fs:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
  fs:SetWidth(width or 320)
  fs:SetJustifyH("LEFT")
  if color then fs:SetTextColor(color[1],color[2],color[3]) end
  fs:SetText(text)
  return fs
end

local function button(parent,text,x,y,w,h,action)
  local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
  b:SetWidth(w or 100)
  b:SetHeight(h or 24)
  b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
  b:SetText(text)
  b:SetScript("OnClick",action)
  return b
end

local function edit(parent,x,y,w,initial,maxLetters)
  local e=CreateFrame("EditBox",nil,parent)
  e:SetWidth(w)
  e:SetHeight(24)
  e:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
  e:SetAutoFocus(false)
  e:SetMaxLetters(maxLetters or 14)
  e:SetFontObject("ChatFontNormal")
  e:SetTextInsets(7,7,2,2)
  e:SetJustifyH("LEFT")
  e:SetTextColor(1,1,1)
  e:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
  e:SetBackdropColor(0.025,0.025,0.035,0.95)
  e:SetBackdropBorderColor(0.3,0.37,0.43,1)
  e:SetText(initial or "")
  e:SetScript("OnEscapePressed",function() this:ClearFocus() end)
  e:SetScript("OnEnterPressed",function() this:ClearFocus() end)
  e:SetScript("OnEditFocusGained",function() this:SetBackdropBorderColor(0.6,0.72,0.85,1) end)
  e:SetScript("OnEditFocusLost",function() this:SetBackdropBorderColor(0.3,0.37,0.43,1) end)
  return e
end

local function check(parent,text,x,y,read,apply)
  local b=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate")
  b:SetWidth(25)
  b:SetHeight(25)
  b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
  local fs=label(parent,text,x+30,y-4,330,"GameFontHighlight")
  b:SetScript("OnClick",function() apply(this:GetChecked() and true or false) end)
  table.insert(controls,function() b:SetChecked(read() and 1 or nil) end)
  return b,fs
end

local function slider(parent,text,x,y,minVal,maxVal,step,read,apply,format)
  label(parent,text,x,y,235,"GameFontHighlight")
  local s=CreateFrame("Slider",nil,parent)
  s:SetOrientation("HORIZONTAL")
  s:SetWidth(230)
  s:SetHeight(18)
  s:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y-26)
  s:SetMinMaxValues(minVal,maxVal)
  s:SetValueStep(step)
  local track=s:CreateTexture(nil,"BACKGROUND")
  track:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
  track:SetAllPoints(s)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local thumb=s:GetThumbTexture()
  thumb:SetWidth(28)
  thumb:SetHeight(28)
  local value=label(parent,"",x+242,y-26,90,"GameFontNormal")
  local function pretty(v)
    if format then return format(v) end
    return tostring(v)
  end
  s:SetScript("OnValueChanged",function()
    local v=this:GetValue()
    value:SetText(pretty(math.floor(v/step+0.5)*step))
  end)
  s:SetScript("OnMouseUp",function()
    local v=math.floor(this:GetValue()/step+0.5)*step
    apply(v)
  end)
  table.insert(controls,function()
    local v=read()
    s:SetValue(v)
    value:SetText(pretty(v))
  end)
  return s
end

local function round(n,d)
  local mult=math.pow(10,d)
  return math.floor(n*mult+0.5)/mult
end

local root=CreateFrame("Frame","TotemCirclesOptionsFrame",UIParent)
root:SetWidth(665)
root:SetHeight(555)
root:SetPoint("CENTER",UIParent,"CENTER",0,0)
root:SetFrameStrata("DIALOG")
root:SetMovable(true)
root:EnableMouse(true)
root:RegisterForDrag("LeftButton")
root:SetScript("OnDragStart",function() this:StartMoving() end)
root:SetScript("OnDragStop",function() this:StopMovingOrSizing() end)
backdrop(root)
root:Hide()

label(root,"TotemCircles v0.5",20,-18,350,"GameFontNormalLarge")
label(root,"World-space Shaman totem range indicator",20,-42,420,"GameFontHighlightSmall",{0.72,0.8,0.85})
button(root,"X",623,-12,28,23,function() root:Hide() end)

local navigation=CreateFrame("Frame",nil,root)
navigation:SetPoint("TOPLEFT",root,"TOPLEFT",14,-75)
navigation:SetWidth(148)
navigation:SetHeight(445)
backdrop(navigation,0.045,0.055,0.07,0.9)
local content=CreateFrame("Frame",nil,root)
content:SetPoint("TOPLEFT",root,"TOPLEFT",173,-75)
content:SetWidth(476)
content:SetHeight(445)
backdrop(content,0.07,0.08,0.1,0.8)
label(root,"Settings are saved automatically. /tcrui opens this window.",18,-529,620,"GameFontHighlightSmall",{0.66,0.75,0.8})

local function page(name)
  local p=CreateFrame("Frame",nil,content)
  p:SetAllPoints(content)
  p:Hide()
  pages[name]=p
  label(p,name,18,-17,420,"GameFontNormalLarge")
  return p
end

local general=page("General")
check(general,"Enable all totem range circles",20,-70,function() return db.enabled end,function(v) command(v and "on" or "off") end)
check(general,"Follow terrain",20,-100,function() return db.terrain end,function(v) command("terrain "..(v and "on" or "off")) end)
check(general,"Enable occlusion",20,-130,function() return db.occlusion end,function(v) command("occlusion "..(v and "on" or "off")) end)
check(general,"Show minimap button",20,-160,function() return db.minimapVisible~=false end,function(v) command("minimap "..(v and "on" or "off")) end)
label(general,"Element visibility",20,-230,290,"GameFontNormal")
label(general,"if you encounter issues inside raids or dungeons,               try disabling occlusion for the time being                       (some objects has weird occlusions)",225,-130,290,"GameFontHighlightSmall",{0.66,0.75,0.8})
for slot=1,4 do
  local i=slot
  local x=(slot<=2) and 20 or 235
  local y=(slot==1 or slot==3) and -271 or -317
  check(general,names[slot].." ("..slot..")",x,y,function() return db.visible[i]~=false end,function(v) command((v and "show " or "hide ")..i) end)
end
button(general,"Show all",20,-383,100,24,function() command("show all") end)
button(general,"Hide all",131,-383,100,24,function() command("hide all") end)

local appearance=page("Appearance")
slider(appearance,"Circle wall height (yards)",22,-64,0.02,5,0.01,function() return db.height or 0.35 end,function(v) command("height "..round(v,2)) end,function(v) return string.format("%.2f",v) end)
slider(appearance,"Circle thickness (yards)",22,-145,0.01,2,0.01,function() return db.thickness or 0.10 end,function(v) command("thickness "..round(v,2)) end,function(v) return string.format("%.2f",v) end)
slider(appearance,"Terrain sampling segments",22,-226,12,192,1,function() return db.segments or 96 end,function(v) command("segments "..v) end)
label(appearance,"Circle quality is also affected by Performance presets.",22,-325,425,"GameFontHighlightSmall")

local colors=page("Colors")
local colorFields={}
for slot=1,4 do
  local i=slot
  local y=-51-(slot-1)*96
  label(colors,slot.."  "..names[slot],17,y,146,"GameFontNormal")
  local swatch=CreateFrame("Frame",nil,colors)
  swatch:SetWidth(28)
  swatch:SetHeight(20)
  swatch:SetPoint("TOPLEFT",colors,"TOPLEFT",145,y+4)
  backdrop(swatch)
  local fill=swatch:CreateTexture(nil,"ARTWORK")
  fill:SetPoint("TOPLEFT",swatch,"TOPLEFT",3,-3)
  fill:SetPoint("BOTTOMRIGHT",swatch,"BOTTOMRIGHT",-3,3)
  local field=edit(colors,188,y+5,105,"",8)
  colorFields[i]=field
  button(colors,"Apply",302,y+5,70,23,function()
    local v=string.gsub(field:GetText() or "","^#","")
    if (string.len(v)==6 or string.len(v)==8) and not string.find(v,"[^0-9a-fA-F]") then
      command("color "..i.." "..string.upper(v))
    else
      field:SetText(db.colors[i] or defaults[i])
    end
    field:ClearFocus()
  end)
  button(colors,"Reset",382,y+5,70,23,function() command("colorreset "..i) end)
  local choices={}
  for index=1,10 do
    local hex=palettes[index]
    local c=CreateFrame("Button",nil,colors)
    c:SetWidth(22)
    c:SetHeight(17)
    c:SetPoint("TOPLEFT",colors,"TOPLEFT",18+(index-1)*43,y-29)
    local t=c:CreateTexture(nil,"BACKGROUND")
    t:SetAllPoints(c)
    t:SetTexture(tonumber(string.sub(hex,1,2),16)/255,tonumber(string.sub(hex,3,4),16)/255,tonumber(string.sub(hex,5,6),16)/255)
    c:SetScript("OnClick",function() command("color "..i.." "..hex) end)
    table.insert(choices,c)
  end
  table.insert(controls,function()
    local h=db.colors[i] or defaults[i]
    if not field:HasFocus() then field:SetText(h) end
    local c=string.sub(h,-6)
    if string.len(c)==6 then fill:SetTexture(tonumber(string.sub(c,1,2),16)/255,tonumber(string.sub(c,3,4),16)/255,tonumber(string.sub(c,5,6),16)/255) end
  end)
end

local rangesPage=page("Ranges")
local globalSlider=slider(rangesPage,"Global radius override (yards)",20,-60,1,50,1,function() return db.globalRadius or 20 end,function(v) command("radius "..v) end)
local globalInfo=label(rangesPage,"",360,-90,110,"GameFontHighlightSmall")
button(rangesPage,"Clear global",20,-120,120,24,function() command("clear global") end)
button(rangesPage,"Auto all slots",153,-120,126,24,function() command("auto") end)
label(rangesPage,"Element overrides",20,-163,215,"GameFontNormal")
local rangeInputs={}
for slot=1,4 do
  local i=slot
  local y=-190-(slot-1)*40
  label(rangesPage,names[i],20,y,82,"GameFontHighlight")
  local e=edit(rangesPage,115,y+5,55,"",3)
  rangeInputs[i]=e
  button(rangesPage,"Set",186,y+5,57,22,function()
    local v=tonumber(e:GetText())
    if v and v>=1 and v<=50 then command("slot "..i.." "..v) end
  end)
  button(rangesPage,"Auto",249,y+5,66,22,function() command("clear slot "..i) end)
end
local mastery=label(rangesPage,"Totemic Mastery fallback",333,-165,142,"GameFontNormal")
local masteryButtons={}
for index,mode in ipairs({"auto","on","off"}) do
  local v=mode
  masteryButtons[index]=button(rangesPage,string.upper(string.sub(mode,1,1))..string.sub(mode,2),326,-193-(index-1)*37,120,24,function() command("mastery "..v) end)
end
local masteryInfo=label(rangesPage,"",325,-312,145,"GameFontHighlightSmall")
table.insert(controls,function()
  globalInfo:SetText(db.globalRadius and ("Override: "..db.globalRadius.." yd") or "Automatic")
  masteryInfo:SetText("Current: "..(db.mastery or "auto"))
  for slot=1,4 do if not rangeInputs[slot]:HasFocus() then rangeInputs[slot]:SetText(db.slotOverride[slot] and tostring(db.slotOverride[slot]) or "") end end
end)

local custom=page("Custom Ranges")
label(custom,"Spell ID override",20,-58,220,"GameFontNormal")
local spellID=edit(custom,20,-91,110,"",10)
local spellRange=edit(custom,145,-91,73,"",3)
label(custom,"Spell ID",20,-122,90,"GameFontHighlightSmall")
label(custom,"Yards",145,-122,70,"GameFontHighlightSmall")
button(custom,"Save",232,-91,82,23,function()
  local id=tonumber(spellID:GetText())
  local radius=tonumber(spellRange:GetText())
  if id and id>=1 and id==math.floor(id) and radius and radius>=1 and radius<=50 then command("spell "..id.." "..radius) end
end)
button(custom,"Remove",325,-91,90,23,function()
  local id=tonumber(spellID:GetText())
  if id and id>=1 and id==math.floor(id) then command("clear spell "..id) end
end)
label(custom,"Active totem name override",20,-160,424,"GameFontNormal")
local nameRange=edit(custom,145,-197,75,"",3)
label(custom,"Yards",145,-227,75,"GameFontHighlightSmall")
local selectedSlot=1
local slotPick={}
for slot=1,4 do
  local i=slot
  slotPick[slot]=button(custom,names[slot],20,-197-(slot-1)*35,113,24,function()
    selectedSlot=i
    if refreshAll then refreshAll() end
  end)
end
button(custom,"Save name",240,-197,113,24,function()
  local radius=tonumber(nameRange:GetText())
  if radius and radius>=1 and radius<=50 then command("name "..selectedSlot.." "..radius) end
end)
button(custom,"Remove name",240,-232,113,24,function() command("clear name "..selectedSlot) end)
button(custom,"Print overrides",240,-309,150,24,function() command("overrides") end)
button(custom,"Check active ranges",240,-345,150,24,function() command("rangecheck") end)
local slotSelected=label(custom,"",240,-277,215,"GameFontHighlightSmall")
table.insert(controls,function() slotSelected:SetText("Selected: "..selectedSlot.." "..names[selectedSlot]) end)

local performance=page("Performance")
label(performance,"Quality presets",20,-62,320,"GameFontNormal")
local perfInfo=label(performance,"",20,-102,400,"GameFontHighlight")
for index,mode in ipairs({"low","balanced","high"}) do
  local v=mode
  button(performance,string.upper(string.sub(mode,1,1))..string.sub(mode,2),20+(index-1)*145,-141,132,27,function() command("performance "..v) end)
end
label(performance,"Low: 32 segments / 250 ms occlusion",20,-210,420,"GameFontHighlight")
label(performance,"Balanced: 64 segments / 150 ms occlusion",20,-246,420,"GameFontHighlight")
label(performance,"High: 96 segments / 100 ms occlusion",20,-282,420,"GameFontHighlight")
label(performance,"Terrain sampling uses the Appearance setting.",20,-354,420,"GameFontHighlightSmall")
table.insert(controls,function() perfInfo:SetText("Selected: "..(db.performance or "high")) end)

local categories={"General","Appearance","Colors","Ranges","Custom Ranges","Performance"}
local navButtons={}
for i,name in ipairs(categories) do
  local n=name
  navButtons[i]=button(navigation,name,9,-14-(i-1)*46,128,31,function()
    activePage=n
    refreshAll()
  end)
end

refreshAll=function()
  db=TotemCirclesDB or db
  for name,p in pairs(pages) do
    if name==activePage then p:Show() else p:Hide() end
  end
  for _,fn in ipairs(controls) do fn() end
end

root:SetScript("OnShow",function() refreshAll() end)

function TotemCircles_ToggleOptions()
  if root:IsShown() then root:Hide() else root:Show() end
end

local minimapButton=CreateFrame("Button","TotemCirclesMinimapButton",Minimap)
minimapButton:SetWidth(31)
minimapButton:SetHeight(31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(Minimap:GetFrameLevel()+5)
minimapButton:EnableMouse(true)
minimapButton:RegisterForClicks("LeftButtonUp")
minimapButton:RegisterForDrag("LeftButton")

local minimapIcon=minimapButton:CreateTexture(nil,"ARTWORK")
minimapIcon:SetWidth(21)
minimapIcon:SetHeight(21)
minimapIcon:SetPoint("CENTER",minimapButton,"CENTER",0,0)
minimapIcon:SetTexture("Interface\\Icons\\Spell_Nature_EarthBind")
minimapIcon:SetTexCoord(0.08,0.92,0.08,0.92)

local minimapBorder=minimapButton:CreateTexture(nil,"OVERLAY")
minimapBorder:SetWidth(53)
minimapBorder:SetHeight(53)
minimapBorder:SetPoint("TOPLEFT",minimapButton,"TOPLEFT",0,0)
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function positionMinimapButton()
  local angle=tonumber(db.minimapAngle) or 220
  local radians=math.rad(angle)
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER",Minimap,"CENTER",math.cos(radians)*80,math.sin(radians)*80)
end

local function visibilityMinimapButton()
  if db.minimapVisible==false then minimapButton:Hide() else minimapButton:Show() end
end

minimapButton:SetScript("OnClick",function() TotemCircles_ToggleOptions() end)
minimapButton:SetScript("OnEnter",function()
  GameTooltip:SetOwner(this,"ANCHOR_LEFT")
  GameTooltip:SetText("TotemCircles",1,0.82,0)
  GameTooltip:AddLine("Click to open Totem settings",1,1,1)
  GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
minimapButton:SetScript("OnDragStart",function()
  this:SetScript("OnUpdate",function()
    local mx,my=GetCursorPosition()
    local scale=UIParent:GetEffectiveScale()
    local cx,cy=Minimap:GetCenter()
    if not mx or not my or not cx or not cy then return end
    local angle=math.deg(math.atan2(my/scale-cy,mx/scale-cx))
    db.minimapAngle=angle
    positionMinimapButton()
  end)
end)
minimapButton:SetScript("OnDragStop",function() this:SetScript("OnUpdate",nil) end)

positionMinimapButton()
visibilityMinimapButton()

SLASH_TOTEMCIRCLESOPTIONS1="/tcroptions"
SLASH_TOTEMCIRCLESOPTIONS2="/tcrui"
SlashCmdList["TOTEMCIRCLESOPTIONS"]=function() TotemCircles_ToggleOptions() end

local prior=SlashCmdList["TOTEMCIRCLES"]
SlashCmdList["TOTEMCIRCLES"]=function(msg)
  local text=string.lower(msg or "")
  if text=="options" or text=="config" or text=="ui" then
    TotemCircles_ToggleOptions()
    return
  end
  if text=="minimap on" or text=="minimap off" then
    db.minimapVisible=(text=="minimap on")
    visibilityMinimapButton()
    if root:IsShown() then refreshAll() end
    return
  end
  prior(msg)
  if root:IsShown() then refreshAll() end
end
