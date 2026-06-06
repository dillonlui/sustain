# WorshipPad Operating Charter

## Mission

WorshipPad exists to help worship leaders confidently run ambient pads, click tracks, and countoffs during live worship services.

The product should reduce cognitive load, increase confidence, and minimize technical complexity during rehearsals and Sunday services.

The product should feel more like a reliable instrument than production software.

---

## Primary User

Volunteer worship leader.

Typically:

- Leads vocals
    
- Plays guitar or keys
    
- Has limited rehearsal time
    
- Is moderately technical
    
- Is not an audio engineer
    

---

## Core Job To Be Done

"I need pads and click to run reliably during worship without thinking about the technology."

---

## Product Principles

### Reliability > Features

If forced to choose:

- Less capable but more reliable wins.
    

### Clarity > Flexibility

The app should communicate clearly what is happening.

### Speed > Customization

The app should optimize for common workflows.

### Boring > Clever

Favor predictable behavior over powerful behavior.

### Explicit > Automatic

The app should never surprise the user.

---

## Worship Service Philosophy

The app does not:

- Detect song endings
    
- Advance automatically
    
- Manage arrangements
    
- Understand verses or choruses
    

The worship leader remains in control at all times.

---

## Engineering Principles

### Native First

Prefer:

- SwiftUI
    
- Core Audio
    
- AVFoundation
    
- Native macOS conventions
    

Avoid unnecessary abstractions.

### Offline First

The application must work without internet access.

### Validate Before Failure

The app should detect:

- Missing pad assets
    
- Missing outputs
    
- Missing devices
    

before playback begins whenever possible.

---

## Sacred Reliability Rule

Never destroy a valid playing state until the next state is confirmed valid.

If a transition fails:

Current playback continues.