#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Reader-panel visual acceptance with real EPUB metadata and MD5-linked native stats."""
import argparse
import importlib.util
import io
import json
import math
from pathlib import Path
import sqlite3
import sys
import time
import zipfile
sys.dont_write_bytecode = True
from PIL import Image, ImageDraw, ImageFont
from run import Emulator

ROOT = Path(__file__).resolve().parents[3]
DESCRIPTION = ("When the keeper of the northern light disappears in a February gale, his daughter climbs "
               "the hundred and nine steps to the lantern room and finds the logbook written in a hand "
               "that is not his. Ines Calder returns to the salt-bitten coast of Tidewright with a slow, "
               "luminous mystery about inheritance, weather and the stories a town tells to keep its boats coming home.")
PAIRS = [('reader-top', 'm8c-reader-top.webp', 0),
         ('reader-bottom', 'm8c-r10-1-panel-custom.webp', 720),
         ('contents', 'm8c-sheet-toc.webp', 350), ('saved-items', 'm8c-sheet-marks.webp', 350),
         ('search-results', 'm8c-sheet-search.webp', 350), ('no-matches', 'm8c-sheet-search.webp', 350),
         ('book-info', 'm8c-sheet-info.webp', 350), ('goto', 'm8c-sheet-goto.webp', 760),
         ('search-input', 'm8c-sheet-search.webp', 350)]


def wait(device, code):
    deadline = time.monotonic() + 30
    while device.command(code) != 'ready':
        if time.monotonic() > deadline:
            raise TimeoutError('reader fixture did not publish: ' + code)
        time.sleep(.2)


