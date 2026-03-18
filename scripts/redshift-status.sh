#!/bin/sh
redshift -l 52.37:4.90 -p 2>/dev/null | awk '
  /Period/           { p = $2 }
  END {
    if (p == "Daytime") printf "<fn=1><fc=#e0af68></fc></fn>"
    else if (p == "Night") printf "<fn=1><fc=#7aa2f7>󰖔</fc></fn>"
    else if (p) printf "<fn=1><fc=#e0af68></fc></fn>"
    else print "<fc=#565f89>off</fc>"
  }
'
