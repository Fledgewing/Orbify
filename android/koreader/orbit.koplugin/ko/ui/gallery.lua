-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Explicit developer gallery: callers own showing/closing it and the reading gate.
function BookSyncUI.gallery()
    local w,h=Device.screen:getWidth(),Device.screen:getHeight()
    local K=BookSyncUI.new();local p=K.px
    local c=K.canvas(w,h)
    K.label(c,"BookSync UI kit",p(20),p(20),w-p(40),"heading",{serif=true,bold=true})
    K.label(c,"Native widgets · shared Home tokens",p(20),p(64),w-p(40),"small",{muted=true})
    local card=K.card{w=w-p(40),h=p(186),title="Continue reading",ink=true}
    K.put(card.content,K.cover{w=p(76),title="Seedfall",author="A. Vale"},p(16),p(48))
    K.label(card.content,"Seedfall",p(112),p(50),p(460),"title",{serif=true,bold=true,ink=true})
    K.label(card.content,"A. Vale · The Glass Orchard #1",p(112),p(88),p(460),"small",{ink=true})
    K.put(card.content,K.progress{w=p(350),value=.38,ink=true},p(112),p(120))
    K.put(card.content,K.button{text="Resume",icon="play",w=p(200),h=p(42),variant="inverted"},p(112),p(138))
    K.put(c,card,p(20),p(106))
    K.put(c,K.search{count=2418,w=p(220)},p(20),p(312))
    K.put(c,K.button{text="Sync now",w=p(160)},p(260),p(312))
    K.put(c,K.button{text="Unavailable",w=p(220),enabled=false},p(440),p(312))
    for i,item in ipairs({{"book.opened","Books"},{"appbar.search","Search"},{"appbar.settings","Settings"}}) do
        K.put(c,K.iconTile{w=p(100),icon=item[1],text=item[2]},p(20+(i-1)*120),p(390))
    end
    K.put(c,K.toggle{value=true},p(460),p(396));K.put(c,K.toggle{value=false},p(550),p(396))
    K.put(c,K.segments{w=p(640),items={"Cover","List","Compact"},selected=2},p(20),p(502))
    K.put(c,K.slider{w=p(620),value=.4,text="Frontlight"},p(30),p(574))
    local shelf=K.card{w=p(640),h=p(112),title="Lists",count=3,all=function() end}
    K.put(shelf.content,K.row{w=p(608),text="Short reads",icon="feather",count=84},p(16),p(40))
    K.put(c,shelf,p(20),p(654))
    K.label(c,"32 px body · 50 px title · 2 px rules · 32 px radius",p(20),p(800),p(650),"body")
    local Input=require("ui/widget/container/inputcontainer"):extend{name="booksync_ui_kit_gallery",covers_fullscreen=true}
    local widget=Input:new{dimen=require("ui/geometry"):new{w=w,h=h},K.frame(c,{w=w,h=h})}
    return widget,K
end