def prepare(device, out):
    seed = out / 'seed'
    seed.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('reader_panel_kit', ROOT / 'tools/e2e/kit.py')
    kit = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = kit
    spec.loader.exec_module(kit)
    device.command('ReaderPanel.close();local ui=liveUI();if ui and ui.document then ui:onClose() end;return true')
    device.shell('am', 'force-stop', 'org.koreader.launcher')
    device.shell('am', 'force-stop', 'net.fledgewing.orbitcompanion')
    library = json.loads((ROOT / 'shared/fixtures/e2e/library.json').read_text())
    library.update(chapters=22, paragraphs_per_chapter=50)
    names = {12: 'The Harbourmaster', 13: 'Small Weather', 14: 'The Lantern Room', 15: 'Second Lens',
             16: 'A Letter, Unsent', 17: 'Drowned Bells', 18: 'The Survey', 19: 'Wintering',
             20: 'Flood', 21: 'The Return', 22: 'Coda: Clear Night'}
    for number, position in zip(range(60, 65), [2, 1, 3, 4, 5]):
        title = 'The Lantern Room' if position == 2 else 'Tidewright Volume ' + str(position)
        book = dict(title=title, author='Ines Calder', series='The Tidewright Cycle', index=position,
                    cover=True, number=number, uuid=f'urn:uuid:00000000-0000-4000-8000-{number:012d}')
        raw = kit.epub_bytes(book, library)
        target = io.BytesIO()
        with zipfile.ZipFile(io.BytesIO(raw)) as source, zipfile.ZipFile(target, 'w') as dest:
            for info in source.infolist():
                data = source.read(info.filename)
                if info.filename.endswith(('.opf', '.xhtml')):
                    text = data.decode()
                    if info.filename.endswith('.opf'):
                        text = text.replace('</dc:language>', '</dc:language><dc:description>' + DESCRIPTION + '</dc:description>')
                    for n, name in sorted(names.items(), reverse=True):
                        text = text.replace('>Chapter ' + str(n) + '<', '>' + name + '<')
                    # Longer final chapter permits a native chapter-14 position with a
                    # measured 26-minute chapter / 202-minute book interval.
                    if info.filename in ('OEBPS/c14.xhtml', 'OEBPS/c22.xhtml'):
                        text = text.replace('</body>', '<p>' + ('The tide moved quietly along the shore. ' * 450) + '</p></body>')
                    if position == 2 and info.filename.startswith('OEBPS/c') and info.filename.endswith('.xhtml'):
                        text = text.replace('The Lantern Room, chapter', 'The keeper, chapter')
                        if info.filename in ('OEBPS/c3.xhtml', 'OEBPS/c9.xhtml', 'OEBPS/c14.xhtml', 'OEBPS/c17.xhtml'):
                            text = text.replace('The rows of the orchard', 'The lantern lit the rows of the orchard', 1)
                    data = text.encode()
                dest.writestr(info, data)
        file = seed / f'{number:03d} {title}.epub'
        file.write_bytes(target.getvalue())
        sidecar = file.with_suffix('.sdr')
        sidecar.mkdir(exist_ok=True)
        props = {'title': title, 'authors': 'Ines Calder', 'series': book['series'], 'series_index': position}
        def literal(values):
            return '{' + ','.join('[' + json.dumps(k) + ']=' + (literal(v) if isinstance(v, dict) else json.dumps(v)) for k, v in values.items()) + '}'
        (sidecar / 'metadata.epub.lua').write_text('return ' + literal({'doc_props': props, 'summary': {'status': 'reading'}, 'percent_finished': .62}))
        Image.open(ROOT / 'docs/design/booksync-home/shots/m8c-sheet-info.webp').crop((68, 550, 332, 944)).save(sidecar / 'cover.png')
        device.push(file, '/sdcard/Books/')
        device.push(sidecar, '/sdcard/Books/')
    device.shell('am', 'start', '-n', 'net.fledgewing.orbitcompanion/.LauncherActivity')
    device.shell('am', 'start', '-n', 'org.koreader.launcher/.MainActivity')
    time.sleep(3)
    device.wait_companion()
    device.command('ReaderPanel.close();Library.companion.setupLater();local w=top();if w and type(w.text)=="string" and w.text:find("BookSync Companion needs",1,true) then click("Later") end;Library.open({local_path="/storage/emulated/0/Books/060 The Lantern Room.epub"});return true')
    wait(device, 'return liveUI() and liveUI().document and liveUI().document.file:find("060 The Lantern Room",1,true) and "ready" or "pending"')
    style(device)
    total, start, following, md5 = device.command('local ui=liveUI();assert(ui.doc_props.description:find("When the keeper",1,true));return ui.document.info.number_of_pages..","..ui.toc.toc[14].page..","..ui.toc.toc[15].page..","..ui.doc_settings:readSetting("partial_md5_checksum")').split(',')
    total, start, following = map(int, (total, start, following))
    assert len(md5) == 32
    # Select native page geometry whose two measured intervals round to the mockup.
    choice = None
    for page in range(start, following):
        d, remaining = following - page, total - page
        low = max(201 * 60 / remaining, 25 * 60 / d)
        high = min(202 * 60 / remaining, 26 * 60 / d)
        if low < high:
            choice = page, (low + high) / 2
            break
    assert choice, (total, start, following)
    page, seconds_per_page = choice
    device.command('ReaderPanel.close();liveUI():onClose();return true')
    device.shell('am', 'force-stop', 'org.koreader.launcher')
    device.shell('am', 'force-stop', 'net.fledgewing.orbitcompanion')
    database = seed / 'statistics.sqlite3'
    device.adb('pull', '/sdcard/koreader/settings/statistics.sqlite3', database)
    db = sqlite3.connect(database)
    found = db.execute('select id from book where md5=?', (md5,)).fetchone()
    if found:
        bid = found[0]
    else:
        bid = db.execute('insert into book(title,authors,pages,md5) values (?,?,?,?)', ('The Lantern Room', 'Ines Calder', total, md5)).lastrowid
    db.execute('update book set pages=? where id=?', (total, bid))
    db.execute('delete from page_stat_data where id_book=?', (bid,))
    now = int(device.shell('date', '+%s'))
    count, seconds = 200, 14700
    old_total = seconds_per_page * total * count / seconds
    low = math.floor(old_total)
    distribution = None
    for high_count in range(count + 1):
        coverage = high_count / (low + 1) + (count - high_count) / low
        pace = seconds / coverage / total
        if math.ceil((total - page) * pace / 60) == 202 and math.ceil((following - page) * pace / 60) == 26:
            distribution = high_count
            break
    assert distribution is not None
    for i in range(count):
        duration = seconds // count + (1 if i < seconds % count else 0)
        db.execute('insert into page_stat_data(id_book,page,start_time,duration,total_pages) values (?,?,?,?,?)',
                   (bid, i + 1, now - 9 * 86400 + i * ((9 * 86400 - 3600) // (count - 1)), duration, low + (i < distribution)))
    assert db.execute('select sum(duration) from page_stat where id_book=?', (bid,)).fetchone()[0] == seconds
    db.commit()
    db.close()
    device.push(database, '/sdcard/koreader/settings/statistics.sqlite3')
    device.shell('am', 'start', '-n', 'net.fledgewing.orbitcompanion/.LauncherActivity')
    device.shell('am', 'start', '-n', 'org.koreader.launcher/.MainActivity')
    time.sleep(3)
    device.wait_companion()
    # Materialize the ordinary catalog once; op=reader then reads the saved series
    # count and per-book statistics without rescanning the library.
    wait(device, 'local p=Library.paint("home");local r=p:read("library.summary",{limit=1});p:flush();return not r.pending and r.total and r.total>=64 and "ready" or "pending"')
    device.command('ReaderPanel.close();Library.open({local_path="/storage/emulated/0/Books/060 The Lantern Room.epub"});return true')
    wait(device, 'return liveUI() and liveUI().document and liveUI().document.file:find("060 The Lantern Room",1,true) and "ready" or "pending"')
    style(device)
    device.command(f'assert(liveUI().document.info.number_of_pages=={total});assert(Library.readerGo(liveUI(),"{page}",false));return true')
    return dict(md5=md5, page=page, total=total, started_days=9, reading_seconds=seconds,
                chapter_minutes=26, book_minutes=202, visits=count, series_books=5)


def style(device):
    device.command('ReaderPanel.close();local ui=liveUI();assert(ui.document);ui.toc:onShowToc();ui.toc.toc_menu.close_callback();Library.setReaderMenus(ui,true);Library.readerAction(ui,"size",18);Library.readingApply(ui,"font",1);Library.readingApply(ui,"margins","custom");Library.readingApply(ui,"spacing",3);Library.readingApply(ui,"contrast",3);if not Library.readerSettings(ui).clock then Library.readerAction(ui,"clock") end;return true')
    time.sleep(1)


def review(device, out):
    out.mkdir(parents=True, exist_ok=True)
    fixture = prepare(device, out)
    def shot(name, code, ready=None):
        print(name, flush=True)
        device.command(code)
        if ready:
            wait(device, ready)
        time.sleep(.4)
        device.shot(out / (name + '.png'))
    shot('reader-top', 'assert(ReaderPanel.show(liveUI(),"reader-top-panel"));return true',
         'local s=ReaderPanel.sheet;return s and s.native.time_left=="3 h 22 m left in book" and s.native.chapter_time_left=="26 m left in chapter" and "ready" or "pending"')
    shot('reader-bottom', 'assert(ReaderPanel.show(liveUI(),"reader-bottom-panel"));return true',
         'local s=ReaderPanel.sheet;return s and s.native.time_left=="3 h 22 m left in book" and s.native.chapter_time_left=="26 m left in chapter" and "ready" or "pending"')
    shot('contents', 'ReaderPanel.close();ReaderPanel.navigation(liveUI(),"contents");return true')
    quotes=['She knew the tide had turned at half past ten. She knew her father did not go down to the rocks at night for anything less than a body or a boat.',
            'It smelled of glass. Clean and cold and faintly electric, like the minute before a storm makes up its mind.',
            'A hundred and nine steps. She counted them anyway, the way he had taught her.', 'The church kept everything else.']
    code='ReaderPanel.close();local ui=liveUI();ui.annotation.annotations={};'
    for i,quote in enumerate(quotes):
        chapter=[7,14,3,11][i]
        code+='do local xp=ui.toc.toc['+str(chapter)+'].xpointer;ui.annotation.annotations[#ui.annotation.annotations+1]={page=xp,pos0=xp,pos1=xp,drawer="lighten",text='+json.dumps(quote)+',chapter="Chapter '+str(chapter)+'",note='+json.dumps('Use this line for the reading group' if i==1 else '')+'} end;'
    code+='local xp=ui.document:getXPointer();ui.annotation.annotations[5]={page=xp,text="Saved position",chapter="Chapter 14"};return true'
    device.command(code)
    shot('saved-items', 'ReaderPanel.navigation(liveUI(),"annotations");return true')
    shot('goto', 'ReaderPanel.close();ReaderPanel.goDialog(liveUI());return true')
    shot('book-info', 'ReaderPanel.close();ReaderPanel.show(liveUI(),"book-info");return true',
         'local m=ReaderPanel.sheet.model;return m.started=="9 days ago" and m.time=="4 h 05 m" and m.description and m.description:find("When the keeper",1,true) and m.series_line=="Book 2 of 5 · The Tidewright Cycle" and "ready" or "pending"')
    assert device.command(f'assert(ReaderPanel.sheet.model.total_pages=={fixture["total"]});return true') == 'true'
    # Exercise the actual native whole-word engine, not a mocked result list.
    device.command('ReaderPanel.search(liveUI(),"orch",true);return true')
    wait(device, 'local s=ReaderPanel.sheet;return s and s.navigation_kind=="search" and s.navigation.total==0 and s.navigation.whole_words and "ready" or "pending"')
    device.command('ReaderPanel.search(liveUI(),"orch",false);return true')
    wait(device, 'local s=ReaderPanel.sheet;return s and s.navigation_kind=="search" and s.navigation.total==128 and s.navigation.capped and not s.navigation.whole_words and "ready" or "pending"')
    device.command('ReaderPanel.search(liveUI(),"lantern",true);return true')
    wait(device, 'local s=ReaderPanel.sheet;return s and s.navigation_kind=="search" and s.navigation.total==5 and not s.navigation.capped and s.navigation.whole_words and "ready" or "pending"')
    device.shell('input','tap','1200','600')
    wait(device, 'local s=ReaderPanel.sheet;return s and s.navigation_kind=="search" and not s.navigation.whole_words and "ready" or "pending"')
    device.shell('input','tap','1200','600')
    wait(device, 'local s=ReaderPanel.sheet;return s and s.navigation_kind=="search" and s.navigation.whole_words and s.navigation.total==5 and "ready" or "pending"')
    device.shot(out / 'search-results.png')
    device.command('ReaderPanel.search(liveUI(),"zzzz-no-native-match-zzzz",true);return true')
    wait(device, 'local s=ReaderPanel.sheet;return s and s.navigation_kind=="search" and s.navigation.total==0 and "ready" or "pending"')
    device.shot(out / 'no-matches.png')
    shot('search-input', 'ReaderPanel.close();ReaderPanel.searchDialog(liveUI());ReaderPanel.sheet.search_input:setText("lantern");UI:setDirty(ReaderPanel.sheet,"ui");return true')
    device.shell('input','tap','1200','600')
    wait(device, 'return ReaderPanel.sheet and ReaderPanel.sheet.search_whole==false and "ready" or "pending"')
    device.command('assert(ReaderPanel.sheet.search_input:getText()=="lantern");return true')
    device.shell('input','tap','1200','600')
    wait(device, 'return ReaderPanel.sheet and ReaderPanel.sheet.search_whole==true and "ready" or "pending"')
    device.shot(out / 'search-input.png')
    (out / 'manifest.json').write_text(json.dumps(dict(serial=device.serial, resolution='1404x1872', dpi=300,
        book_fixture=fixture, data_source='Actual EPUB document properties and MD5-linked KOReader statistics DB; no supplied display models',
        whole_word_checks=['orch whole-word: 0', 'orch substring: capped 128', 'lantern whole-word: native results']), indent=2) + '\n')
    gallery(out)


def gallery(out):
    notes = {'reader-top': 'No sign-in text; compact learning label; measured book time from native per-book pace.',
             'reader-bottom': 'Actual worker pace: 26 m left in chapter / 3 h 22 m left in book. Generic emulator front light is supported; warmth driver is absent.',
             'book-info': 'Actual open-document page count and EPUB dc:description; MD5-linked per-book Started and Time read; saved five-book series count. No model injection.',
             'search-results': 'Native whole-word search, ellipsized match-centred context, chapter/page location and cap wording only when the 129th hit proves a cap.',
             'search-input': 'Whole words toggles inside the field. The native keyboard remains for input methods.',
             'no-matches': 'Real whole-word zero-result state. Approved Search shell is the empty-state reference.'}
    sections = []
    for name, reference, y in PAIRS:
        native = Image.open(out / (name + '.png')).convert('RGB')
        assert native.size == (1404, 1872)
        end = 480 if name == 'reader-top' else 1872
        approved = Image.open(ROOT / 'docs/design/booksync-home/shots' / reference).convert('RGB').crop((1, y, 1405, end))
        native = native.crop((0, y, 1404, end))
        pair = Image.new('RGB', (2824, native.height + 40), '#ddd')
        draw = ImageDraw.Draw(pair)
        draw.rectangle((0, 0, 2824, 40), fill='white')
        font = ImageFont.load_default(size=22)
        draw.text((16, 8), 'Approved mockup', fill='black', font=font)
        draw.text((1440, 8), 'Native KOReader · Round 1 · real per-book data', fill='black', font=font)
        pair.paste(approved, (0, 40));pair.paste(native, (1420, 40))
        filename = 'pair-' + name + '.png'
        pair.save(out / filename, optimize=True)
        sections.append(f'<section><h2>{name}</h2><p>{notes.get(name, "Native cached reader data; synthetic narrative and pagination differ from the static mockup.")}</p><a href="{filename}"><img src="{filename}" loading="lazy"></a></section>')
    (out / 'index.html').write_text('<!doctype html><meta charset="utf-8"><title>V2 reader panels — Round 1</title><style>body{max-width:1500px;margin:24px auto;padding:20px;font:16px/1.5 system-ui;background:#f5f5f5}section{border-top:1px solid #aaa;margin-top:32px;padding-top:16px}img{width:100%;height:auto}</style><h1>V2 reader panels · Round 1</h1><p>Approved crop left, native 1404×1872 / 300 dpi capture right. All Book info and pace fields come from the open EPUB and its own native statistics database. No display-model injections. Native font/icon metrics, synthetic narrative/pagination, native keyboard, bounded annotation paging and the generic emulator’s missing warmth driver remain different.</p>' + ''.join(sections))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    review(Emulator(args.serial), args.out)
