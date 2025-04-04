--  	Author: Ryan Hagelstrom
--      Please see the license file included with this distribution for
--      attribution and copyright information.
--
-- luacheck: globals ActionDamageDnDBCE BCEManager ActionDamage5EBCE ActionDamage4EBCE ActionDamage35EBCE EffectManagerBCE
-- luacheck: globals ActionDamageSFRPGBCE onInit onClose onTabletopInit setProcessEffectOnDamage applyDamageBCE getTempHPAndWounds
local RulesetEffectManager = nil;
local RulesetActionDamageManager = nil
local fProcessEffectOnDamage;

function onInit()
    RulesetEffectManager = BCEManager.getRulesetEffectManager();
    if User.getRulesetName() == '5E' then
        RulesetActionDamageManager = ActionDamage5EBCE;
    elseif User.getRulesetName() == '4E' then
        RulesetActionDamageManager = ActionDamage4EBCE;
    elseif User.getRulesetName() == '3.5E' or User.getRulesetName() == 'PFRPG' then
        RulesetActionDamageManager = ActionDamage35EBCE;
    elseif User.getRulesetName() == 'SFRPG' then
        RulesetActionDamageManager = ActionDamageSFRPGBCE;
    end

    OptionsManager.registerOption2('TEMP_IS_DAMAGE', false, 'option_Better_Combat_Effects', 'option_Temp_Is_Damage',
                                   'option_entry_cycler', {
        labels = 'option_val_off',
        values = 'off',
        baselabel = 'option_val_on',
        baseval = 'on',
        default = 'on'
    });
end

function onClose()
end

function onTabletopInit()
    EffectManagerBCE.registerEffectCompType('DMGAT', {bIgnoreDisabledCheck = true, bNoDUSE = true});
    EffectManagerBCE.registerEffectCompType('TDMGADDT', {bIgnoreOtherFilter = true});
    EffectManagerBCE.registerEffectCompType('TDMGADDS', {bIgnoreOtherFilter = true});
    EffectManagerBCE.registerEffectCompType('SDMGADDT', {bIgnoreOtherFilter = true});
    EffectManagerBCE.registerEffectCompType('SDMGADDS', {bIgnoreOtherFilter = true});
end

function setProcessEffectOnDamage(ProcessEffectOnDamage)
    fProcessEffectOnDamage = ProcessEffectOnDamage
end

