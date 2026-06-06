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
  padPack
```

Example:

```yaml
title: Goodness of God
defaultKey: G
defaultBPM: 72
timeSignature: 6/8
padPack: Warm
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

Overrides song defaults.

```yaml
SetlistEntry:
  songId
  keyOverride?
  bpmOverride?
```

---

## Pad Pack

Folder-based pad asset collection.

```text
Warm/
├── C.wav
├── D.wav
├── E.wav
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