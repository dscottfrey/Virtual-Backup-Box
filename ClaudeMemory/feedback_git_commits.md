---
name: Git commit style
description: Every commit must include the reason for the change and Scott's original prompt/request in the commit message
type: feedback
originSessionId: ffbd3f8e-f5af-493e-a0fa-12dc5539cd73
---
Every git commit must include the reason for the change AND Scott's original prompt/request that triggered it in the commit message body. Not just what changed — why it changed and what Scott asked for.

**Why:** Scott needs to be able to trace any change back to the request that caused it, for debugging and reverting.

**How to apply:** After every code change, commit immediately with a message structured as: summary line, then Scott's prompt quoted in the body, then what was changed and why.
