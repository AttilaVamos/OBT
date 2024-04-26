#!/bin/bash
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

TEST_CASE=""
ENGINE="thor"
VERBOSE=0
DEBUG=0
SEPARATOR=0
GROUP_BY_DATE=0
CSV_OUTPUT=0

usage()
{
    echo "Tool to list the result of a test or a group (?*) of tests "
    echo "Usage:"
    echo ""
    echo "  $0 <testname> [-e <engine>] [-all] [-addsep] [-group-by-date] [-csv] [-v] [-h]"
    echo "where:" 
    echo " <testname>     - Name of individual test case or a group of test cases "
    echo "                  using '?' and/or '*', but in this case the test name should"
    echo "                  be enclosed by the single quote (') character to avoid" 
    echo "                  shell expansion. The '*' reports all test cases."
    echo "                  It can use to process only one version of test case. In this"
    echo "                  case the test name should enclose with (') and need to use same"
    echo "                  format as is logged in result file like:"
    echo "                   'stresstext.ecl ( version: multiPart=true )' "
    echo " -e <engine>    - Engine where the test executed: Hthor, Thor or Roxie."
    echo "                   Default: Thor."
    echo " -addsep        - Add separator line betwent tests with stat and new header"
    echo "                  Default is: no."
# TO-DO if needed
#    echo " -group-by-date - Report each day separately. Default is no, grouped by test."
#    echo "                    (Not implemented yet.)"
#    echo " -csv           - Output is CSV formatted. Default is no (the output is a"
#    echo "                  formatted text."
#    echo "                    (Not implemented yet.)"
    echo " -v             - Show more logs."
    echo " -d             - Show debug logs."
    echo " -h             - This help."
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
        TEST_CASE=$1
        shift
    fi
    while [ $# -gt 0 ]
    do
        param=$1
        param=${param//-/}
        upperParam=${param^^}
        [[ $DEBUG == 1 ]] && echo "Param: ${upperParam}"
         
        case $upperParam in
           
            ADDSEP)
                SEPARATOR=1
                ;;
                
#            GROUPBYDATE)
#                GROUP_BY_DATE=1
#                ;;
#
#            CSV)
#                CSV_OUTPUT=1
#                ;;
    
            V) VERBOSE=1
                ;;
                
            D) DEBUG=1
                ;;

            E) shift
                ENGINE=$1
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

if [[ -f ./settings.sh && ( "$OBT_ID" =~ "OBT" ) ]]
then
    echo "We are in OBT environment"
    . ./settings.sh
    LOG_DIR=$STAGING_DIR_ROOT
else
    echo "Non OBT environment, like local VM/BM"
    LOG_DIR="$HOME/common/nightly_builds/HPCC/"
fi

pushd $LOG_DIR > /dev/null

printf "Test case    : '$TEST_CASE'\n"
printf "Engine       : '$ENGINE'\n"
printf "Group by     : %s\n" "$( [[ $GROUP_BY_DATE -eq 1 ]] && echo "Date" || echo "Test case")"
printf "Output is    : %s\n" "$( [[ $CSV_OUTPUT -eq 0 ]] && echo "Formatted text" || echo "CSV")"

