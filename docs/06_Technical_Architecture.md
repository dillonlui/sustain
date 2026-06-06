# Technical Architecture

## Platform

macOS only.

---

## Frameworks

### UI

SwiftUI

### Audio

AVFoundation

Core Audio

### Persistence

SwiftData or SQLite

### File Access

Native macOS filesystem

---

## Audio Model

Pads:

- User supplied WAV files
    
- Loop continuously
    

Click:

- Dynamically generated
    
- BPM driven
    

Countoff:

- Spoken samples
    
- Derived from time signature
    

---

## Storage

Local only.

No backend.

No cloud.

No authentication.

---

## Future Rule

Every technical decision must answer:

"Does this improve reliability for Sunday morning?"