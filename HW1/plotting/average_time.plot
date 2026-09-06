set terminal pdfcairo size 14,8 enhanced font "Arial,33"
set output "average_time.pdf"

set title "Average Total Time for 100 Requests, by Configuration\n(5 benchmark scripts per configuration)" font "Arial,35"
set ylabel "Time (ms)"
set xlabel "Configuration" offset 0,0
set boxwidth 0.1
set style fill solid border -0.7
unset key
set xtics scale 0 font "Arial,26" offset 0,-0.5 rotate by -45.0 offset 0,0.25
set bmargin 7
set linetype 1 lc rgb "#808080"   # blue
set linetype 2 lc rgb "#4C72B0"   # blue
set linetype 3 lc rgb "#55A868"   # green
set linetype 4 lc rgb "#C44E52"   # red

set label "Serial Baseline"        at 1,   graph -0.34 center front font "Arial,28"
set label "Parallel — No Load"     at 1.315, graph -0.34 center front font "Arial,28"
set label "Parallel — CPU Load"    at 1.74,   graph -0.34 center front font "Arial,28"

plot 'data.dat' using 1:4:2:xtic(3) with boxes lc variable notitle, \
     ''         using 1:($4+500):(sprintf("%.0f ms", $4)) with labels font "Arial,20" notitle