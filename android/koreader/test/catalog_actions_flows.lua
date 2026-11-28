-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(t)
local E,W,test,eq,ok=t.E,t.W,t.test,t.eq,t.ok
    test('End of book: pace requires measured pages and time',function()
        for _,stats in ipairs({{}, {available=false,pages_read=0,reading_seconds=3600}, {pages_read=0,reading_seconds=3600}, {pages_read=12,reading_seconds=0}}) do
            eq(E.CatalogUI.readingPace(stats),'—')
        end
        eq(E.CatalogUI.readingPace{available=true,pages_read=45,reading_seconds=1800},'90 pp/h')
    end)
local function isolated(fn)
    local action,native,position,reading=E.Library.catalogAction,E.Library.nativeReader,E.Library.finishCurrent,E.reading
    E.Library.finishCurrent=function(done) done(true) end
    local oldsheet=E.FinishUI.sheet
    E.FinishUI.sheet=nil
    local success,why=pcall(fn)
    E.FinishUI.closeSheet();E.FinishUI.sheet=oldsheet
    E.Library.catalogAction,E.Library.nativeReader,E.Library.finishCurrent,E.reading=action,native,position,reading
    if not success then error(why) end
end
local function fixture()
    local ui,m=t.newUI(true)
    ui.doc_settings={readSetting=function(self,k) return self[k] end,saveSetting=function(self,k,v) self[k]=v end}
    local b={digest=string.rep("a",32),file="/books/synthetic.epub",key=true,summary={},doc_settings=ui.doc_settings}
    E.Library.nativeReader=function() return b end
    return ui,m,b
