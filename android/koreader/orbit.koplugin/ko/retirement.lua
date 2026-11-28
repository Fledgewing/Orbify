-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Local migration metadata only. Retire complete legacy classes before instance startup;
-- no original method is invoked, and a late/missing handshake never activates our writer.
NativeRetirement={}
SyncRetirement={safe=false}
local result=Library.bootstrap()
if result and result.ok=="1" and type(result.body)=="string" and #result.body<=16384 then
    local plan=Cache.decode(result.body)
    if type(plan)=="table" and type(plan.plugins)=="table" and #plan.plugins<=4 and type(plan.modules)=="table" and #plan.modules<=8 then
        NativeRetirement.plan=plan
        HomePlan.SERVER_HOME=plan.home_key or HomePlan.SERVER_HOME
        local function retired() return nil,"companion_owned" end
        local function disable(target)
            if type(target)~="table" then return end
            local function callable(value)
                local mt=type(value)=="table" and getmetatable(value)
                return type(value)=="function" or type(mt)=="table" and type(mt.__call)=="function"
            end
            for name,value in pairs(target) do
                if callable(value) then target[name]=retired end
            end
            -- Widget:new invokes both _init and init; events may also be inherited.
            -- Shadow lifecycle entries on this class only, never mutate a shared base.
            local seen={}
            local base=getmetatable(target)
            while type(base)=="table" and not seen[base] do
                seen[base]=true
                for name,value in pairs(base) do
                    if type(name)=="string" and (name:sub(1,2)=="on" or name=="_init" or name=="init" or name=="stopPlugin") and callable(value) then
                        target[name]=retired
                    end
                end
                local mt=getmetatable(base)
                base=type(mt)=="table" and (rawget(mt,"__index") or mt) or nil
            end
        end
        local function disarm(plugin)
            for _,id in ipairs(plan.plugins) do
                if plugin and plugin.name==id then
                    NativeRetirement.defaults=plugin.default_settings
                    disable(plugin)
                    -- Even a plugin-defined constructor must never run. The loader only
                    -- needs an inert instance carrying its ui/name and shadowed handlers.
                    plugin.new=function(class,attributes)
                        return setmetatable(attributes or {},{__index=class})
                    end
                end
            end
            for _,id in ipairs(plan.modules) do disable(package.loaded[id]) end
        end
        local late=false
        for _,id in ipairs(plan.plugins) do if PluginLoader.loaded_plugins and PluginLoader.loaded_plugins[id] then late=true end end
        for _,plugin in ipairs(PluginLoader.enabled_plugins or {}) do disarm(plugin) end
        if type(PluginLoader.createPluginInstance)=="function" then
            local stock=PluginLoader.createPluginInstance
            function PluginLoader:createPluginInstance(plugin,...)
                disarm(plugin)
                return stock(self,plugin,...)
            end
            SyncRetirement.safe=not late
        end
    end
end
