# Lindon Academy

A macOS whiteboard for one-to-one maths and science tutoring, forked from
[ExcalidrawZ](https://github.com/chocoford/ExcalidrawZ) (a native Excalidraw
client by Chocoford). The Excalidraw canvas, file management, file history,
library, search and presentation mode come from upstream. The tutoring
features are ours.

## What it does

- **Lesson Draw** – one click creates the lesson file for the student on the
  calendar now (or next), carries the previous board over as a recap frame, and
  can summarise last time with your own Anthropic key.
- **Students** – a local TutorKit database (SQLite via GRDB) of students,
  enrolments, contacts and lesson history, synced two-way with the TutorKit
  Supabase project.
- **MyTutor import** – Lessonspace room exports (Fabric.js ZIPs) become
  Excalidraw boards.
- **Past Paper mode** – Insert PDF can split an exam paper into one image per
  question.
- **Maths Tools** – interactive triangles, compass arcs and a protractor in the
  inspector.
- **Inline LaTeX** – `$...$` typed into text elements renders as maths; the
  Math Input sheet covers formulas, function plots and geometry templates.
- **Viewer window** – a read-only mirror of the canvas for a second display,
  also served to browsers on the local network for a kiosk.
- **Daily board** – `tools/daily-board` builds a dated kiosk board from a
  Google Sheet.

Upstream features that are not part of this build: iOS/iPadOS, AI chat and
MCP, collaboration rooms, third-party cloud storage providers, the App Store
subscription, Sparkle updates, screen annotation and the question bank (which
now lives in its own app).

## Building

Xcode 27, macOS only. The web bundle and local signing config are not in the
repository:

1. Clone `chocoford/excalidraw` (branch `ExcalidrawZ-core`), run
   `yarn install --frozen-lockfile && yarn build`, and copy
   `excalidraw-app/build/` to `ExcalidrawZ/Resources/excalidraw-latest`.
2. Create `ExcalidrawZ/Resources/Videos` (may be empty).
3. Add `Config/Overrides.xcconfig` with your `DEVELOPMENT_TEAM`, a stub
   `Config/Secrets.plist`, and `Config/Overrides.entitlements` without the
   iCloud entitlements.
4. Build the `ExcalidrawZ` scheme. The product is `Lindon Academy.app`; the
   Swift module is still `ExcalidrawZ`.

The TutorKit package builds and tests on its own with `swift test` in
`Packages/TutorKit`.

## Licence

MIT, as upstream. See `LICENSE`.
