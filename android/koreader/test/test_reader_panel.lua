-- SPDX-License-Identifier: AGPL-3.0-or-later
return function(test,eq,ok,here)
    local env=setmetatable({},{__index=_G})
    setfenv(assert(loadfile(here.."/../orbit.koplugin/logic/reader_panel.lua")),env)()
    local R=env.ReaderPanelPlan
    test("reader model: pending, empty, error and offline-without-data never invent saved progress",function()
        for _,result in ipairs({{items={},pending=true},{items={}},{items={},error="unavailable"},
            {items={},freshness={saved=false,offline=true}}}) do
            local m=R.model(result,{})
            eq(m.title,"Book info not saved yet"); eq(m.progress,nil)
            eq(m.progress_text,"Progress not saved yet")
            eq(m.battery,"Battery estimate not available yet")
            eq(m.days,"Days start to finish: not saved yet")
        end
    end)
    test("reader model: ready and offline cached rows keep companion display values",function()
        for _,offline in ipairs({false,true}) do
            local m=R.model({items={{title="Fixture",authors={"Fixture author"},progress=62,
                stats={pages_read=120,reading_seconds=3600,days_start_to_finish=3}}},freshness={saved=true,offline=offline}},
                {display={page_estimate="Learning your usual use"},hours_usual_use=999})
            eq(m.title,"Fixture"); eq(m.author,"Fixture author"); eq(m.progress,.62)
            eq(m.progress_text,"62% read"); eq(m.battery,"Learning your usual use")
            eq(m.pages,"120 pages read"); eq(m.time,"1 h 00 m"); eq(m.days,"3 days start to finish")
        end
        eq(R.model({items={{progress=200}}},{}).progress,1)
        eq(R.model({items={{progress=-1}}},{}).progress,0)
        for _,n in ipairs({0/0,math.huge,-math.huge}) do eq(R.model({items={{progress=n}}},{}).progress,nil) end
    end)
    test("reader size choices: approved M8C steps wrap in both directions",function()
        local sizes={16,18,20,22,24,27}
        for i,size in ipairs(sizes) do
            eq(R.fontSize(size,1),sizes[i%#sizes+1])
            eq(R.fontSize(size,-1),sizes[(i-2)%#sizes+1])
        end
        eq(R.fontSize(23,1),24); eq(R.fontSize(100,-1),24)
        eq(R.sizeDots(16),"●○○○○○"); eq(R.sizeDots(22),"●●●●○○"); eq(R.sizeDots(27),"●●●●●●")
    end)
    test("reader keypad: replaces leading zero, backspaces and bounds entry",function()
        eq(R.keypad("0","2"),"2");eq(R.keypad("12","back"),"1")
        eq(R.keypad("","back"),"");eq(R.keypad("123456","7"),"123456")
        eq(R.keypad("12","-"),"12");eq(R.keypad("12","42"),"12")
    end)
    test("reader segments: selection and custom value are separate display fields",function()
        local name,detail,selected=R.segment{display_text="✓ Custom · 46 px ✎"}
        eq(name,"Custom");eq(detail,"46 px");eq(selected,true)
        name,detail,selected=R.segment{text="Literary"}
        eq(name,"Literary");eq(detail,nil);eq(selected,false)
    end)
    test("book info: passes available cover, metadata and stats without creating values",function()
        local m=R.model({items={{title="Fixture",authors={"A"},cover_path="/fixture/cover.png",description="Description",
            series_line="Series · Book 2",total_pages=341,started="9 days ago",stats={reading_seconds=120}}}})
        eq(m.cover_path,"/fixture/cover.png");eq(m.description,"Description");eq(m.series_line,"Series · Book 2")
        eq(m.total_pages,341);eq(m.started,"9 days ago");eq(m.time,"2 min reading time")
        eq(R.model({items={}}).total_pages,nil)
        eq(R.model({items={{series={"Fixture series"},series_position=2}}}).series_line,"Book 2 · Fixture series")
    end)

    test("reader revision: native metadata and recorded stats populate Book info",function()
        local m=R.model({items={{series={"The Tidewright Cycle"},series_position=2,series_total=5,
            stats={started_days=9,reading_seconds=14700}}}},{display={page_estimate="Learning · estimate available after measured use"}},
            {total_pages=341,description="EPUB description"})
        eq(m.total_pages,341);eq(m.description,"EPUB description");eq(m.started,"9 days ago");eq(m.time,"4 h 05 m")
        eq(m.series_line,"Book 2 of 5 · The Tidewright Cycle");eq(m.battery_short,"Learning your usage")
    end)
    test("reader whole words: escape literal regex metacharacters and preserve ordinary search",function()
        eq(R.searchPattern("lantern",true),"\\blantern\\b")
        eq(R.searchPattern("a+b.c",true),"\\ba\\+b\\.c\\b")
        eq(R.searchPattern("a+b.c",false),"a+b.c")
    end)

end
