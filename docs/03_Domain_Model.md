# Domain Model

## Song

Reusable song definition.

```yaml
Song:
  id
  title
  defaultKey
  defaultBPM
  timeSignature
```

Example:

```yaml
title: Goodness of God
defaultKey: G
defaultBPM: 72
timeSignature: 6/8
```

---

## Setlist

A collection of songs for a service.

```yaml
Setlist:
  id
  title
  entries[]
```

---

## Setlist Entry

References one canonical library song. Key, BPM, and time signature live on `Song`, so edits
from either Song Library or Live Service update every occurrence consistently.

```yaml
SetlistEntry:
  songId
```

---

## Included Pad Library

V1 uses one included pad bundle only. Each supported musical key maps to one included audio file.

```text
Resources/Pads/
├── C Major.mp3
├── Db Major.mp3
├── D Major.mp3
└── ...
```

---

## Runtime Session

```yaml
RuntimeSession:
  playingSong
  cuedSong
  padState
  clickState
```

---

## Core Concept

Playing Song ≠ Cued Song

The currently audible song and the selected next song are separate concepts.
