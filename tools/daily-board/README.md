# Daily Board

A generated Excalidraw board for the kiosk: today's diary, a checklist of
todos split by **do date** and **due date**, the things Jess has flagged, a
picture of the day, and a scratch area. You tick items by drawing on the
canvas; a sync script reads the strokes and marks the rows done in the sheet.

```
Google Sheet "Daily Board"  ──(Apps Script)──▶  daily_board.py build  ──▶  ~/Daily Board/2026-10-08 Thu.excalidraw
        ▲                                                                              │
        └────────── daily_board.py sync (every 5 min, reads your ticks) ◀──────────────┘
```

Sheet: https://docs.google.com/spreadsheets/d/1jEjQ7GBBfrsGB5pF2Uuk2kONbK_jyxtcgs0jk-hsmkA/edit

## How the sheet works (this is all Jess needs)

**Todos** tab, one row per item:

| Item | Do date | Due date | Done | Who | Notes | ID |
|---|---|---|---|---|---|---|

- *Do date* = the day it should appear under **Do today**. Unticked items roll forward each day, marked "from Tue".
- *Due date* = the deadline. Appears under **Due today** on the day, **Overdue** (red) after it, and is shown next to the item everywhere else.
- Items with only a date in the next 7 days go under **Coming up**.
- *Done* is ticked automatically when you draw a tick on the board. Jess can also tick it by hand.
- *Who* shows as "(Jess)" after the item when it is not you.
- *ID* is filled in automatically. Leave it alone.
- To remove an item, delete the row.

**Flags** tab: Date, Client, Channel (Email/WhatsApp/Phone), Note, Done, ID. Flags from the last 14 days show under **Jess flagged** with a checkbox; ticking one marks it Done so Jess knows it is handled.

## One-time setup (about 10 minutes)

1. **Apps Script**: open the sheet, Extensions ▸ Apps Script, replace the code with `Code.gs`.
   Project Settings ▸ Script Properties ▸ add `SECRET` with any long random string.
   Deploy ▸ New deployment ▸ type *Web app*, *Execute as: Me*, *Who has access: Anyone* ▸ Deploy.
   Authorise it (it needs Sheets + Calendar). Copy the Web app URL.
2. **Config**: run `python3 daily_board.py build` once; it creates
   `~/Library/Application Support/Daily Board/config.json`. Paste the URL as `endpoint` and the secret as `key`.
3. **Check it**: `python3 daily_board.py fetch` prints today's data; `python3 daily_board.py build` writes today's board.
4. **Schedule**: `python3 daily_board.py install` loads two launchd agents: build at 05:30, sync every 5 minutes.
5. **Pictures**: by default the panel shows NASA's Astronomy Picture of the Day with its title and credit,
   read from https://science.nasa.gov/apod/ (cached in the app support folder). Drop PNG/JPG files into
   `~/Daily Board/Pictures` to override it; those rotate one per day. Set `"picture": "local"` in the
   config to turn NASA off.
6. **Share the sheet with Jess** (editor). Nothing else for her to set up.

The folder `~/Daily Board` is already linked in Lindon Academy under *Linked Storage* (via a symlink at
`~/Documents/Daily Board`). It lives outside Documents on purpose: macOS refuses to let launchd agents write
into Documents, Desktop or Downloads.
Each morning click the new day's file in that folder; the kiosk mirrors whatever is open.

## Day to day

- Draw anything over a checkbox to tick it (pencil, line, a scribble). Within 5 minutes the sheet row is marked Done.
- Delete a generated green tick to un-tick an item.
- Scribble freely elsewhere; strokes much larger than a checkbox are ignored by the sync.
- Yesterday's file stays in the folder as a record. The morning build also syncs yesterday's ticks first.
- Want a fresh board mid-day (say Jess added a "do today" item)? Open a different file in the app, run
  `python3 daily_board.py build`, then open today's file again. Rebuilding while the file is open in the
  app loses the rebuild, because the app autosaves its own copy over it.

## Files

- `Code.gs` — Apps Script backend (read sheet + calendar, assign IDs, mark done).
- `daily_board.py` — generator (`build`), tick detector (`sync`), `install`, `demo`, `fetch`.
- Logs: `~/Library/Application Support/Daily Board/daily-board.log`.
