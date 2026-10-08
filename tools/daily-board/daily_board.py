#!/usr/bin/env python3
"""Daily Board: a generated Excalidraw board for the kiosk.

Commands
  build    Fetch todos, flags and calendar, write today's board file.
  sync     Read today's (and yesterday's) board, detect hand-drawn ticks,
           write Done back to the Google Sheet.
  install  Write and load the launchd agents (build at 05:30, sync every 5 min).
  demo     Build a board from sample data without touching the network.

Config lives in ~/Library/Application Support/Daily Board/config.json:
  { "endpoint": "https://script.google.com/macros/s/.../exec",
    "key": "the SECRET script property",
    "board_dir": "~/Documents/Daily Board" }
"""
import base64
import datetime as dt
import glob
import hashlib
import json
import os
import plistlib
import random
import re
import struct
import subprocess
import sys
import urllib.parse
import urllib.request

APP_DIR = os.path.expanduser("~/Library/Application Support/Daily Board")
CONFIG_PATH = os.path.join(APP_DIR, "config.json")
STATE_PATH = os.path.join(APP_DIR, "state.json")
LOG_PATH = os.path.join(APP_DIR, "daily-board.log")
DEFAULT_BOARD_DIR = os.path.expanduser("~/Documents/Daily Board")

# Brand colours (Lindon Academy brand manual)
INDIGO = "#142C61"
WISTERIA = "#90AAFF"
GOLD = "#FFF494"
MAUVE = "#CC8DFF"
SNOW = "#F8F8F8"
GREY = "#868e96"
RED = "#e03131"
TICK_GREEN = "#2b8a3e"

FONT = 1  # hand-drawn (Virgil)
TAG = "dailyBoard"


# ----------------------------------------------------------------------------
# Config / state / logging
# ----------------------------------------------------------------------------

