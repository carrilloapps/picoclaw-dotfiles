#!/usr/bin/env python3
"""Setup knowledge base directory and AGENT.md instructions."""
import os
import sys

if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(__file__))
from connect import connect, run


KNOWLEDGE_SECTION = """

## Knowledge Base (Persistent Context)

When the user says **"guarda el contexto"**, **"documenta esto"**, **"arde el contexto"**,
**"save this"**, or any similar instruction to persist knowledge:

1. Create a `.md` file in `~/.picoclaw/workspace/knowledge/`
2. Name it descriptively: `<topic>-<YYYYMMDD>.md` (e.g., `router-setup-20260328.md`)
3. Include: what was done, commands used, results, and any gotchas
4. Confirm to the user that the context was saved

**Commands:**
```bash
# List all saved knowledge
ls ~/.picoclaw/workspace/knowledge/

# Read a specific file
cat ~/.picoclaw/workspace/knowledge/<filename>.md

# Search across all knowledge
grep -r "keyword" ~/.picoclaw/workspace/knowledge/
```

**Format for each knowledge file:**
```markdown
---
title: What was done
date: YYYY-MM-DD
topic: networking | automation | config | security | ...
---

## Context
Brief description of what the user asked for.

## Steps Taken
1. Step one...
2. Step two...

## Commands Used
(code block with commands)

## Results
What happened.

## Notes / Gotchas
Any important caveats.
```

This is your **persistent memory** for operational procedures. When the user asks
"how did we do X?" or "what was the command for Y?", search this directory first.
"""


def main():
    ssh = connect()

    # Create knowledge directory
    run(ssh, "mkdir -p ~/.picoclaw/workspace/knowledge")
    print("Created ~/.picoclaw/workspace/knowledge/")

    # Create index
    sftp = ssh.open_sftp()
    index = "# PicoClaw Knowledge Base\n\nPersistent context files created by PicoClaw.\n"
    with sftp.open('/data/data/com.termux/files/home/.picoclaw/workspace/knowledge/README.md', 'w') as f:
        f.write(index)

    # Update AGENT.md
    with sftp.open('/data/data/com.termux/files/home/.picoclaw/workspace/AGENT.md', 'r') as f:
        agent = f.read().decode('utf-8')

    if 'Knowledge Base' not in agent:
        idx = agent.find('## Skills Available')
        if idx > 0:
            agent = agent[:idx] + KNOWLEDGE_SECTION + "\n" + agent[idx:]
        else:
            agent += KNOWLEDGE_SECTION

        with sftp.open('/data/data/com.termux/files/home/.picoclaw/workspace/AGENT.md', 'w') as f:
            f.write(agent)
        print("AGENT.md: Knowledge Base section added")
    else:
        print("AGENT.md: Knowledge Base already present")

    sftp.close()

    # Check WhatsApp build
    out, _ = run(ssh, "ls -la ~/picoclaw-wa.bin 2>/dev/null || echo STILL_BUILDING")
    print(f"\nWhatsApp build: {out.strip()}")

    ssh.close()


if __name__ == "__main__":
    main()
