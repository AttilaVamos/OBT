OUTTER_LOOP_COUNT=2
INNER_LOOP_COUNT=10
TARGET="hthor"
TEST_SET="02bb_sort.ecl"

clear

ulimit -s 81920
ulimit -u 524288
ulimit -n 524288
ulimit -c unlimited

echo "ulimits: $( ulimit -a | egrep '[pr]ocesses|open|stack|core' )"

printf " Outter loop         : %6d\n" "${OUTTER_LOOP_COUNT}"
printf " inner loop          : %6d\n" "${INNER_LOOP_COUNT}"
printf " number of executions: %6d\n" "$(( $OUTTER_LOOP_COUNT * $INNER_LOOP_COUNT ))"
printf " Test set            : '%s'\n\n" "${TEST_SET}"

pushd ~/build/CE/platform/HPCC-Platform/testing/regress/

for (( i=1; i<=$OUTTER_LOOP_COUNT; i++ ))
do 
    echo "Loop:$i" 
    sudo /etc/init.d/hpcc-init start

    for (( j=1; j <=$INNER_LOOP_COUNT; j++ ))
    do 
        echo "Exec:$j"
        suffix=$( printf "F542D241_L%03d_E%02d" "$i" "$j" )
        echo $suffix

        CMD="./ecl-test query -t ${TARGET} --suiteDir /home/vamosax/perftest/PerformanceTesting/PerformanceTesting --timeout -1 -fthorConnectTimeout=36000 -e stress --pq 1 --flushDiskCache --flushDiskCachePolicy 1 --jobnamesuffix ${suffix} ${TEST_SET}"

	${CMD}

        echo "-------------------------------------"
    done

    sudo /etc/init.d/hpcc-init stop
    sudo service dafilesrv stop

    echo "======================================"
done

popd

sudo /etc/init.d/hpcc-init start


echo "End."
