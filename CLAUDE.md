# Virtual Backup Box — Claude Code Instructions

**Project:** Virtual Backup Box
**Platform:** iOS 17+ / iPadOS 17+
**Language:** Swift / SwiftUI

---

## Before You Write a Single Line of Code

Read `Docs/00_OVERALL_DIRECTIVE.md` first — every session, every time.
It contains the authoritative spec, module breakdown, open questions, and decisions already made.
Do not proceed on any module until you have read the section that covers it.

---

## The Four Coding Rules (Non-Negotiable)

### §6.1 — Simplest Solution That Works
If Apple's SDK provides it, use it. Do not reach for a third-party library or a clever custom
solution when a straightforward one exists. When two approaches work, pick the simpler one.

### §6.2 — Comments Are Part of the Deliverable
- Every file gets a header comment explaining what it does and why it exists.
- Every function gets a plain-English explanation of what it does (legible to a careful non-developer).
- When a working solution was reached after iteration — after something failed — the comment must
  record what was tried, what failed, and *why* the final approach works. This is regression
  protection. Future-Claude (or Scott) needs to know why the code is the way it is.
- Stale comments that no longer match the code are deleted immediately. Never leave them in place.

### §6.3 — One File, One Job
- No file should exceed ~200 lines.
- Views contain only UI. Business logic lives in ViewModels or services.
- Models contain only data shape. No UI references, no network calls.
- If a file is doing two jobs, split it before adding more code.

### §6.5 — Work With Apple, Not Against It
If an approach requires fighting SwiftUI or UIKit in a non-trivial way — custom layout hacks,
overriding internal behaviour, working around framework bugs — **stop**. Flag it to Scott using
this exact language: *"This approach requires fighting the framework."* Describe the problem and
propose an alternative. Scott decides whether to proceed. Do not write the code first and flag
it later.

---

## Git Commits

- **Commit after every change.** Do not batch multiple changes into one commit.
- Every commit message must include:
  1. A clear summary line describing what changed.
  2. Scott's original prompt/request that triggered the change (quoted in the body).
  3. What was changed and why.
- This allows any change to be traced back to the request that caused it and reverted if necessary.

---

## Working Style

- Summarise what you're going to build and in what order **before** writing any code.
- Surface open questions explicitly. Do not pick an answer silently.
- When something in a directive is ambiguous, say so. Don't guess.
- Scott is not a developer. All explanations must be in plain English.
