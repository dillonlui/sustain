# Runtime State Machine

## High Level States

```text
NO SONG PLAYING
        ↓
SONG STARTING
        ↓
SONG PLAYING
```

---

## Pad State

```text
OFF
 ↓
FADING_IN
 ↓
PLAYING
 ↓
FADING_OUT
 ↓
OFF
```

---

## Click State

```text
OFF
 ↓
COUNTOFF
 ↓
PLAYING
 ↓
OFF
```

---

## Start Song

When no song is currently playing:

```text
Pad Fade In
↓
Countoff
↓
Click Starts
```

---

## Start Song While Another Song Is Playing

```text
Stop Current Click
↓
Crossfade Pads
↓
Countoff
↓
Start New Click
↓
New Song Active
```

---

## Stop

```text
Click Off Immediately
↓
Pad Fade Out
↓
No Song Playing
```

---

## Start Click

If click is currently off:

```text
Countoff
↓
Click Starts
```

Never start click without a countoff.

---

## Next Song

Changes only:

```text
Cued Song
```

No audio changes occur.

---

## Sacred Rule

Current playback remains active until transition validation succeeds.