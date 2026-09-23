---
name: scott-pushes-to-github
description: Scott pushes to GitHub himself via GitHub Desktop; Claude commits locally and never pushes or offers to push
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 40ecf8a3-a27c-45fd-ba56-acf9ee0e9857
  modified: 2026-09-09T00:40:52.923Z
---

Scott pushes to GitHub himself, using GitHub Desktop. Claude commits locally only.

**Why:** Scott stated it directly on 2026-09-08 ("you can't push, I have to") after Claude
offered to push. Pushing is outward-facing and he keeps that step in his own hands.

**How to apply:** Commit after every change as usual, then tell Scott the working tree is
clean and how many commits are waiting. Do not run `git push` and do not offer to. Fetching
and merging remote commits locally is fine (it changes nothing on GitHub). Related:
[[git-commit-style]].
