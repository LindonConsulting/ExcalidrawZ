// Daily Board – Google Apps Script backend.
//
// Paste this into Extensions ▸ Apps Script of the "Daily Board" spreadsheet,
// set a Script Property called SECRET (Project Settings ▸ Script Properties),
// then Deploy ▸ New deployment ▸ Web app, "Execute as: Me", "Who has access: Anyone".
// Copy the Web app URL into ~/Library/Application Support/Daily Board/config.json.
//
// GET  ?key=SECRET&action=board&date=YYYY-MM-DD
//      → { date, todos:[…], flags:[…], events:[…] }
// GET  ?key=SECRET&action=done&sheet=Todos&done=id1,id2&undone=id3
//      → { updated: n }

var TODOS = { name: 'Todos', cols: { item: 0, doDate: 1, dueDate: 2, done: 3, who: 4, notes: 5, id: 6 } };
var FLAGS = { name: 'Flags', cols: { date: 0, client: 1, channel: 2, note: 3, done: 4, id: 5 } };

function doGet(e) {
  var p = (e && e.parameter) || {};
  var secret = PropertiesService.getScriptProperties().getProperty('SECRET');
  if (!secret || p.key !== secret) {
    return json_({ error: 'bad key' });
  }
  try {
    if (p.action === 'done') return json_(markDone_(p));
    return json_(board_(p.date));
  } catch (err) {
    return json_({ error: String(err) });
  }
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function tz_() { return Session.getScriptTimeZone(); }

function isoDate_(v) {
  if (v instanceof Date && !isNaN(v)) return Utilities.formatDate(v, tz_(), 'yyyy-MM-dd');
  if (typeof v === 'string' && v.trim()) {
    var m = v.trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (m) return v.trim();
    var d = new Date(v);
    if (!isNaN(d)) return Utilities.formatDate(d, tz_(), 'yyyy-MM-dd');
  }
  return '';
}

function parseDate_(s) {
  var m = String(s || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) return new Date();
  var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return d;
}

// Reads a sheet, assigns IDs to rows that have content but no ID, returns row objects.
function readSheet_(spec, keyCol) {
  var sh = SpreadsheetApp.getActive().getSheetByName(spec.name);
  if (!sh) return [];
  var last = sh.getLastRow();
  if (last < 2) return [];
  var width = Object.keys(spec.cols).length;
  var range = sh.getRange(2, 1, last - 1, width);
  var values = range.getValues();
  var idCol = spec.cols.id;
  var rows = [];
  var idsToWrite = [];
  for (var i = 0; i < values.length; i++) {
    var row = values[i];
    var hasContent = String(row[keyCol] || '').trim() !== '';
    if (!hasContent) continue;
    var id = String(row[idCol] || '').trim();
    if (!id) {
      id = Utilities.getUuid().replace(/-/g, '').slice(0, 8);
      row[idCol] = id;
      idsToWrite.push([i + 2, id]);
    }
    rows.push({ rowNumber: i + 2, cells: row, id: id });
  }
  for (var k = 0; k < idsToWrite.length; k++) {
    sh.getRange(idsToWrite[k][0], idCol + 1).setValue(idsToWrite[k][1]);
  }
  return rows;
}

function board_(dateStr) {
  var day = parseDate_(dateStr);
  var todos = readSheet_(TODOS, TODOS.cols.item).map(function (r) {
    var c = r.cells, k = TODOS.cols;
    return {
      id: r.id,
      item: String(c[k.item]).trim(),
      doDate: isoDate_(c[k.doDate]),
      dueDate: isoDate_(c[k.dueDate]),
      done: c[k.done] === true || String(c[k.done]).toUpperCase() === 'TRUE',
      who: String(c[k.who] || '').trim(),
      notes: String(c[k.notes] || '').trim()
    };
  });
  var flags = readSheet_(FLAGS, FLAGS.cols.note).map(function (r) {
    var c = r.cells, k = FLAGS.cols;
    return {
      id: r.id,
      date: isoDate_(c[k.date]),
      client: String(c[k.client] || '').trim(),
      channel: String(c[k.channel] || '').trim(),
      note: String(c[k.note]).trim(),
      done: c[k.done] === true || String(c[k.done]).toUpperCase() === 'TRUE'
    };
  });
  return {
    date: Utilities.formatDate(day, tz_(), 'yyyy-MM-dd'),
    todos: todos,
    flags: flags,
    events: events_(day)
  };
}

function events_(day) {
  var out = [];
  var cals = CalendarApp.getAllCalendars().filter(function (c) { return c.isSelected(); });
  if (cals.length === 0) cals = [CalendarApp.getDefaultCalendar()];
  cals.forEach(function (cal) {
    cal.getEventsForDay(day).forEach(function (ev) {
      out.push({
        title: ev.getTitle(),
        start: Utilities.formatDate(ev.getStartTime(), tz_(), "yyyy-MM-dd'T'HH:mm"),
        end: Utilities.formatDate(ev.getEndTime(), tz_(), "yyyy-MM-dd'T'HH:mm"),
        allDay: ev.isAllDayEvent(),
        calendar: cal.getName(),
        location: ev.getLocation() || ''
      });
    });
  });
  out.sort(function (a, b) { return a.start < b.start ? -1 : a.start > b.start ? 1 : 0; });
  return out;
}

function markDone_(p) {
  var spec = p.sheet === 'Flags' ? FLAGS : TODOS;
  var keyCol = spec === FLAGS ? FLAGS.cols.note : TODOS.cols.item;
  var doneIds = (p.done || '').split(',').filter(String);
  var undoneIds = (p.undone || '').split(',').filter(String);
  if (!doneIds.length && !undoneIds.length) return { updated: 0 };
  var sh = SpreadsheetApp.getActive().getSheetByName(spec.name);
  var rows = readSheet_(spec, keyCol);
  var updated = 0;
  rows.forEach(function (r) {
    var want = null;
    if (doneIds.indexOf(r.id) >= 0) want = true;
    else if (undoneIds.indexOf(r.id) >= 0) want = false;
    if (want === null) return;
    sh.getRange(r.rowNumber, spec.cols.done + 1).setValue(want);
    updated++;
  });
  return { updated: updated };
}
