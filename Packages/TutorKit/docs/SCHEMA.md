# TutorKit local schema — target design

Status: proposal (2026-10-07). Current DB is at migration `v4-multi-spec`.
Engine: SQLite via GRDB, one file in Application Support/TutorKit. Media (Excalidraw
elements JSON, thumbnails, PDFs, .apkg) stays on disk, keyed by row id.

## Principles

- **Who** (student) is separate from **what they study** (enrolment) and **what we teach from** (specification / topic).
- Every user-data table carries `createdAt`, `updatedAt`, `deletedAt` (soft delete) and `remoteID` so it can round-trip with the TutorKit Supabase project (#12) without a parallel sync table.
- Reference data (taxonomy, specs, past papers) has no `deletedAt`; it is replaced by import.
- Joins are real tables, not JSON arrays. JSON only for genuinely unstructured blobs (AI recap payloads, mark-scheme breakdowns).
- Text columns are `NOT NULL DEFAULT ''`; nullable means "not known".
- `id` is a UUID blob unless the row is a stable slug (`topic`, `pastPaper`, `course`).

## Entity map

```
student ──< enrolment >── specification ──< specSection ──< specPoint
   │             │                                             │
   │             └── course (reference, mirrors remote)        │
   ├──< lesson ──< lessonTopic >── topic ─────────────────────-┤ specPointTopic
   │      │                                                    │
   │      └──< outcome >── question >── questionSpecPoint ─────┘
   │                          │  └── questionTopic >── topic
   │                          └── pastPaper ──< pastPaperQuestion (optional link)
   ├──< topicProgress >── topic
   ├──< coverageMark >── specPoint
   ├──< assignment ──< assignmentQuestion >── question
   │        └── deck (when kind = deck)
   └──< studentContact
importBatch, syncCursor, meta
```

## Tables

### Reference: curriculum

```sql
topic (            -- built-in taxonomy, user-extensible
  id TEXT PK,                 -- "maths.algebra.quadratics"
  parentID TEXT REFERENCES topic ON DELETE CASCADE,
  subject TEXT NOT NULL, level TEXT,          -- level NULL = all levels
  name TEXT NOT NULL, aliases TEXT NOT NULL DEFAULT '[]',
  sortOrder INTEGER NOT NULL DEFAULT 0,
  isBuiltin INTEGER NOT NULL DEFAULT 1
);

specification (id BLOB PK, subject, level, board, title, code, sourceFileName,
               importedAt, importBatchID BLOB REFERENCES importBatch);
specSection   (id BLOB PK, specificationID → specification CASCADE, code, title, sortOrder);
specPoint     (id BLOB PK, specificationID, sectionID → specSection CASCADE,
               code, text, tier, sortOrder);
specPointTopic (specPointID → specPoint CASCADE, topicID → topic CASCADE,
                PRIMARY KEY (specPointID, topicID));   -- bridges the two tagging systems
course        (id TEXT PK,            -- "gcse_maths": mirrors remote `courses`
               subject, level, displayName, active INTEGER NOT NULL DEFAULT 1);
```

`specPointTopic` is new: once a spec point is mapped to a taxonomy topic, a question tagged against either side can be reported against both, and the coverage checklist can roll up by topic.

### Reference: past papers

```sql
pastPaper (
  id TEXT PK,                 -- "wjec_3300_2023_jun_u1h"
  board, level, tier, subject,
  series TEXT NOT NULL,       -- "2023 June"
  paperName TEXT NOT NULL,    -- "Unit 1 Higher"
  calculator INTEGER, totalMarks INTEGER, timeMinutes INTEGER,
  questionPaperPath TEXT, markSchemePath TEXT,   -- relative to media folder
  importBatchID BLOB REFERENCES importBatch
);
pastPaperQuestion (
  id BLOB PK, paperID TEXT → pastPaper CASCADE,
  number INTEGER NOT NULL, part TEXT NOT NULL DEFAULT '',   -- "", "a", "b(i)"
  marks INTEGER, questionText TEXT NOT NULL DEFAULT '',
  answer TEXT NOT NULL DEFAULT '', markScheme TEXT NOT NULL DEFAULT '',
  markSchemeJSON TEXT,        -- structured breakdown if extracted
  pageStart INTEGER, pageEnd INTEGER,
  UNIQUE (paperID, number, part)
);
```

Separate from `question` on purpose: a past-paper question is the authoritative source; a bank `question` is a canvas-ready capture that may point back to it.

### Question bank

```sql
question (
  id BLOB PK,
  title, source,              -- source kept as free text for non-paper questions
  subject NOT NULL, level, board, tier,
  marks INTEGER, difficulty INTEGER,
  notes TEXT NOT NULL DEFAULT '',
  answer TEXT NOT NULL DEFAULT '', workedSolution TEXT NOT NULL DEFAULT '',
  imageHash TEXT,             -- dHash for duplicate detection
  pastPaperQuestionID BLOB REFERENCES pastPaperQuestion ON DELETE SET NULL,
  importBatchID BLOB REFERENCES importBatch,
  freeTags TEXT NOT NULL DEFAULT '[]',   -- ad-hoc, stays JSON
  remoteID BLOB, createdAt, updatedAt, deletedAt
);
questionTopic     (questionID → question CASCADE, topicID → topic CASCADE, PK (questionID, topicID));
questionSpecPoint (questionID → question CASCADE, specPointID → specPoint CASCADE, PK (…));
```

Change from today: `topicIDs` JSON → `questionTopic`; `archivedAt` → `deletedAt`; add answer/solution and the past-paper link.

### People

```sql
student (
  id BLOB PK,
  name TEXT NOT NULL,         -- also the ExcalidrawZ group name
  yearGroup, school, management,      -- "private" | "mytutor" | …
  notes, rapportNotes, hobbies, interests,
  calendarIdentifier TEXT,    -- EventKit calendar / attendee match
  remoteID BLOB, remoteSyncedAt, createdAt, updatedAt, deletedAt
);
studentContact (              -- parents / guardians; 0..n per student
  id BLOB PK, studentID → student CASCADE,
  name, relationship, phone, email, preferredMethod, isPrimary INTEGER NOT NULL DEFAULT 0
);
enrolment (                   -- one row per (student, thing they are studying with you)
  id BLOB PK, studentID → student CASCADE,
  courseID TEXT REFERENCES course,              -- remote mapping, nullable
  specificationID BLOB REFERENCES specification ON DELETE SET NULL,
  subject NOT NULL, level NOT NULL, board, tier, -- denormalised so an enrolment works with no spec imported
  targetGrade TEXT NOT NULL DEFAULT '',
  startedAt, endedAt, isPrimary INTEGER NOT NULL DEFAULT 0,
  notes, remoteID BLOB, createdAt, updatedAt, deletedAt
);
CREATE UNIQUE INDEX enrolment_unique ON enrolment(studentID, subject, level) WHERE deletedAt IS NULL;
```

This replaces `student.subject/level/board/tier/targetGrade/specificationID/specificationIDs`. Target grade moves to the enrolment because it is per qualification.

### Teaching record

```sql
lesson (                      -- replaces lessonSession
  id BLOB PK, studentID → student CASCADE,
  enrolmentID BLOB REFERENCES enrolment ON DELETE SET NULL,   -- which subject this lesson was
  fileID TEXT,                -- ExcalidrawZ file (nullable: lesson may have no board)
  calendarEventID TEXT,       -- EventKit identifier
  startAt NOT NULL, endAt, durationMinutes INTEGER,
  status TEXT NOT NULL DEFAULT 'planned',   -- planned | done | cancelled | no-show
  subjectLine TEXT NOT NULL DEFAULT '',
  plan TEXT NOT NULL DEFAULT '', recap TEXT,  -- recap = AI/tutor summary
  recapJSON TEXT,             -- structured recap payload (topics, homework) if generated
  homeworkSet TEXT NOT NULL DEFAULT '', nextPlan TEXT NOT NULL DEFAULT '',
  transcriptPath TEXT,        -- issue #10
  billable INTEGER NOT NULL DEFAULT 1,
  remoteID BLOB, createdAt, updatedAt, deletedAt
);
CREATE INDEX lesson_student_date ON lesson(studentID, startAt);
CREATE UNIQUE INDEX lesson_file ON lesson(fileID) WHERE fileID IS NOT NULL;

lessonTopic (lessonID → lesson CASCADE, topicID → topic CASCADE,
             minutes INTEGER, note TEXT NOT NULL DEFAULT '', PK (lessonID, topicID));

outcome (                     -- a question shown to a student
  id BLOB PK,
  questionID → question CASCADE,
  studentID → student ON DELETE SET NULL,
  lessonID BLOB REFERENCES lesson ON DELETE SET NULL,
  shownAt NOT NULL,
  result TEXT NOT NULL DEFAULT 'unknown',   -- unknown | right | partial | wrong | skipped
  marksAwarded INTEGER, perceivedDifficulty INTEGER,
  timeSeconds INTEGER,
  note TEXT NOT NULL DEFAULT '',
  remoteID BLOB, createdAt, updatedAt, deletedAt
);
```

`outcome.studentName` and `lessonFileID` go: the lesson row carries the file.

### Progress

```sql
topicProgress (               -- tutor's current judgement per topic; mirrors remote `topics`
  studentID → student CASCADE, topicID → topic CASCADE,
  understanding INTEGER,      -- 1..5
  isFocus INTEGER NOT NULL DEFAULT 0,       -- replaces student.focusTopicIDs
  startedAt, lastRevisedAt, notes,
  remoteID BLOB, updatedAt,
  PRIMARY KEY (studentID, topicID)
);
coverageMark (                -- explicit tick on the spec checklist, independent of outcomes
  studentID → student CASCADE, specPointID → specPoint CASCADE,
  status TEXT NOT NULL,       -- covered | secure | needs-work
  markedAt NOT NULL, lessonID BLOB REFERENCES lesson ON DELETE SET NULL,
  note TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (studentID, specPointID)
);
```

Coverage *derived* from outcomes stays a query; `coverageMark` is the tutor override ("we did this, no question recorded").

### Homework and resources

```sql
deck (                        -- Anki deck catalogue (~/platform/decks/*/output/*.apkg); issue #13
  id BLOB PK, slug TEXT NOT NULL UNIQUE, title, deckType, cardCount INTEGER,
  subject, level, board,
  localPath TEXT, remoteID BLOB, updatedAt
);
assignment (                  -- anything set outside the lesson
  id BLOB PK, studentID → student CASCADE,
  lessonID BLOB REFERENCES lesson ON DELETE SET NULL,     -- set during this lesson
  kind TEXT NOT NULL,         -- deck | paper | questions | worksheet | other
  title TEXT NOT NULL,
  deckID BLOB REFERENCES deck ON DELETE SET NULL,
  pastPaperID TEXT REFERENCES pastPaper ON DELETE SET NULL,
  resourcePath TEXT,
  assignedAt NOT NULL, dueAt, completedAt,
  status TEXT NOT NULL DEFAULT 'set',       -- set | done | overdue | dropped
  score INTEGER, total INTEGER, grade TEXT,
  notes, remoteID BLOB, createdAt, updatedAt, deletedAt
);
assignmentQuestion (assignmentID → assignment CASCADE, questionID → question CASCADE,
                    sortOrder INTEGER NOT NULL DEFAULT 0, PK (assignmentID, questionID));
```

A paper result (today's remote `papers` table) is an `assignment` with `kind = 'paper'` and a score; weak topics go through `outcome`/`topicProgress` rather than free text.

### Housekeeping

```sql
importBatch (id BLOB PK, kind TEXT NOT NULL,   -- spec | paper | questions | legacy-bank | remote
             sourceName, importedAt NOT NULL, itemCount INTEGER, notes);
syncCursor  (remoteTable TEXT PK, lastPulledAt, lastPushedAt);   -- per remote table
meta        (key TEXT PK, value TEXT NOT NULL);                  -- taxonomyVersion, lastBackupAt, …
```

Sync model: pull by `updated_at > lastPulledAt`, match on `remoteID`, push rows whose `updatedAt > remoteSyncedAt`. Soft deletes propagate as `deletedAt`. No outbox table needed while there is one writer (the tutor's Mac).

## What changes from v4

| Today | Target |
|---|---|
| `student.subject/level/board/tier/targetGrade/specificationID/specificationIDs` | `enrolment` rows |
| `student.focusTopicIDs` JSON | `topicProgress.isFocus` |
| `student.parentName/parentContact` | `studentContact` |
| `question.topicIDs` JSON | `questionTopic` |
| `question.archivedAt`, `student.archivedAt` | `deletedAt` |
| `lessonSession` | `lesson` (+ status, calendar, plan, homework, transcript) |
| `outcome.lessonFileID`, `outcome.studentName` | `outcome.lessonID` |
| `topic` only | `topic` + `specPointTopic` |
| nothing | `pastPaper`, `pastPaperQuestion`, `course`, `deck`, `assignment`, `coverageMark`, `importBatch`, `syncCursor`, `meta` |

## Migration order (each its own GRDB migration)

1. `v5-enrolments`: create `enrolment`, `course`; one row per student from the flat columns plus one per extra `specificationIDs` entry; keep old columns until UI is switched.
2. `v6-lessons`: create `lesson` from `lessonSession`; add `outcome.lessonID` resolved via `lessonFileID`.
3. `v7-progress`: `topicProgress` from `focusTopicIDs`; `coverageMark` empty; `studentContact` from parent columns.
4. `v8-question-joins`: `questionTopic` from `topicIDs`; `specPointTopic` empty (filled by Auto-tag); rename `archivedAt` → `deletedAt`.
5. `v9-resources`: `pastPaper`, `pastPaperQuestion`, `deck`, `assignment`, `assignmentQuestion`, `importBatch`, `syncCursor`, `meta`.
6. `v10-drop-flat-columns`: once no reader is left.

Later, if a second writer appears (iPad, web), add a `changeLog` outbox; nothing above has to change for that.