def log(msg):
    line = "%s %s" % (dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(line)
    try:
        os.makedirs(APP_DIR, exist_ok=True)
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def load_config():
    if not os.path.exists(CONFIG_PATH):
        os.makedirs(APP_DIR, exist_ok=True)
        with open(CONFIG_PATH, "w") as f:
            json.dump({"endpoint": "", "key": "", "board_dir": DEFAULT_BOARD_DIR}, f, indent=2)
        sys.exit("No config yet. Fill in endpoint and key in %s" % CONFIG_PATH)
    with open(CONFIG_PATH) as f:
        cfg = json.load(f)
    cfg["board_dir"] = os.path.expanduser(cfg.get("board_dir") or DEFAULT_BOARD_DIR)
    return cfg


def load_state():
    try:
        with open(STATE_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"done": {}}


def save_state(state):
    os.makedirs(APP_DIR, exist_ok=True)
    with open(STATE_PATH, "w") as f:
        json.dump(state, f, indent=2)


# ----------------------------------------------------------------------------
# Google Apps Script endpoint
# ----------------------------------------------------------------------------

def api_get(cfg, params):
    if not cfg.get("endpoint") or not cfg.get("key"):
        sys.exit("endpoint/key missing in %s" % CONFIG_PATH)
    params = dict(params, key=cfg["key"])
    url = cfg["endpoint"] + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "daily-board/1"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = resp.read().decode("utf-8")
    try:
        data = json.loads(body)
    except ValueError:
        raise RuntimeError("Endpoint did not return JSON (is the deployment set to 'Anyone'?): %s" % body[:200])
    if isinstance(data, dict) and data.get("error"):
        raise RuntimeError("Endpoint error: %s" % data["error"])
    return data


def fetch_board(cfg, day):
    return api_get(cfg, {"action": "board", "date": day.isoformat()})


def push_done(cfg, sheet, done_ids, undone_ids):
    if not done_ids and not undone_ids:
        return 0
    data = api_get(cfg, {
        "action": "done", "sheet": sheet,
        "done": ",".join(done_ids), "undone": ",".join(undone_ids),
    })
    return data.get("updated", 0)


# ----------------------------------------------------------------------------
# Excalidraw element helpers
# ----------------------------------------------------------------------------

_counter = [0]


def new_id(prefix):
    _counter[0] += 1
    return "%s-%d-%s" % (prefix, _counter[0], hashlib.md5(os.urandom(8)).hexdigest()[:6])


def base_element(kind, x, y, w, h, **over):
    el = {
        "id": new_id(kind),
        "type": kind,
        "x": x, "y": y, "width": w, "height": h,
        "angle": 0,
        "strokeColor": INDIGO,
        "backgroundColor": "transparent",
        "fillStyle": "solid",
        "strokeWidth": 2,
        "strokeStyle": "solid",
        "roughness": 1,
        "opacity": 100,
        "groupIds": [],
        "frameId": None,
        "index": None,
        "roundness": None,
        "seed": random.randint(1, 2 ** 31),
        "version": 1,
        "versionNonce": random.randint(1, 2 ** 31),
        "isDeleted": False,
        "boundElements": None,
        "updated": int(dt.datetime.now().timestamp() * 1000),
        "link": None,
        "locked": False,
    }
    el.update(over)
    return el


def tagged(el, **data):
    el["customData"] = {TAG: data}
    return el


def text(x, y, s, size=20, color=INDIGO, bold=False, width=None):
    lines = s.split("\n")
    est_w = width or max(len(l) for l in lines) * size * 0.55
    h = size * 1.25 * len(lines)
    return tagged(base_element(
        "text", x, y, est_w, h,
        strokeColor=color,
        text=s, originalText=s,
        fontSize=size, fontFamily=FONT,
        textAlign="left", verticalAlign="top",
        containerId=None, lineHeight=1.25, autoResize=True,
        roughness=0, strokeWidth=2 if bold else 1,
    ), kind="text")


def rect(x, y, w, h, fill="transparent", stroke=INDIGO, stroke_width=2):
    return tagged(base_element(
        "rectangle", x, y, w, h,
        backgroundColor=fill, strokeColor=stroke, strokeWidth=stroke_width,
        roundness={"type": 3},
    ), kind="panel")


def checkbox(x, y, size, sheet, row_id):
    return tagged(base_element(
        "rectangle", x, y, size, size,
        backgroundColor="#ffffff", strokeColor=INDIGO, strokeWidth=2,
        roundness={"type": 3},
    ), kind="checkbox", sheet=sheet, id=row_id)


def generated_tick(x, y, size, sheet, row_id):
    """A tick stroke drawn inside a box for items already done."""
    pts = [[0, size * 0.55], [size * 0.38, size * 0.92], [size * 1.05, size * 0.05]]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return tagged(base_element(
        "freedraw", x + size * 0.05, y - size * 0.05, max(xs) - min(xs), max(ys) - min(ys),
        strokeColor=TICK_GREEN, strokeWidth=3, roughness=1,
        points=pts, pressures=[], simulatePressure=True, lastCommittedPoint=None,
    ), kind="tick", sheet=sheet, id=row_id)


def wrap(s, max_chars):
    words = s.split()
    lines, cur = [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > max_chars:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    if cur:
        lines.append(cur)
    return "\n".join(lines) if lines else s


def image_dimensions(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", data[16:24])
        return w, h
    if data[:2] == b"\xff\xd8":
        i = 2
        while i < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return w, h
            seg = struct.unpack(">H", data[i + 2:i + 4])[0]
            i += 2 + seg
    return None


# ----------------------------------------------------------------------------
# Board layout
# ----------------------------------------------------------------------------

def parse_day(s):
    try:
        return dt.date.fromisoformat(s) if s else None
    except ValueError:
        return None


def nice_date(d, today):
    if d == today:
        return "today"
    if d == today + dt.timedelta(days=1):
        return "tomorrow"
    return d.strftime("%a %-d %b")


class Board:
    def __init__(self, today):
        self.today = today
        self.elements = []
        self.files = {}

    def add(self, *els):
        self.elements.extend(els)

    def panel(self, x, y, w, title, body_fn, accent=WISTERIA, min_h=120):
        """Draws a titled panel; body_fn(x, y, w) -> height used. Returns panel height."""
        title_h = 44
        start = len(self.elements)
        body_h = body_fn(x + 20, y + title_h + 10, w - 40)
        h = max(min_h, title_h + body_h + 30)
        # Panel chrome goes underneath the body, so insert it where the body began.
        self.elements[start:start] = [
            rect(x, y, w, h, fill=SNOW, stroke=INDIGO),
            rect(x, y, w, title_h, fill=accent, stroke=INDIGO),
            text(x + 18, y + 8, title, size=24, bold=True),
        ]
        return h

    def checklist(self, x, y, w, sheet, items, empty_msg="Nothing here"):
        """items: list of dicts {id, label, done, color}. Returns height used."""
        if not items:
            self.add(text(x, y, empty_msg, size=18, color=GREY))
            return 30
        size = 26
        line_h = 24
        cy = y
        max_chars = max(20, int((w - 60) / 11))
        for it in items:
            label = wrap(it["label"], max_chars)
            n_lines = label.count("\n") + 1
            self.add(checkbox(x, cy, size, sheet, it["id"]))
            color = GREY if it["done"] else it.get("color", INDIGO)
            self.add(text(x + size + 14, cy - 2, label, size=20, color=color))
            if it["done"]:
                self.add(generated_tick(x, cy, size, sheet, it["id"]))
            cy += max(size + 14, n_lines * line_h + 14)
        return cy - y

    def schedule(self, x, y, w, events):
        if not events:
            self.add(text(x, y, "Nothing in the calendar", size=18, color=GREY))
            return 30
        cy = y
        for ev in events:
            if ev.get("allDay"):
                when = "all day"
            else:
                when = ev["start"][11:16] + "–" + ev["end"][11:16]
            self.add(text(x, cy, when, size=18, color=GREY))
            title = wrap(ev["title"], max(18, int((w - 130) / 11)))
            self.add(text(x + 120, cy - 2, title, size=20))
            cy += 24 * (title.count("\n") + 1) + 12
        return cy - y

    def picture(self, x, y, w, path):
        if not path:
            self.add(text(x, y, "Drop pictures into\n" + os.path.join(DEFAULT_BOARD_DIR, "Pictures"),
                          size=16, color=GREY))
            return 60
        with open(path, "rb") as f:
            data = f.read()
        dims = image_dimensions(data)
        if not dims:
            self.add(text(x, y, "Could not read %s" % os.path.basename(path), size=16, color=GREY))
            return 60
        iw, ih = dims
        scale = min(w / iw, 520 / ih)
        dw, dh = iw * scale, ih * scale
        ext = os.path.splitext(path)[1].lower()
        mime = "image/png" if ext == ".png" else "image/jpeg"
        file_id = hashlib.sha1(data).hexdigest()
        self.files[file_id] = {
            "mimeType": mime,
            "id": file_id,
            "dataURL": "data:%s;base64,%s" % (mime, base64.b64encode(data).decode("ascii")),
            "created": int(dt.datetime.now().timestamp() * 1000),
            "lastRetrieved": int(dt.datetime.now().timestamp() * 1000),
        }
        self.add(tagged(base_element(
            "image", x + (w - dw) / 2, y, dw, dh,
            fileId=file_id, status="saved", scale=[1, 1], crop=None,
            roughness=0, strokeColor="transparent",
        ), kind="picture"))
        return dh

    def to_json(self, source):
        return {
            "type": "excalidraw",
            "version": 2,
            "source": source,
            "elements": self.elements,
            "appState": {
                "gridSize": None,
                "viewBackgroundColor": "#ffffff",
            },
            "files": self.files,
        }


def pick_picture(board_dir, today):
    folder = os.path.join(board_dir, "Pictures")
    pics = sorted(
        p for p in glob.glob(os.path.join(folder, "*"))
        if os.path.splitext(p)[1].lower() in (".png", ".jpg", ".jpeg")
    )
    if not pics:
        return None
    return pics[today.toordinal() % len(pics)]


def categorise(todos, today):
    """Split todo rows into the board's sections."""
    do_today, due_today, overdue, coming = [], [], [], []
    horizon = today + dt.timedelta(days=7)
    for t in todos:
        do_d = parse_day(t.get("doDate"))
        due_d = parse_day(t.get("dueDate"))
        done = bool(t.get("done"))
        who = t.get("who", "")
        suffix = ""
        if who and who.lower() not in ("john", "johnny", "me"):
            suffix = "  (%s)" % who
        label = t["item"] + suffix

        # Done items only linger on the board for the day they were scheduled.
        if done and not (do_d == today or due_d == today):
            continue

        if do_d and do_d <= today:
            lbl = label
            if do_d < today and not done:
                lbl += "  · from %s" % do_d.strftime("%a")
            if due_d and due_d != today:
                lbl += "  · due %s" % nice_date(due_d, today)
            do_today.append({"id": t["id"], "label": lbl, "done": done,
                             "color": RED if (due_d and due_d < today) else INDIGO})
        elif due_d and due_d == today:
            due_today.append({"id": t["id"], "label": label, "done": done})
        elif due_d and due_d < today:
            overdue.append({"id": t["id"], "label": label + "  · due %s" % due_d.strftime("%a %-d %b"),
                            "done": done, "color": RED})
        elif (do_d and do_d <= horizon) or (due_d and due_d <= horizon):
            bits = []
            if do_d:
                bits.append("do %s" % nice_date(do_d, today))
            if due_d:
                bits.append("due %s" % nice_date(due_d, today))
            sort_key = min(d for d in (do_d, due_d) if d)
            coming.append({"id": t["id"], "label": label + "  · " + ", ".join(bits),
                           "done": done, "_k": sort_key})
    coming.sort(key=lambda c: c["_k"])
    for c in coming:
        c.pop("_k", None)
    return do_today, due_today, overdue, coming


def flag_items(flags, today):
    out = []
    cutoff = today - dt.timedelta(days=14)
    for fl in flags:
        d = parse_day(fl.get("date"))
        if fl.get("done") and d != today:
            continue
        if d and d < cutoff:
            continue
        head = " · ".join(b for b in (fl.get("channel"), fl.get("client")) if b)
        when = d.strftime("%a %-d") if d and d != today else ""
        label = (head + ": " if head else "") + fl["note"]
        if when:
            label += "  · " + when
        out.append({"id": fl["id"], "label": label, "done": bool(fl.get("done")), "_d": d or today})
    out.sort(key=lambda f: f["_d"], reverse=True)
    for f in out:
        f.pop("_d", None)
    return out


def build_board(data, today, board_dir):
    b = Board(today)
    do_today, due_today, overdue, coming = categorise(data.get("todos", []), today)
    flags = flag_items(data.get("flags", []), today)
    events = data.get("events", [])

    # Header
    b.add(text(40, 30, today.strftime("%A %-d %B %Y"), size=44, bold=True))
    remaining = sum(1 for i in do_today + due_today + overdue if not i["done"])
    b.add(text(44, 92, "%d to do today · %d in the diary · built %s" % (
        remaining, len(events), dt.datetime.now().strftime("%H:%M")), size=16, color=GREY))

    # Column A: schedule + flags
    ax, aw, y = 40, 520, 140
    h = b.panel(ax, y, aw, "Diary", lambda x, yy, w: b.schedule(x, yy, w, events), accent=WISTERIA)
    y += h + 30
    b.panel(ax, y, aw, "Jess flagged",
            lambda x, yy, w: b.checklist(x, yy, w, "Flags", flags, "Nothing flagged"), accent=GOLD)

    # Column B: todos
    bx, bw, y = 600, 640, 140
    h = b.panel(bx, y, bw, "Do today",
                lambda x, yy, w: b.checklist(x, yy, w, "Todos", do_today, "Nothing scheduled for today"),
                accent=WISTERIA)
    y += h + 30
    if overdue:
        h = b.panel(bx, y, bw, "Overdue",
                    lambda x, yy, w: b.checklist(x, yy, w, "Todos", overdue), accent="#ffc9c9")
        y += h + 30
    if due_today:
        h = b.panel(bx, y, bw, "Due today",
                    lambda x, yy, w: b.checklist(x, yy, w, "Todos", due_today), accent=MAUVE)
        y += h + 30
    b.panel(bx, y, bw, "Coming up",
            lambda x, yy, w: b.checklist(x, yy, w, "Todos", coming, "Nothing in the next week"),
            accent=SNOW)

    # Column C: picture + scratch space
    cx, cw, y = 1280, 480, 140
    pic = pick_picture(board_dir, today)
    h = b.panel(cx, y, cw, "Picture of the day", lambda x, yy, w: b.picture(x, yy, w, pic), accent=GOLD)
    y += h + 30
    b.panel(cx, y, cw, "Scratch", lambda x, yy, w: 260, accent=SNOW)

    return b.to_json("Lindon Academy daily board")


def board_path(board_dir, day):
    return os.path.join(board_dir, day.strftime("%Y-%m-%d %a") + ".excalidraw")


def cmd_build(cfg, day=None, data=None):
    day = day or dt.date.today()
    os.makedirs(cfg["board_dir"], exist_ok=True)
    os.makedirs(os.path.join(cfg["board_dir"], "Pictures"), exist_ok=True)
    if data is None:
        cmd_sync(cfg)  # capture any ticks drawn since the last sync first
        data = fetch_board(cfg, day)
    doc = build_board(data, day, cfg["board_dir"])
    path = board_path(cfg["board_dir"], day)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(doc, f)
    os.replace(tmp, path)
    # Remember the server's view of done so sync only sends real changes.
    state = load_state()
    for t in data.get("todos", []):
        state["done"]["Todos:" + t["id"]] = bool(t.get("done"))
    for fl in data.get("flags", []):
        state["done"]["Flags:" + fl["id"]] = bool(fl.get("done"))
    save_state(state)
    log("built %s (%d elements)" % (path, len(doc["elements"])))
    return path


# ----------------------------------------------------------------------------
# Sync: find hand-drawn ticks
# ----------------------------------------------------------------------------

def bbox(el):
    x, y, w, h = el["x"], el["y"], el.get("width", 0), el.get("height", 0)
    if el["type"] in ("freedraw", "line", "arrow") and el.get("points"):
        xs = [p[0] for p in el["points"]]
        ys = [p[1] for p in el["points"]]
        return (x + min(xs), y + min(ys), x + max(xs), y + max(ys))
    return (x, y, x + w, y + h)


def overlaps(a, b):
    return a[0] <= b[2] and b[0] <= a[2] and a[1] <= b[3] and b[1] <= a[3]


def detect_ticks(doc):
    """Returns {(sheet, id): done_bool} for every checkbox in the document."""
    els = [e for e in doc.get("elements", [])]
    boxes = [e for e in els if not e.get("isDeleted")
             and (e.get("customData") or {}).get(TAG, {}).get("kind") == "checkbox"]
    gen_ticks = {}
    for e in els:
        d = (e.get("customData") or {}).get(TAG, {})
        if d.get("kind") == "tick":
            gen_ticks[(d["sheet"], d["id"])] = e
    strokes = [e for e in els if not e.get("isDeleted")
               and e["type"] in ("freedraw", "line", "arrow", "ellipse", "rectangle", "diamond", "text")
               and TAG not in (e.get("customData") or {})]
    stroke_boxes = [(bbox(s), s) for s in strokes]
    result = {}
    for box in boxes:
        d = box["customData"][TAG]
        key = (d["sheet"], d["id"])
        size = box["width"]
        margin = size * 0.6
        bb = bbox(box)
        zone = (bb[0] - margin, bb[1] - margin, bb[2] + margin, bb[3] + margin)
        ticked = False
        for sb, s in stroke_boxes:
            if not overlaps(sb, zone):
                continue
            sw, sh = sb[2] - sb[0], sb[3] - sb[1]
            if sw > size * 4 or sh > size * 4:
                continue  # a big scribble across the panel is not a tick
            ticked = True
            break
        if not ticked:
            g = gen_ticks.get(key)
            if g is not None and not g.get("isDeleted"):
                ticked = True
        result[key] = ticked
    return result


def cmd_sync(cfg):
    today = dt.date.today()
    state = load_state()
    changes = {"Todos": {"done": [], "undone": []}, "Flags": {"done": [], "undone": []}}
    seen = set()
    for day in (today, today - dt.timedelta(days=1)):
        path = board_path(cfg["board_dir"], day)
        if not os.path.exists(path):
            continue
        try:
            with open(path) as f:
                doc = json.load(f)
        except (OSError, ValueError) as err:
            log("skip %s: %s" % (path, err))
            continue
        for (sheet, row_id), ticked in detect_ticks(doc).items():
            if (sheet, row_id) in seen:
                continue  # today's file wins over yesterday's
            seen.add((sheet, row_id))
            key = "%s:%s" % (sheet, row_id)
            if state["done"].get(key) == ticked:
                continue
            changes[sheet]["done" if ticked else "undone"].append(row_id)
    total = 0
    for sheet, ch in changes.items():
        if ch["done"] or ch["undone"]:
            n = push_done(cfg, sheet, ch["done"], ch["undone"])
            total += n
            for rid in ch["done"]:
                state["done"]["%s:%s" % (sheet, rid)] = True
            for rid in ch["undone"]:
                state["done"]["%s:%s" % (sheet, rid)] = False
            log("%s: ticked %s, unticked %s" % (sheet, ch["done"] or "-", ch["undone"] or "-"))
    save_state(state)
    if total == 0:
        print("sync: nothing changed")
    return total


# ----------------------------------------------------------------------------
# launchd
# ----------------------------------------------------------------------------

def cmd_install():
    agents = os.path.expanduser("~/Library/LaunchAgents")
    os.makedirs(agents, exist_ok=True)
    script = os.path.abspath(__file__)
    python = sys.executable
    specs = {
        "com.lindonacademy.dailyboard.build": {
            "ProgramArguments": [python, script, "build"],
            "StartCalendarInterval": {"Hour": 5, "Minute": 30},
            "RunAtLoad": True,
        },
        "com.lindonacademy.dailyboard.sync": {
            "ProgramArguments": [python, script, "sync"],
            "StartInterval": 300,
        },
    }
    for label, extra in specs.items():
        plist = dict(extra, Label=label,
                     StandardOutPath=LOG_PATH, StandardErrorPath=LOG_PATH)
        path = os.path.join(agents, label + ".plist")
        with open(path, "wb") as f:
            plistlib.dump(plist, f)
        subprocess.run(["launchctl", "unload", path], capture_output=True)
        res = subprocess.run(["launchctl", "load", path], capture_output=True, text=True)
        print("loaded %s %s" % (label, res.stderr.strip()))
    print("Agents installed. Logs: %s" % LOG_PATH)


# ----------------------------------------------------------------------------
# Demo data
# ----------------------------------------------------------------------------

def demo_data(today):
    d = lambda n: (today + dt.timedelta(days=n)).isoformat()
    return {
        "date": today.isoformat(),
        "todos": [
            {"id": "a1", "item": "Reply to the Patels about moving Thursday", "doDate": d(0), "dueDate": d(1), "done": False, "who": "Jess"},
            {"id": "a2", "item": "Mark the Year 11 mock papers", "doDate": d(-1), "dueDate": d(2), "done": False, "who": "John"},
            {"id": "a3", "item": "Send October invoices", "doDate": d(0), "dueDate": d(0), "done": True, "who": ""},
            {"id": "a4", "item": "Chase the DBS renewal form", "doDate": "", "dueDate": d(-3), "done": False, "who": "Jess"},
            {"id": "a5", "item": "Book the hall for the revision day", "doDate": "", "dueDate": d(0), "done": False, "who": ""},
            {"id": "a6", "item": "Plan the Further Maths scheme of work for next half term, including the mechanics unit", "doDate": d(3), "dueDate": d(6), "done": False, "who": ""},
            {"id": "a7", "item": "Renew the Zoom subscription", "doDate": "", "dueDate": d(5), "done": False, "who": "Jess"},
        ],
        "flags": [
            {"id": "f1", "date": d(0), "client": "Mrs Okafor", "channel": "WhatsApp", "note": "Asked if Tuesday can move to 5pm", "done": False},
            {"id": "f2", "date": d(-1), "client": "Sam's dad", "channel": "Email", "note": "Wants a progress summary before parents' evening", "done": False},
        ],
        "events": [
            {"title": "Year 10 maths · Priya", "start": d(0) + "T09:00", "end": d(0) + "T10:00", "allDay": False},
            {"title": "Admin block", "start": d(0) + "T11:00", "end": d(0) + "T12:00", "allDay": False},
            {"title": "A-level · Tom (Zoom)", "start": d(0) + "T16:00", "end": d(0) + "T17:30", "allDay": False},
        ],
    }


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "build"
    if cmd == "demo":
        cfg = {"board_dir": DEFAULT_BOARD_DIR}
        today = dt.date.today()
        path = cmd_build(cfg, today, demo_data(today))
        print(path)
        return
    cfg = load_config()
    if cmd == "build":
        cmd_build(cfg)
    elif cmd == "sync":
        cmd_sync(cfg)
    elif cmd == "install":
        cmd_install()
    elif cmd == "fetch":
        print(json.dumps(fetch_board(cfg, dt.date.today()), indent=2))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    try:
        main(sys.argv)
    except Exception as err:  # noqa: BLE001
        log("error: %s" % err)
        raise