-- 3.5E  function applyDamage(rSource, rTarget, bSecret, sRollType, sDamage, nTotal)
-- 4E   function applyDamage(rSource, rTarget, bSecret, sRollType, sDamage, nTotal, sFocusBaseDice)
-- 5E   function customApplyDamage(rSource, rTarget, rRoll, ...)
function applyDamageBCE(rSource, rTarget, rRoll, ...)
    BCEManager.chat('applyDamageBCE : ');
    -- Some situations can have nil source such as drag damage from chat
    if not rSource or not rTarget or not rRoll then
        return RulesetActionDamageManager.applyDamage(rSource, rTarget, rRoll, ...);
    end

    if rRoll.sType ~= 'damage' or (rRoll.sType == 'damage' and rRoll.nTotal < 0) then
        return RulesetActionDamageManager.applyDamage(rSource, rTarget, rRoll, ...);
    end
    local nodeTarget = ActorManager.getCTNode(rTarget);
    local nodeSource = ActorManager.getCTNode(rSource);
    local nodeCharTarget = ActorManager.getCreatureNode(rTarget);
    -- if User.getRulesetName() == '5E' then
        -- Get the advanced effects info we snuck on the roll from the client
        rSource.itemPath = rRoll.itemPath;
        rSource.ammoPath = rRoll.ammoPath;
    -- end
    -- save off temp hp and wounds before damage
    local nTempHPPrev, nWoundsPrev = ActionDamageDnDBCE.getTempHPAndWounds(rTarget);
    local nTotalSPPrev = 0
    local nTotalSP = 0
    if nodeCharTarget and User.getRulesetName() == 'SFRPG' then
         nTotalSPPrev = DB.getValue(nodeCharTarget, "sp.fatique", 0); -- Starfinder
    end
    RulesetActionDamageManager.applyDamage(rSource, rTarget, rRoll, ...);

    -- get temp hp and wounds after damage
    local nTempHP, nWounds = ActionDamageDnDBCE.getTempHPAndWounds(rTarget);
    if nodeCharTarget and User.getRulesetName() == 'SFRPG' then
        nTotalSP = DB.getValue(nodeCharTarget, "sp.fatique", 0); -- Starfinder
    end
    if OptionsManager.isOption('TEMP_IS_DAMAGE', 'on') then
        -- If no damage was applied then return
        if nWoundsPrev >= nWounds and nTempHPPrev <= nTempHP and nTotalSP <= nTotalSPPrev then
            return;
        end
        -- return if no damage was applied then return
    elseif nWoundsPrev >= nWounds and nTotalSP <= nTotalSPPrev then
        return;
    end

    local aTags = {'DMGAT', 'DMGDT', 'DMGRT'};
    -- We need to do the activate, deactivate and remove first as a single action in order to get the rest
    -- of the tags to be applied as expected
    for _, sTag in pairs(aTags) do
        local tMatch = RulesetEffectManager.getEffectsByType(rTarget, sTag, nil, rSource);
        for _, tEffect in pairs(tMatch) do
            if sTag == 'DMGAT' then
                BCEManager.chat('ACTIVATE: ');
                BCEManager.modifyEffect(tEffect.sEffectNode, 'Activate');
            elseif sTag == 'DMGDT' then
                BCEManager.chat('DEACTIVATE: ');
                BCEManager.modifyEffect(tEffect.sEffectNode, 'Deactivate');
            elseif sTag == 'DMGRT' then
                BCEManager.chat('REMOVE: ');
                BCEManager.modifyEffect(tEffect.sEffectNode, 'Remove');
            end
        end
    end
    if (fProcessEffectOnDamage) then
        fProcessEffectOnDamage(rSource, rTarget, rRoll, ...);
    end

    aTags = {'TDMGADDT', 'TDMGADDS'};
    for _, sTag in pairs(aTags) do
        local tMatch = RulesetEffectManager.getEffectsByType(rTarget, sTag, nil, rSource);
        for _, tEffect in pairs(tMatch) do
            if sTag == 'TDMGADDT' then
                BCEManager.chat('TDMGADDT: ');
                for _,remainder in pairs(tEffect.remainder) do
                    BCEManager.notifyAddEffect(nodeTarget, nodeTarget, remainder);
                end
            elseif sTag == 'TDMGADDS' then
                BCEManager.chat('TDMGADDS: ');
                for _,remainder in pairs(tEffect.remainder) do
                    BCEManager.notifyAddEffect(nodeSource, nodeTarget, remainder);
                end
            end
        end
    end
    aTags = {'SDMGADDT', 'SDMGADDS'};
    for _, sTag in pairs(aTags) do
        local tMatch = RulesetEffectManager.getEffectsByType(rSource, sTag, nil, rTarget);
        for _, tEffect in pairs(tMatch) do
            if sTag == 'SDMGADDT' then
                BCEManager.chat('SDMGADDT: ');
                for _,remainder in pairs(tEffect.remainder) do
                    BCEManager.notifyAddEffect(nodeTarget, nodeSource, remainder);
                end
            elseif sTag == 'SDMGADDS' then
                BCEManager.chat('SDMGADDS: ');
                for _,remainder in pairs(tEffect.remainder) do
                    BCEManager.notifyAddEffect(nodeSource, nodeSource, remainder);
                end
            end
        end
    end
end

function getTempHPAndWounds(rTarget)
    BCEManager.chat('getTempHPAndWounds : ');
    local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget);
    local nTempHP = 0;
    local nWounds = 0;

    if not nodeTarget then
        return nTempHP, nWounds;
    end

    if sTargetNodeType == 'pc' then
        nTempHP = DB.getValue(nodeTarget, 'hp.temporary', 0);
        nWounds = DB.getValue(nodeTarget, 'hp.wounds', 0);
    elseif sTargetNodeType == 'ct' or sTargetNodeType == 'npc' then
        nTempHP = DB.getValue(nodeTarget, 'hptemp', 0);
        nWounds = DB.getValue(nodeTarget, 'wounds', 0);
    end
    return nTempHP, nWounds;
end
