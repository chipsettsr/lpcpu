pslgiergpp10:/home/data # cat datacollect.sh
#!/bin/bash
set -x
TEST_DURATION=600   ## TEST_DURATION is the expected measurement duration in seconds.
COLLECTIONS=1       ## COLLECTIONS is the number of samples of perf record.
NMON_INTERVAL_DB=5  ## NMON_INTERVAL is the sampling interval which nmon uses
NMON_ITERATION=$((TEST_DURATION/NMON_INTERVAL_DB))
PERF_DURATION=20    ## PERF_DURATION is the perf record interval
DATA_PATH=/home/data
NMONPATH=/usr/bin

TS=`date '+%y%m%d-%H%M%S'`

DATA_DIR=$DATA_PATH/$TS

mkdir -p $DATA_DIR
chmod 777 $DATA_DIR

monitors_only(){

## setup lpcpu by downloading in /home/IBM
#cd /home/IBM

#download lpcpu if it does not exist
#if [ ! -d lpcpu ]; then
#   git clone https://github.com/open-power-sdk/lpcpu
#fi

cd $DATA_DIR

## Start nmon
NMONPID=/tmp/nmon.pid
$NMONPATH/nmon -p -c $NMON_ITERATION -s ${NMON_INTERVAL_DB} -F ${DATA_DIR}/nmon.db.out > ${NMONPID}

##start lpcpu as well. It captures all configuration, iostat with extended metrics and interrupts information,lparstat, numactl and all kernel configs
#capture all configuration information. This runs for the entire duration of the test
/home/data/lpcpu-master/lpcpu.sh duration=${TEST_DURATION} output_dir=${DATA_DIR} &
lparstat $NMON_INTERVAL_DB $NMON_ITERATION > ${DATA_DIR}/lparstat.out &
sleep 5                                            ## Sleep for 5s after starting lpcpu as it has to finish the config collection


echo "Started lpcpu, nmon and 24x7 . This runs for $TEST_DURATION s"
}




collect_profile_pmu() {

#SLEEPTIME=$((TEST_DURATION/COLLECTIONS))            ## Intervals
ulimit -n 1000000                                   ## Change the ulimit values for perf

#collect profile -  runs for 5 minutes so doing 1 iteration. Using -c option to reduce the samples count . This usually completes within 5 minutes
for (( c=1; c<=$COLLECTIONS; c++ ))
do
        TS_COLLECT=`date '+%y%m%d-%H%M'`
        /usr/bin/perf record -k CLOCK_MONOTONIC_RAW -a -g -e cycles -o ${DATA_DIR}/perf.rec.${TS}.${TS_COLLECT}.data --proc-map-timeout 60000 sleep $PERF_DURATION

done


for (( c=1; c<=$COLLECTIONS; c++ ))
do
              ##capture L2 miss profiles
              /usr/bin/perf record -k CLOCK_MONOTONIC_RAW -a -d -g -e r401e8 -o ${DATA_DIR}/perf.L2miss --proc-map-timeout 60000 sleep 10
              ##capture L3 miss profiles
              /usr/bin/perf record -k CLOCK_MONOTONIC_RAW -a -d -g -e r201e4 -o ${DATA_DIR}/perf.L3miss --proc-map-timeout 60000 sleep 10
              ##capture larx fin profile
              /usr/bin/perf record -k CLOCK_MONOTONIC_RAW -a -d -g -e r40116 -o ${DATA_DIR}/perf.larx --proc-map-timeout 60000 sleep 10
              ##capture c2c record
              /usr/bin/perf c2c record -- -g -a -o ${DATA_DIR}/perf.c2c --proc-map-timeout 60000 sleep 10

done


# Post this - all data can be collected after the run

## Kill nmon
#/bin/kill -s USR2 `cat ${NMONPID}`

#mv /tmp/lpcpu* ${DATA_DIR}/


########################################
#
# When you are certain the test is done
#
########################################
 cd $DATA_DIR
## Capture all kernel symbols
 cat /proc/kallsyms > ./kallsyms

 for i in perf.rec*
 do
  /usr/bin/perf report -g none --no-children -i $i  > ${i}.top.txt
  /usr/bin/perf report --no-children --call-graph=graph,0 -i $i  > ${i}.callgraph.txt
  /usr/bin/perf report --no-children -i $i -s dso,symbol > ${i}.symbol.txt
  /usr/bin/perf c2c report --full-symbols -g -i perf.c2c > perf.c2c.txt
 done

        ## Capture all symbols for local post processing
        /usr/bin/perf archive ${DATA_DIR}/perf.rec.${TS}.${TS_COLLECT}.data
        sleep 10

}

package_data() {
cd $DATA_PATH
sleep $TEST_DURATION
tar -cvf toibm_DB_$TS.tar ${DATA_DIR}
gzip toibm_$TS.tar

echo "*********************Data collection & Processing complete. Send toibm_$TS.tar or gz to IBM *************************"
exit 0
}

usage(){

    echo "usage : ${0##*/} [  -M  ] [  -P  ] [ -A  ]

    -A      Collect all data including monitors, profiles, pmu and nest
    -M      Enable monitors only - lpcpu, nmon and nest
    -P      Collect profiles and pmu only

    Example : ${0##*/} -M "

exit 0
}

    echo "usage : ${0##*/} [  -M  ] [  -P  ] [ -A  ]"

while [[ $# -gt 0 ]]; do
      key="$1"

      case $key in
        -A)
            monitors_only
            #sleep $SLEEP_TO_PEAK
            collect_profile_pmu
            package_data
            ;;
        -M)
            monitors_only
            sleep $TEST_DURATION
            sleep 60
            package_data
            ;;
        -P)
            collect_profile_pmu
            package_data
            ;;
         *)
            usage
            ;;
        esac
done
