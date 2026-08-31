#!/bin/bash

#Takes 3 Arguments, TESTNAME has to be given, others fall back to default
TESTNAME=$1 #will be added to the filename
NUMJOBS=${2:-1} #dictates how many jobs/benchmark tests will be run
MODE=${3:-"p"} #p for parallel jobs, s for serial jobs

FILENAME="${TESTNAME}_results_$(date +%d_%m_%Y_%H_%M).txt"
echo "Writing results to $FILENAME"

if [ "$MODE" = "p" ]; then
    printf "tests run in parallel\nelapsed time us\n" > "$FILENAME"
    for i in $(seq 1 "$NUMJOBS"); do
    escript bench_script.erl "$FILENAME" &
    done
elif [ "$MODE" = "s" ]; then
    printf "tests run in series\nelapsed time us\n" > "$FILENAME"
    for i in $(seq 1 "$NUMJOBS"); do
    escript bench_script.erl "$FILENAME"
    done
else
    echo "Unknown mode: $MODE"
    exit 1
fi

wait
echo "All ${NUMJOBS} jobs finished"