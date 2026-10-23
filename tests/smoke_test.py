"""Run with Python + lupa (Lua 5.1); no WoW process or saved data is touched."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / '.test-runtime'))
from lupa.lua51 import LuaRuntime
root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
unpack = unpack or table.unpack
now = os.time({year=2026,month=10,day=22,hour=12})
GetServerTime = function() return now end
date, time = os.date, os.time
strtrim = function(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
STANDARD_TEXT_FONT = 'Fonts/FRIZQT__.TTF'
SlashCmdList, UISpecialFrames, frames, timers = {}, {}, {}, {}
C_Timer = {After = function(delay, fn) timers[#timers+1]={at=now+delay,fn=fn} end}
function Advance(seconds)
    local target=now+seconds
    while true do
        local index
        for i,t in ipairs(timers) do
            if t.at<=target and (not index or t.at<timers[index].at) then index=i end
        end
        if not index then break end
        local t=table.remove(timers,index); now=t.at; t.fn()
    end
    now=target
end
wallet, warband, guildGold, player = 100000000, 50000000, 30000000, 'Tester'
GetMoney = function() return wallet end
UnitName = function() return player end
UnitGUID = function() return 'Player-' .. player end
GetRealmName = function() return 'Realm' end
IsInGuild = function() return true end
GetGuildInfo = function() return 'Test Guild',nil,nil,'Realm' end
GetGuildBankMoney = function() return guildGold end
Enum={BankType={Account=2,Guild=3}}
C_Bank={FetchDepositedMoney=function(kind) return kind==2 and warband or guildGold end,
    CanViewBank=function() return true end}
C_DateAndTime={GetWeeklyResetStartTime=function() return 1792494000 end}
local methods = {}
function methods:SetScript(event, fn) self.scripts[event]=fn end
function methods:HookScript(event,fn)
    local old=self.scripts[event]
    self.scripts[event]=function(...) if old then old(...) end;fn(...) end
end
function methods:RegisterEvent(name) self.events[name]=true end
function methods:SetSize(w,h) self.w,self.h=w,h end
function methods:SetWidth(w) self.w=w end
function methods:SetHeight(h) self.h=h end
function methods:GetWidth() return self.w or (self.parent and self.parent:GetWidth()) or 900 end
function methods:GetHeight() return self.h or 400 end
function methods:SetFont(path,size,flags) self.font,self.size,self.flags=path,size,flags end
function methods:GetFont() return self.font or STANDARD_TEXT_FONT,self.size or 12,self.flags or '' end
function methods:SetText(text) self.text=tostring(text or '') end
function methods:GetText() return self.text or '' end
function methods:GetStringHeight() return math.ceil(#self:GetText() / math.max(1, self:GetWidth()/((self.size or 12)*.55)))*(self.size or 12) end
function methods:GetFontString()
    if not self.label then self.label=self:CreateFontString() end
    return self.label
end
function methods:SetShown(value) self.shown=value==true end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown~=false end
function methods:SetChecked(value) self.checked=value end
function methods:GetChecked() return self.checked end
function methods:HasFocus() return self.focus==true end
function methods:ClearFocus() self.focus=false end
function methods:GetAlpha() return 1 end
function methods:IsEnabled() return self.enabled~=false end
function methods:SetEnabled(v) self.enabled=v end
function methods:GetParent() return self.parent end
function methods:GetPoint() return 'CENTER',UIParent,'CENTER',0,0 end
function methods:GetName() return self.name end
function methods:CreateFontString(name) return CreateFrame('FontString',name,self) end
function methods:CreateTexture(name) return CreateFrame('Texture',name,self) end
local noop=function() end
local mt={__index=function(t,key)
    if methods[key] then return methods[key] end
    if key:match('^Set') or key:match('^Enable') or key:match('^RegisterFor') or key=='ClearAllPoints' or key=='StartMoving' or key=='StopMovingOrSizing' or key=='AddLine' then return noop end
    if key:match('^[A-Z]') then error('Unmocked method: '..key) end
    return nil
end}
function CreateFrame(kind,name,parent,template)
    local f=setmetatable({kind=kind,name=name,parent=parent,scripts={},events={}},mt)
    if name then _G[name]=f end
    frames[#frames+1]=f
    return f
end
UIParent=CreateFrame('Frame');UIParent:SetSize(1920,1080)
Minimap=CreateFrame('Frame',nil,UIParent)
GameTooltip=CreateFrame('GameTooltip',nil,UIParent)
addon={}
function Event(name,...)
    for _, f in ipairs(frames) do
        if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f,name,...) end
    end
end
''')
load = lua.eval('function(source, name) local fn, err=loadstring(source,name); assert(fn,err); fn("IRS Lite",addon) end')
for line in (root/'IRS Lite.toc').read_text().splitlines():
    if line.endswith('.lua'):
        p=root/line.replace('\\','/')
        load(p.read_text(encoding='utf-8-sig'), str(p))
lua.execute(r'''
Event('ADDON_LOADED','IRS Lite')
Event('PLAYER_LOGIN')
assert(_G.IRS==nil, 'Lite must not create the full addon global')
local function eq(a,b,label) assert(a==b,(label or '')..' expected '..tostring(b)..', got '..tostring(a)) end
local function total() return addon:GetCurrentEarnings().total end
local function money(delta) wallet=wallet+delta;Event('PLAYER_MONEY') end
money(1500000); money(-500000)
eq(total(),1000000,'net income');eq(addon:GetCharacterEarnings().today,1000000)
player='Alt';Event('PLAYER_LOGIN');money(200000)
eq(total(),1200000);eq(addon:GetCharacterEarnings().total,200000)
player='Tester';Event('PLAYER_LOGIN')
addon:AdjustCurrentCharacterEarnings(-100000)
eq(total(),1100000);eq(addon:GetCurrentEarnings().today,1100000)
addon:AdjustAccountTotalEarnings(900000)
eq(total(),2000000);eq(addon:GetCurrentEarnings().today,1100000)
eq(addon:GetCharacterEarnings().total,900000)
assert(not addon:AdjustAccountTotalEarnings(math.huge))
assert(not addon:AdjustCurrentCharacterEarnings(0/0))
eq(addon:ParseAdjustment('-1.5kg'),-15000000)
eq(addon:ParseAdjustment('garbage'),nil)
eq(addon:ParseAdjustment('0'),nil)
local before=total()
-- Warband bank-first and wallet-first, both directions, plus mixed income.
Event('BANKFRAME_OPENED')
warband=warband+700000;Event('ACCOUNT_MONEY');money(-700000);eq(total(),before)
money(800000);warband=warband-800000;Event('ACCOUNT_MONEY');Advance(1.3);eq(total(),before)
money(-600000);warband=warband+500000;Event('ACCOUNT_MONEY');Advance(1.3);eq(total(),before-100000)
Event('BANKFRAME_CLOSED')
Advance(3)
-- Guild: default shared; explicit personal; deferred timeout and late reversal.
assert(not addon:IsInternalGuildBank('Test Guild@Realm'))
addon:SetInternalGuildBank('Test Guild@Realm',true)
Event('GUILDBANKFRAME_OPENED');Advance(1.1)
before=total()
guildGold=guildGold+400000;Event('GUILDBANK_UPDATE_MONEY');money(-400000);eq(total(),before)
money(300000);guildGold=guildGold-300000;Event('GUILDBANK_UPDATE_MONEY');Advance(1.3);eq(total(),before)
money(-250000);Advance(1.3);eq(total(),before-250000)
guildGold=guildGold+250000;Event('GUILDBANK_UPDATE_MONEY');eq(total(),before)
Advance(3)
-- Late matching across midnight corrects the original day's history.
local oldKeys={addon:GetPeriodKeys()}
money(-120000);Advance(1.3)
local yesterday=addon.db.tracking.days[oldKeys[1]]
now=now+86400
guildGold=guildGold+120000
-- Simulate a new calendar period within the late-match grace period, not 24h elapsed.
local recorded=addon.internalTransferRuntime.recentRecordedWallet
recorded[#recorded].recordedAt=now-2
Event('GUILDBANK_UPDATE_MONEY')
eq(addon.db.tracking.days[oldKeys[1]],yesterday+120000,'late reversal original day')
Event('GUILDBANKFRAME_CLOSED');Advance(3)
local days=addon:GetRecentDailyEarnings(7);eq(#days,7)
for i=2,7 do assert(days[i].key>days[i-1].key) end
-- Pending amounts are committed on logout, once.
Event('BANKFRAME_OPENED');before=total();money(-123000);Event('PLAYER_LOGOUT');Advance(2)
eq(total(),before-123000)
-- UI navigation, graph signs, settings/fonts, and SavedVariables reload.
SlashCmdList.IRSLITE('tools');assert(addon.toolsPage:IsShown())
SlashCmdList.IRSLITE('settings');assert(addon.settingsPage:IsShown())
addon:SelectSettingsSection('transfers');addon:RefreshSettingsPage()
addon:SetFontSize('main','body',99);eq(addon:GetFontSize('main','body'),14)
addon:SetFontFace('arial');addon:ResetFontSizes('main');eq(addon:GetFontSize('main','body'),11)
addon:ShowUI('dashboard');addon:RefreshUI()
local saved=IRSLiteDB;Event('ADDON_LOADED','IRS Lite');eq(IRSLiteDB,saved)
eq(addon.FONT_STYLE_DEFAULTS.mini,nil)
-- Stale cached guild balances cannot become matches on the next bank visit.
Event('GUILDBANKFRAME_CLOSED');Advance(3)
addon.db.guildBanks['Test Guild@Realm'].money=999999999
guildGold=22222222
local moved=addon:GetInternalTransferSummary().total
Event('GUILDBANKFRAME_OPENED');Advance(1.1)
eq(addon:GetInternalTransferSummary().total,moved,'bank opening is a baseline')
-- A guild-bank observation cannot consume a wallet change waiting on Warband storage.
Event('GUILDBANKFRAME_CLOSED');Advance(3)
Event('BANKFRAME_OPENED');money(-77000)
addon:ObserveInternalStorageDelta('guild','Test Guild@Realm',77000)
eq(#addon.internalTransferRuntime.pendingWallet,1,'matching bank identity')
warband=warband+77000;Event('ACCOUNT_MONEY');Advance(1.3)
eq(#addon.internalTransferRuntime.pendingWallet,0)
Event('BANKFRAME_CLOSED');Advance(3)
-- The chart supports negative-only, mixed, and empty periods without arithmetic errors.
local day,week,month=addon:GetPeriodKeys()
addon.db.tracking.days[day]=-100000;addon:RefreshUI()
addon.db.tracking.days[day]=0;addon:RefreshUI()
addon.db.tracking.days[day]=100000;addon:RefreshUI()
-- Calendar and game reset buckets change independently of the accumulated total.
local historicalTotal=total()
now=now+32*86400
C_DateAndTime.GetWeeklyResetStartTime=function() return 1792494000+35*86400 end
eq(addon:GetCurrentEarnings().today,0)
eq(addon:GetCurrentEarnings().week,0)
eq(addon:GetCurrentEarnings().month,0)
eq(total(),historicalTotal)
-- IRS import is manual, replaces rather than adds, and copies all supported periods.
assert(addon:GetIRSImportPreview()==nil)
local day,week,month=addon:GetPeriodKeys()
IncomeRecordsSystemDB={
    tracking={totalEarned=7654321,overallIncomeAdjustment=-10000,startedAt=123,
        days={[day]={earned=-12500,sources={goldLooted=99}}},
        weeks={[week]={earned=25000}},months={[month]={earned=50000}}},
    characters={['Player-Tester']={name='Tester',realm='Realm',earnedSinceTracking=123456,
        periodEarnings={days={[day]=-12500},weeks={[week]=20000},months={[month]=40000}}}},
    guildBanks={['Test Guild@Realm']={name='Test Guild',money=999}},
    internalTransfers={ownedGuildBanks={['Test Guild@Realm']=true},days={[day]=123},totalMoved=456,events={{amount=42}}},
    settings={showMinimapButton=false,fontFace='arial',fontSizes={main={body=13},mini={body=39}}},
    projects={items={sentinel=true}},reserves={sentinel=true},
}
local source=IncomeRecordsSystemDB
local oldTotal=total()
local preview=addon:GetIRSImportPreview()
eq(preview.characterCount,1);eq(preview.dayCount,1);eq(total(),oldTotal,'preview does not import')
local ok=addon:ImportIRSFiles();assert(ok)
eq(total(),7644321);eq(addon:GetCurrentEarnings().today,-12500)
eq(addon:GetCurrentEarnings().week,25000);eq(addon:GetCurrentEarnings().month,50000)
eq(addon:GetCharacterEarnings().total,123456);eq(addon:GetCharacterEarnings().today,-12500)
eq(addon:GetRecentDailyEarnings(7)[7].amount,-12500)
eq(addon.db.settings.fontFace,'arial');eq(addon:GetFontSize('main','body'),13)
eq(addon.db.settings.showMinimapButton,false)
eq(addon.db.internalTransfers.totalMoved,456);eq(addon.db.internalTransfers.events,nil)
eq(addon.db.projects,nil);eq(addon.db.reserves,nil)
assert(addon.db.guildBanks~=source.guildBanks)
addon.db.guildBanks['Test Guild@Realm'].money=2;eq(source.guildBanks['Test Guild@Realm'].money,999)
addon:AdjustCurrentCharacterEarnings(10000)
eq(source.tracking.totalEarned,7654321)
eq(source.characters['Player-Tester'].earnedSinceTracking,123456)
eq(source.settings.fontSizes.main.body,13) -- Original main font setting is kept intact.
local repeated=addon:ImportIRSFiles();assert(repeated);eq(total(),7644321,'repeat import replaces without doubling')
-- Invalid source history cannot partially replace Lite data.
local before=addon.db.tracking
source.characters['Player-Tester'].periodEarnings.days[day]='invalid'
assert(not addon:ImportIRSFiles());eq(addon.db.tracking,before)
source.characters['Player-Tester'].periodEarnings.days[day]=-12500
-- Import waits until pending bank events have settled.
Event('BANKFRAME_OPENED');money(-1000)
assert(not addon:ImportIRSFiles());Advance(1.3);Event('BANKFRAME_CLOSED')
-- The import buttons require explicit confirmation, and Cancel preserves history.
addon:SelectSettingsSection('import')
local importButton,confirm,cancel
for _,f in ipairs(frames) do
    if f.text=='Import IRS files' then importButton=f end
    if f.text=='REPLACE LITE HISTORY' then confirm=f end
    if f.text=='CANCEL' then cancel=f end
end
assert(importButton and confirm and cancel)
local before=total();importButton.scripts.OnClick();assert(confirm:IsShown());eq(total(),before)
cancel.scripts.OnClick();assert(not confirm:IsShown());eq(total(),before)
importButton.scripts.OnClick();confirm.scripts.OnClick();eq(total(),7644321)
IncomeRecordsSystemDB=nil
addon:RefreshUI();assert(not importButton:IsEnabled())
print('PASS: IRS preview, import, confirmation/cancel, source isolation, schema conversion, repeat import, invalid records, pending transfers')
print('PASS: load order, isolated storage, net/account/character totals, adjustments, bank event orders, partial matches, late reversal, rollover, logout, chart history, navigation, fonts, stale cache and bank identity')
''')

# Validate install assets and prevent accidentally restoring excluded feature modules.
manifest=(root/'IRS Lite.toc').read_text(encoding='utf-8-sig')
loaded=[line.replace('\\','/') for line in manifest.splitlines() if line.endswith('.lua')]
assert len(loaded)==8
assert '## OptionalDeps: IncomeRecordsSystem' in manifest
assert '## SavedVariables: IRSLiteDB' in manifest
assert set(loaded)=={str(p.relative_to(root)).replace('\\','/') for p in root.rglob('*.lua')}
for name in ['IRSButton.tga','IRSTitleIcon.tga','fonts/2002.ttf','fonts/2002b.ttf']:
    assert (root/'Media'/name).is_file(),name
for filename in loaded:
    text=(root/filename).read_text(encoding='utf-8-sig')
    for broken in ['\u00e2', '\u00c3', '\u00c2', '\ufffd']:
        assert broken not in text,(filename,'corrupted text encoding')
    for obsolete in ['ToggleMiniDashboard','GetSortedProjects','RefreshReportsPage','tokenMarket','BeginStartupTiming']:
        assert obsolete not in text,(filename,obsolete)
print('PASS: manifest, assets, and removed-feature reference audit')
