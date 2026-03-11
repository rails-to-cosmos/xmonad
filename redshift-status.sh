#!/bin/sh
redshift -l 52.37:4.90 -p 2>/dev/null | awk '
  /Period/           { p = $2 }
  /Color temperature/ { t = $3 }
  END { if (p) printf "%s %s", p, t; else print "off" }
'
