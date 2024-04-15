#!/bin/bash
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

testCase="genjoin"
engine="thor"
VERBOSE=0
ALL_TESTS_RESULTS=0

usage()
{
    echo "Tool to list execution time statistic of a test or a group (?*) of tests "
    echo "Usage:"
    echo ""
    echo "  $0 <testname> [-e <engine>] [-v] [-h]"
    echo "where:" 
    echo " -e <engine> - Engine where the test executed: Hthor, Thor or Roxie."
    echo "               (Default: Thor)."
    echo " -all        - Use all test results Pass/Fail. Default: Pass only)."
    echo " -v          - Show more logs."
    echo " -h          - This help."
    echo " "
}


contains() {
    item="$1"
    shift
    list=("$@")
    local retVal=0
    local element
    for element in "${list[@]}"
    do
        if [[ "$element" == "$item" ]]
        then
            retVal=1
            break
        fi
    done
    echo $retVal
}

if [[ -z $1 ]]
then
    printf "Missing test case name.\n\n"
    usage
    exit 1
else
    if [[ "$1" != "-h" ]]
    then
        testCase=$1
        shift
    fi
    while [ $# -gt 0 ]
    do
        param=$1
        param=${param//-/}
        upperParam=${param^^}
        #WriteLog "Param: ${upperParam}" "/dev/null"
        case $upperParam in
            ALL) ALL_TESTS_RESULTS=1
                ;;
                
            V) VERBOSE=1
                ;;

            E) shift
                engine=$1
                ;;
                
            H)
                usage
                exit 1
                ;;
                
            *)
                echo "Unknown parameter: ${upperParam}"
                usage
                exit 1
                ;;
        esac
        shift
    done
fi

pushd ~/common/nightly_builds/HPCC/ > /dev/null

[[ $VERBOSE == 1 ]] &&  echo "testCase: $testCase"
[[ $ALL_TESTS_RESULTS -eq 1 ]] && echo "All tests" || echo "Pass only"

declare -A count  min  max sum avg
declare items=()
while read fn
do
    branchName=${fn#*/}
    branchName=${branchName%%/*}
    
    if [[ $ALL_TESTS_RESULTS -eq 1 ]]
    then
        line=$(egrep "(Pass |Fail )$testCase" ${fn})
    else
        line=$(egrep "Pass $testCase" ${fn})
    fi
    
    [[ $VERBOSE == 1 ]] && printf "%s\n%s\n" "$fn" "$line"
    while read tn rt
    do 
        # printf "\nline:\t%s\t%s\n" "$tn" "$rt"
        #echo "tn:$tn"
        item="$tn-$branchName"
        #echo "item: $item"        
        
        retCode=$(contains "$item" "${items[@]}" )
        #echo "retCode:$retCode"
        if [[ $retCode -eq 0 ]]
        then
            #echo "nincs"
            count[$item]=0
            max[$item]=0
            min[$item]=99999
            sum[$item]=0
            items+=( "$item" )
            #printf "items:%s:\n" "${items[@]}"
        fi
        count[$item]=$(( count[$item] + 1 ))
        sum[$item]=$(( sum[$item] + $rt ))
        [[ max[$item] -le $rt ]] && max[$item]=$rt
        [[ min[$item] -gt $rt ]] && min[$item]=$rt
        
    done< <(echo "$line" |  sed -n 's/^\(.*\)[ls] \(.*\)\.ecl\s\-\sW[0-9\-]*\s*(\(.*\) sec)*$/\2 \3/p')
done< <(find . -iname $engine'.2*.log' -type f -print)

printf "%-30s:\t%s\t%s\t%s\t%s\n" "Test" "count" "min(s)" "max(s)" "avg(s)"
echo "----------------------------------------------------------------"
for item in  $( printf "%s\n" "${items[@]}" | sort )
do
    avg[$item]=$(( sum[$item] / count[$item] ))
    printf "%-30s:\t%3d\t%5d\t%5d\t%5d\n" "$item" "${count[$item]}" "${min[$item]}" "${max[$item]}" "${avg[$item]}"
done

popd > /dev/null