end
test("catalog actions: mark, rate, undo and leave dispatch neutral commands",function() isolated(function()
    local ui,m,b=fixture();local calls={}
    E.Library.catalogAction=function(op,args,done) calls[#calls+1]={op,args};if done then done({ok=true}) end end
    b.summary.status="complete";E.FinishUI.onMarked(ui)
    eq(calls[1][1],"finish.mark");eq(calls[1][2].complete,true);eq(calls[1][2].path,b.file)
    ok(calls[1][2].server==nil and calls[1][2].userkey==nil)
    E.FinishUI.actions.star(ui,b,4);eq(calls[2][1],"finish.rate");eq(calls[2][2].rating,4)
    E.FinishUI.actions.star(ui,b,4);eq(calls[3][2].rating,nil)
    E.FinishUI.onLeave(ui);eq(calls[4][1],"finish.leave")
    b.summary.status="reading";E.FinishUI.onMarked(ui);eq(calls[5][2].complete,false)
end) end)
test("catalog actions: automatic refresh requires the neutral capability",function()
    local snapshot,command=E.LibraryAdapter.account_snapshot,E.LibraryAdapter.command
    local success,why=pcall(function()
        E.LibraryAdapter.account_snapshot={catalog={canRefresh=false}}
        E.LibraryAdapter.command=function() error("refresh without capability") end
        eq(E.Library.refreshCatalog("resume",false),false)
        E.LibraryAdapter.account_snapshot={catalog={}}
        eq(E.Library.refreshCatalog("incremental",false),false)
    end)
    E.LibraryAdapter.account_snapshot,E.LibraryAdapter.command=snapshot,command
    if not success then error(why) end
end)
test("catalog actions: unmarked reader leave needs no companion command",function() isolated(function()
    local ui,m,b=fixture();E.FinishUI.jobs[b.digest]=nil
    E.Library.catalogAction=function() error("unnecessary leave command") end
    E.FinishUI.onLeave(ui)
end) end)
test("catalog actions: finish snapshot paint is bounded and contains no catalog algorithms",function() isolated(function()
    local ui,m,b=fixture();local adapter=E.LibraryAdapter;local requests={}
    E.LibraryAdapter={read=function(raw)
        local args=E.Cache.decode(raw)
        if args.op=="reader" then eq(args.limit,1);return {items={{cover_path="saved-cover.png",stats={pages_read=341}}}},100 end
        eq(args.op,"reader.finish");eq(args.limit,3)
        return {title="Synthetic",status="Saved",row_count=3,next={book_id="opaque-next",local_path="next.epub"},suggestion={book_id="opaque-suggestion"}},300
    end,request=function(batch) requests[#requests+1]=batch;return true end}
    local success,why=pcall(function()
        local model=E.FinishUI.model(b);eq(model.title,"Synthetic");eq(#requests,1);eq(#requests[1],3);eq(model.book.cover_path,"saved-cover.png");eq(model.next.book.cover_path,"saved-cover.png");eq(model.stats.pages_read,341)
    end)
    E.LibraryAdapter=adapter;if not success then error(why) end
end) end)
test("catalog actions: closing a pending finish sheet cancels polling and stale callbacks stay inert",function() isolated(function()
    local model=E.FinishUI.model;local calls=0
    E.FinishUI.model=function() calls=calls+1;error("closed sheet must not request data") end
    local sheet={model={pending=true}};E.FinishUI.sheet=sheet
    E.FinishUI.pollSheet(sheet);local pending=E.FinishUI.sheet_retry;ok(pending)
    E.FinishUI.closeSheet();eq(E.FinishUI.sheet_retry,nil)
    pending();eq(calls,0);eq(E.FinishUI.sheet,nil)
    E.FinishUI.model=model
end) end)
test("catalog actions: queued copies dispatch once outside reading with open path protection",function() isolated(function()
    local ui,m,b=fixture();local calls={};local enabled=E.S.keep_copies_current
    E.S.keep_copies_current=true;E.Library.copies_at=nil;E.Library.copies_pending=nil
    E.Library.catalogAction=function(op,args,done) calls[#calls+1]={op,args};done({ok=true});return true end
    E.reading=function() return true end;E.Library.copiesTick("full refresh");eq(#calls,0)
    E.reading=function() return false end;E.Library.copiesTick("full refresh");eq(#calls,1)
    eq(calls[1][1],"copies.check");eq(calls[1][2].open_path,ui.document.file)
    E.Library.copiesTick("background");eq(#calls,1)
    E.S.keep_copies_current=false;E.Library.copiesTick("full refresh");eq(#calls,1)
    E.S.keep_copies_current=enabled
end) end)

test("catalog actions: failed or departed download never reopens a book",function() isolated(function()
    local ui,m,b=fixture();local pending;local opened=0;local open=E.Library.open
    E.Library.open=function() opened=opened+1 end
    E.Library.catalogAction=function(op,args,done) pending=done;return true end
    local sheet={ui=ui,book=b,update=function() end};E.FinishUI.sheet=sheet
    E.FinishUI.actions.book(ui,b,"opaque","Synthetic")
    E.FinishUI.sheet=nil;pending({local_path="/books/next.epub"});eq(opened,0)
    E.Library.open=open
end) end)
test("catalog actions: recommendation observation unwraps the saved native value and checks compatibility",function()
    local ui,m=t.newUI(false);local p=ui.bookorbit
    local saved,mode=E.S.osm_saved_plugin,E.S.sync_mode
    p.default_settings={sync_forward=1}
    local retirement=E.NativeRetirement
    E.NativeRetirement={plan={settings_key="fixture-connector",preference_overlay={record="osm_saved_plugin",guard={sync_forward=3,sync_backward=3},keys={"sync_forward","sync_backward","auto_sync"}}},defaults=p.default_settings}
    E.G_reader_settings:saveSetting("fixture-connector",p.settings)
    E.S.osm_saved_plugin={sync_forward=3};E.S.sync_mode="balanced"
    p.settings.sync_forward,p.settings.sync_backward=3,3
    local success,why=pcall(function()
        local obs=E.Library.observeSetting({key="sync_forward"});eq(obs.available,true);eq(obs.current,3)
        E.S.sync_mode="custom";E.S.osm_saved_plugin.sync_forward=2
        eq(E.Library.observeSetting({key="sync_forward"}).current,2)
        ok(E.Library.writeSetting({key="sync_forward"},1));eq(E.S.osm_saved_plugin.sync_forward,1);eq(p.settings.sync_forward,3)
        E.NativeRetirement.defaults=nil;eq(E.Library.observeSetting({key="sync_forward"}).available,false)
    end)
    E.NativeRetirement=retirement
    E.S.osm_saved_plugin,E.S.sync_mode=saved,mode
    if not success then error(why) end
end)
test("catalog actions: finish follows the owned writer even with pending closed-sidecar work",function()
    local run,action=E.ReadingSync.run,E.Library.catalogAction;local order={}
    E.ReadingSync.run=function(moment,done) eq(moment,"manual");order[#order+1]="owned-writer";done(false,nil) end
    E.Library.catalogAction=function(op,args,done) order[#order+1]=op;done({ok=true}) end
    local success,why=pcall(function()
        local done
        E.LibraryAdapter.finishCurrent(function(ok) done=ok end)
        eq(done,true);eq(order[1],"owned-writer");eq(order[2],"finish.drain")
        E.ReadingSync.run=function(_,cb) cb(false,"offline") end
        E.LibraryAdapter.finishCurrent(function(ok) eq(ok,false) end);eq(#order,2)
    end)
    E.ReadingSync.run,E.Library.catalogAction=run,action
    if not success then error(why) end
end)

test("catalog actions: leaving for Home schedules the existing writer after its paint",function() isolated(function()
    local ui,m,b=fixture();local nextTick=t.UIManager.nextTick;local scheduled;local calls=0
    E.FinishUI.jobs[b.digest]={};E.FinishUI.sending=nil
    E.Library.catalogAction=function() end
    E.Library.finishCurrent=function(done) calls=calls+1;done(true) end
    t.UIManager.nextTick=function(_,fn) scheduled=fn end
    local success,why=pcall(function()
        E.FinishUI.leaveForHome(ui);eq(calls,0);ok(scheduled);scheduled();eq(calls,1)
    end)
    t.UIManager.nextTick=nextTick;E.FinishUI.sending=nil
    if not success then error(why) end
end) end)
test("catalog actions: finish leaves and drains the existing writer before a remote download",function() isolated(function()
    local ui,m,b=fixture();local order={}
    E.Library.catalogAction=function(op,args,done) order[#order+1]=op;if done then done({error="offline"}) end end
    E.Library.finishCurrent=function(done) order[#order+1]="existing-writer";done(true) end
    E.FinishUI.sheet={ui=ui,book=b,update=function() end}
    E.FinishUI.actions.book(ui,b,"opaque","Synthetic")
    eq(order[1],"finish.leave");eq(order[2],"existing-writer");eq(order[3],"finish.download")
end) end)
test("catalog actions: a saved next book opens offline without a network command",function() isolated(function()
    local ui,m,b=fixture();local opened;local open=E.Library.open
    E.Library.open=function(row) opened=row.local_path;return true end
    E.Library.finishCurrent=function() error("local book requested sync") end
    E.Library.catalogAction=function(op) eq(op,"finish.leave") end
    E.FinishUI.actions.book(ui,b,"opaque","Synthetic","/books/local.epub")
    eq(opened,"/books/local.epub");E.Library.open=open
end) end)

test("catalog actions: end sheet uses only the library action dispatcher",function() isolated(function()
    local ui,m,b=fixture();local endAction=E.Library.endAction;local calls={}
    E.Library.endAction=function(name) calls[#calls+1]=name end
    local sheet=E.EndSheet:new{ui=ui,book=b,model={title="Synthetic",status="Saved",can_mark=true}}
    for _,row in ipairs(sheet:rows()) do if row.kind=="status" then row.action() end end
    eq(calls[1],"mark");sheet:onClose();eq(calls[2],"back")
    E.Library.endAction=endAction
end) end)
test("catalog actions: series action appears only for companion-projected membership",function() isolated(function()
    local ui,m,b=fixture();local action=E.Library.endAction;local calls={}
    E.Library.endAction=function(...) calls[#calls+1]={...} end
    local success,why=pcall(function()
        for _,model in ipairs({
            {series_key="opaque-series",next={line="Next in series",book_id="next",title="Next"}},
            {series_key="opaque-series",next={line="You've finished the series"}},
            {},
            {series_key="opaque-series",offline=true,next={line="Next in series",book_id="next",title="Saved",local_path="saved.epub"}},
        }) do
            model.title,model.status="Synthetic","Saved"
            local sheet=E.EndSheet:new{ui=ui,book=b,model=model};local found=0
            for _,row in ipairs(sheet:rows()) do
                if row.text=="View series" then
                    found=found+1;row.action()
                    local call=calls[#calls];eq(call[1],"series");eq(call[2],ui);eq(call[3],b);eq(call[4],model.series_key)
                end
            end
            eq(found,model.series_key and 1 or 0)
        end
    end)
    E.Library.endAction=action;if not success then error(why) end
end) end)
test("catalog actions: failed series entry restores sheet and stale Back cannot reopen it",function() isolated(function()
    local ui,m,b=fixture();local show,model=E.SeriesUI.show,E.FinishUI.model;local restore
    E.FinishUI.model=function() return {title="Synthetic",status="Saved"} end
    local success,why=pcall(function()
        E.SeriesUI.show=function() return false end
        eq(E.Library.endAction("series",ui,b,"opaque"),false);ok(E.FinishUI.sheet)
        E.SeriesUI.show=function(key,back) eq(key,"opaque");restore=back;return true end
        ok(E.Library.endAction("series",ui,b,"opaque"));eq(E.FinishUI.sheet,nil)
        ui.document={file="other.epub"};restore();eq(E.FinishUI.sheet,nil)
    end)
    E.SeriesUI.show,E.FinishUI.model=show,model;if not success then error(why) end
end) end)
test("catalog actions: every added screen and widget has strict deterministic budgets",function()
    for _,id in ipairs({"end-of-book","settings-recommendations","copies-state"}) do
        local b=E.Budgets.get("screens",id);eq(b.network,0);eq(b.spawns,0);ok(b.roundTrips<=1);ok(b.snapshotBytes<=16384)
        ok(not E.Budgets.check(b,{rows=b.rows+1,bytes=0,spawns=0,roundTrips=0,network=0,snapshotBytes=0}))
    end
    for _,id in ipairs({"end-of-book","recommendations"}) do E.Budgets.get("widgets",id) end
end)
local function recommendationPass(case)
    local saved={recommendations=E.Recommendations,call=E.Library.recommendations,menus=E.Library.setReaderMenus,live=E.liveUI,
        record=E.S.recommended,backup=E.S.recommended_backup,clean=E.S.clean_menus,save=E.saveSettings,silent=E.silentWifiOn,report=E.Library.report.send}
    local state={calls=0,writes=0,saves=0,flushes=0}
    local default={toggle_page_flipping=true}
    local ui={gestures={default_settings={data={gesture_reader={tap_top_left_corner=default}}},data={gesture_reader={tap_top_left_corner=default}}}}
    ui.gestures.onFlushSettings=function() ok(E.S.recommended_backup);state.flushes=state.flushes+1 end
    local definitions={{id="g.no_flip",kind="gesture",key="tap_top_left_corner",ours={}},{id="o.clean_menus",kind="owned",key="clean_menus",ours=true,untouched_only=true}}
    E.liveUI=function() return ui end;E.S.recommended=nil;E.S.recommended_backup=nil;E.S.clean_menus=case=="undo" and true or nil
    E.saveSettings=function() state.saves=state.saves+1 end
    E.Library.setReaderMenus=function(_,value) ok(E.S.recommended_backup,"backup precedes native mutation");E.S.clean_menus=value;state.writes=state.writes+1 end
    E.Library.report.send=function() end
    local filename=(arg[0]:match("^(.*)/") or ".").."/../orbit.koplugin/ko/recommendations_backend.lua"
    local fn=assert(loadfile(filename));setfenv(fn,E);fn()
    E.Library.recommendations=function(args,done)
        state.calls=state.calls+1;ok(E.Recommendations.pending)
        if args.definitions then done({items=definitions});return end
        if args.ack then
            state.failed=args.failed
            done({items={},record=args.record,backup=args.backup});return
        end
        eq(args.observations["g.no_flip"].available,true)
        local writes={}
        if case=="defaults" or case=="race" then
            writes={{id="g.no_flip",expected=default,value={}},{id="o.clean_menus",value=true,guard_untouched=true}}
        elseif case=="explicit" then
            ui.gestures.data.gesture_reader.tap_top_left_corner={custom=true}
            writes={{id="o.clean_menus",value=true,guard_untouched=false}}
        else writes={{id="o.clean_menus",expected=true,value=nil}} end
        if case=="race" then ui.gestures.data.gesture_reader.tap_top_left_corner={custom=true} end
        done({writes=writes,record={items={["g.no_flip"]="applied",["o.clean_menus"]="applied"},unseen=2},
            backup={["g.no_flip"]={prior=default,ours={}},["o.clean_menus"]={ours=true}}})
    end
    local success,why=pcall(function()
        E.Recommendations.pass("test",nil,false,function() state.done=true end)
        eq(state.calls,3,"definitions lead to evaluation and acknowledgement");ok(state.done);eq(E.Recommendations.pending,nil)
        if case=="race" then eq(state.writes,0);eq(E.S.clean_menus,nil);eq(#state.failed,2);ok(ui.gestures.data.gesture_reader.tap_top_left_corner.custom)
        elseif case=="undo" then eq(state.writes,1);eq(E.S.clean_menus,nil)
        else eq(state.writes,1);eq(E.S.clean_menus,true);eq(#state.failed,0)
            if case=="defaults" then eq(next(ui.gestures.data.gesture_reader.tap_top_left_corner),nil);eq(state.flushes,1) end
        end
    end)
    E.Recommendations,E.Library.recommendations,E.Library.setReaderMenus,E.liveUI=saved.recommendations,saved.call,saved.menus,saved.live
    E.S.recommended,E.S.recommended_backup,E.S.clean_menus=saved.record,saved.backup,saved.clean
    E.saveSettings,E.silentWifiOn,E.Library.report.send=saved.save,saved.silent,saved.report
    if not success then error(why) end
end
test("recommendations: first definition fetch applies and acknowledges without a pending deadlock",function() recommendationPass("defaults") end)
test("recommendations: an intervening customized gesture defeats automatic menu takeover",function() recommendationPass("race") end)
test("recommendations: explicit menu opt-in works on a customized reader",function() recommendationPass("explicit") end)
test("recommendations: Undo restores the absent owned setting",function() recommendationPass("undo") end)

end
