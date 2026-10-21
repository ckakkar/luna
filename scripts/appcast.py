#!/usr/bin/env python3
"""Writes the Sparkle appcast for one release (run by .github/workflows/release.yml).

    scripts/appcast.py --version 0.1.42 --build 42 --url https://…/Luna.zip \
        --signature "sparkle:edSignature=\"…\" length=\"…\"" --notes notes.md > appcast.xml

--signature is what Sparkle's sign_update prints for the archive.
"""
import argparse
import html
from email.utils import formatdate

parser = argparse.ArgumentParser()
parser.add_argument("--version", required=True)
parser.add_argument("--build", required=True)
parser.add_argument("--url", required=True)
parser.add_argument("--signature", required=True)
parser.add_argument("--notes", required=True)
parser.add_argument("--minimum-system", default="14.0")
args = parser.parse_args()

with open(args.notes, encoding="utf-8") as f:
    lines = [line[2:].strip() for line in f if line.startswith("- ")]
items = "\n".join(f"          <li>{html.escape(line)}</li>" for line in lines) or "          <li>Maintenance release</li>"

print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Luna</title>
    <link>https://github.com/ckakkar/luna</link>
    <item>
      <title>Luna {args.version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{args.build}</sparkle:version>
      <sparkle:shortVersionString>{args.version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{args.minimum_system}</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <ul>
{items}
        </ul>
      ]]></description>
      <enclosure url="{html.escape(args.url)}" type="application/octet-stream" {args.signature.strip()} />
    </item>
  </channel>
</rss>""")