maxTestNameLen=0
declare -A testStatus testNames testDates testTimes branches
declare items=()
while read fn
do
    # Process the filename './candidate-9.6.x/2024-04-22/OBT-AWS02-CentOS_Linux_7/07-18-58/CE/platform/test/roxie.24-04-22-10-21-53.log'
    # to extract branch name, test date and time.
    #
    branchName=${fn#*/}
    branchName=${branchName#candidate-}
    branchName=${branchName%%/*}
    [[ $DEBUG == 1 ]] && echo "branchName: '$branchName'"
    
    testDate=${fn#*/}
    testDate=${testDate#candidate-}
    testDate=${testDate#$branchName/}
    testTime=$testDate
    testDate=${testDate%%/*}
    [[ $DEBUG == 1 ]] && echo "testDate: '$testDate'"
    
    testTime=${testTime#$testDate/}
    testTime=${testTime#*/}
    testTime=${testTime%%/*}
    [[ $DEBUG == 1 ]] && echo "testTime: '$testTime'"

    # Need to escape the '(' to '\(' and ')' to '\)' for grep
    escapedTestCase=$( echo $TEST_CASE | sed -e 's/(/\\(/g' -e 's/)/\\)/g')
    line=$(egrep "(Pass |Fail )$escapedTestCase" ${fn})
    
    versionedTestCase=$( echo "${line}" | egrep -c 'version:')
     [[ $DEBUG == 1 ]] && echo "versionedTestCase: $versionedTestCase"
    
    [[ $DEBUG == 1 ]] && printf "File: '%s'\n\tLine: %s\n" "$fn" "${line[@]}"
    
    while read status tName version
    do 
        [[ $DEBUG == 1 ]] && printf "\nline:\ttest name:%s\tstatus:%s\tversion'%s'\n" "$tName" "$status" "$version"

        if [[ $versionedTestCase -gt 0 ]]
        then
            verTag="$( echo "$version" | tr -d ' []:' | tr '=,' '-_')"
            [[ $DEBUG == 1 ]] && echo "version tag: '$verTag'"
            verTag=${verTag##version}
            [[ $DEBUG == 1 ]] && echo "version tag: '$verTag'"
            
            # Create a unique key
            item="$tName-$verTag-$branchName-$testDate-$testTime"
            [[ $DEBUG == 1 ]] && echo "item: $item"        
            
            testName="$tName-$verTag"
            [[ $DEBUG == 1 ]] && echo "testName: $testName"        
        else
            # Create a unique key
            item="$tName-$branchName-$testDate-$testTime"
            [[ $DEBUG == 1 ]] && echo "item: $item"        
            
            testName="$tName"
            [[ $DEBUG == 1 ]] && echo "testName: $testName"        
        fi
    
        [[ ${#testName} -gt $maxTestNameLen ]] && maxTestNameLen=${#testName}
    
        retCode=$(contains "$item" "${items[@]}" )
        [[ $DEBUG == 1 ]] && echo "contains() returned with $retCode"
         
        if [[ $retCode -eq 0 ]]
        then
            items+=( "$item" )
        fi
        testStatus[$item]="$status"
        testNames[$item]="$testName"
        testDates[$item]="$testDate"
        testTimes[$item]="$testTime"
        branches[$item]="$branchName"
        
    done< <( [[ $versionedTestCase -gt 0  ]] && (echo "$line" | tr '()' '[]' | sed -n 's/^\s*.*\([PF].*\)\s\(.*\)\.ecl\s*\(\[.*\]\)\s.*$/\1 \2 \3/p')  \
                                                                        || (echo "$line" | tr '()' '[]' | sed -n 's/^\s*.*\([PF].*\)\s\(.*\)\.ecl\s*.*$/\1 \2/p') \
                    )

done< <(find . -iname $ENGINE'.2*.log' -type f -print)

[[ ($VERBOSE -eq 1) || ($DEBUG == 1) ]] && echo "maxTestNameLen: $maxTestNameLen"
items=( $( printf "%s\n" "${items[@]}" | sort ) )
[[ $DEBUG == 1 ]] && printf "items:%s:\n" "${items[@]}"

prevTestName=${testNames[${items[0]}]}
prevBranch=${branches[${items[0]}]}
[[ ($VERBOSE == 1) || ($DEBUG == 1) ]] && echo "testName: '$prevTestName'"
testCount=0
pass=0
fail=0
echo ""
printf "%-*s:  %-8s  %-10s  %-6s\n" "$maxTestNameLen" "Test"  "Branch"  "Date" "Result" 
printf "%.*s\n"  "$(( $maxTestNameLen + 32 ))"  "---------------------------------------------------------------------------------"
for item in  ${items[@]}
do
    testName=${testNames[$item]}
    branch=${branches[$item]}
    if [[ ( ("$testName" != "$prevTestName") || ("$branch" != "$prevBranch" ) ) && ($SEPARATOR -eq 1) ]]
    then
        prevTestName=$testName
        prevBranch=$branch
        printf "%-*s %4d run, Pass:%4d, Fail:%4d, Pass ratio: %d%%\n\n" "5" " " "$testCount" "$pass" "$fail" "$(( ( $pass * 100) / $testCount ))"
        testCount=0
        pass=0
        fail=0
        
        # repeat the header
        echo ""
        printf "%-*s:  %-8s  %-10s  %-6s\n" "$maxTestNameLen" "Test"  "Branch"  "Date" "Result" 
        printf "%.*s\n"  "$(( $maxTestNameLen + 32 ))"  "---------------------------------------------------------------------------------"
    fi
    printf "%-*s:  %8s  %10s  %6s\n"  "$maxTestNameLen" "${testNames[$item]}" "${branches[$item]}" "${testDates[$item]}"   "${testStatus[$item]}"
    testCount=$(( testCount + 1))
    [[  "${testStatus[$item]}" == "Pass" ]] && pass=$(( $pass + 1 )) || fail=$(( $fail + 1 ))
done

printf "%-*s %4d run, Pass:%4d, Fail:%4d, Pass ratio: %d%%\n\n" "5" " " "$testCount" "$pass" "$fail" "$(( ( $pass * 100) / $testCount ))"

popd > /dev/null
