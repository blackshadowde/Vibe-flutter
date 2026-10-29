#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Release notes describe Vibe in its own words: removes "X-style" / "X-like"
comparisons with other apps (stdin -> stdout)."""
import re
import sys

NAMES = (r"(?:Telegram|Slack/Reddit|Slack|Reddit|WhatsApp|iMessage|Discord|"
         r"Hike|Vibgram|Instagram|Snapchat)")

text = sys.stdin.read()
text = text.replace("A Discord-style, end-to-end encrypted messenger",
                    "An end-to-end encrypted messenger")
text = text.replace("Chat looks more like Discord:", "Chat looks tighter:")
text = text.replace("Looks: Vibe (Discord),", "Looks: Vibe (default),")
text = re.sub(r"\s*\(" + NAMES + r"[ -](?:style|like)\)", "", text)
text = re.sub(r"\b" + NAMES + r"[ -](?:style|like)\s+", "", text)
text = re.sub(r"\b" + NAMES + r"[ -](?:style|like)\b", "", text)
sys.stdout.write(text)
