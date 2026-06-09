#!/bin/bash
set -euo pipefail
DIR="$1"

{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
  echo '  <channel>'
  echo '    <title>Pluricode</title>'
  [ -f "$DIR/stable.item.xml" ] && cat "$DIR/stable.item.xml"
  [ -f "$DIR/nightly.item.xml" ] && cat "$DIR/nightly.item.xml"
  echo '  </channel>'
  echo '</rss>'
} > "$DIR/appcast.xml"
