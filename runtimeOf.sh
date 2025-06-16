#!/bin/bash
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

testCase=""
engine="thor"
VERBOSE=0
DEBUG=0
ALL_TESTS_RESULTS=0
SEPARATOR=0

usage()
{
    echo "Tool to list execution time statistic of a test or a group (?*) of tests "
    echo "Usage:"
    echo ""
    echo "  $0 <testname> [-e <engine>] [-all] [-addsep] [-v] [-d] [-h]"
    echo "where:" 
    echo " <testname>  - Name of individual test case or a group of test cases "
    echo "               using '?' and/or '*', but in this case the test name should"
    echo "               be enclosed by the single quote (') character to avoid" 
    echo "               shell expansion. The '*' reports all test cases."
    echo "               It can use to process only one version of test case. In this"
    echo "               case the test name should enclose with (') and need to use same"
    echo "               format as is logged in result file like:"
    echo "               'stresstext.ecl ( version: multiPart=true )' "
    echo " -e <engine> - Engine where the test executed: Hthor, Thor or Roxie."
    echo "               Default: Thor."
    echo " -all        - Use all test results Pass/Fail. Default: Pass only."
    echo " -addsep     - Add separator line betwent tests. Default: no"
    echo " -v          - Show more logs."
    echo " -d          - Show debug logs."
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
            ALL) 
                ALL_TESTS_RESULTS=1
                ;;
            
            ADDSEP)
                SEPARATOR=1
                ;;
            
            V) VERBOSE=1
                ;;
                
            D) DEBUG=1
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

printf "Test case    : '$testCase'\n"
printf "Result filter: "
[[ $ALL_TESTS_RESULTS -eq 1 ]] && echo "All tests" || echo "Pass only"

maxTestNameLen=0
declare -A count  min  max sum avg testNames failed passed
declare items=()
while read fn
do
    branchName=${fn#*/}
    branchName=${branchName#candidate-}
    branchName=${branchName%%/*}
    [[ $DEBUG == 1 ]] && printf "Branch: %s\n" "$branchName"
    
    # Need to escape the '(' to '\(' and ')' to '\)' for grep
    escapedTestCase=$( echo $testCase | sed -e 's/(/\\(/g' -e 's/)/\\)/g')
    if [[ $ALL_TESTS_RESULTS -eq 1 ]]
    then
        line=$(egrep "(Pass |Fail )$escapedTestCase" ${fn})
    else
        line=$(egrep "Pass $escapedTestCase" ${fn})
    fi
    
    versionedTestCase=$( echo "${line}" | egrep -c 'version:')
    [[ $DEBUG == 1 ]] && echo "versionedTestCase: $versionedTestCase"
    
    [[ $DEBUG == 1 ]] && printf "File:%s\nline:%s\n" "$fn" "$line"
    while read status testName runTime version
    do 
        [[ $DEBUG == 1 ]] && printf "\nline:test name: '%s',version: '%s', runtime: %s sec, status: '%s'\n" "$testName" "$version" "$runTime" "$status"
        if [[ $versionedTestCase -gt 0 ]]
        then
            verTag="$( echo "$version" | tr -d " []:'" | tr '=,' '-_')"
            verTag=${verTag##version}
            [[ $DEBUG == 1 ]] && echo "version tag: '$verTag'"
            
            # Create a unique key
            item="$testName-$verTag-$branchName"
            [[ $DEBUG == 1 ]] && echo "item: $item"        
            
            testName="$testName-$verTag"
            [[ $DEBUG == 1 ]] && echo "testName: $testName"        
        else
            # Create a unique key
            item="$testName-$branchName"
            [[ $DEBUG == 1 ]] && echo "item: $item"        
            
            testName="$testName"
            [[ $DEBUG == 1 ]] && echo "testName: $testName"        
        fi        
        
        [[ ${#item} -gt $maxTestNameLen ]] && maxTestNameLen=${#item}
        
        retCode=$(contains "$item" "${items[@]}" )
        [[ $DEBUG == 1 ]] && echo "contains() returned with $retCode - $( [[ $retCode -eq 0 ]] && echo 'not found' || echo 'found')."
        
        if [[ $retCode -eq 0 ]]
        then
            #echo "nincs"
            count[$item]=0
            max[$item]=0
            min[$item]=99999
            sum[$item]=0
            passed[$item]=0
            failed[$item]=0
            items+=( "$item" )
        fi
        count[$item]=$(( count[$item] + 1 ))
        sum[$item]=$(( sum[$item] + $runTime ))
        [[ max[$item] -le $runTime ]] && max[$item]=$runTime
        [[ min[$item] -gt $runTime ]] && min[$item]=$runTime
        [[ "$status" == "Pass" ]] && passed[$item]=$(( passed[$item] + 1 )) || failed[$item]=$(( failed[$item] + 1 ))
        testNames[$item]="$testName"
        
    done< <( [[ $versionedTestCase -gt 0  ]] && (echo "$line" | tr '()' '[]' |sed -n 's/^\s*.*\([PF].*\)\s\(.*\)\.ecl\s\(\[.*\]\)\s*.*\[\(.*\) sec\].*$/\1 \2 \4 \3/p')  \

                                                                        || (echo "$line"  | tr '()' '[]' |sed -n 's/^\s*.*\([PF].*\)\s\(.*\)\.ecl\s\-\sW[0-9\-]*\s*\[\(.*\) sec\].*$/\1 \2 \3/p') \
                    )

    [[ $DEBUG == 1 ]] && printf "--------------------------\n\n"
      
done< <(find . -iname $engine'.2*.log' -type f -print)

[[ ($VERBOSE -eq 1) || ($DEBUG == 1) ]] && echo "maxTestNameLen: $maxTestNameLen"
items=( $( printf "%s\n" "${items[@]}" | sort ) )
prevTestName=${testNames[${items[0]}]}
[[  ($VERBOSE -eq 1) || ($DEBUG == 1)]] && echo "testName: '$prevTestName'"
echo ""
printf "%-*s:  %-5s  %-6s  %-6s  %-6s  %-6s  %-6s\n" "$maxTestNameLen" "Test" "count" "min(s)" "max(s)" "avg(s)" " Pass " " Fail "
printf "%.*s\n"  "$(( $maxTestNameLen + 48 ))"  "--------------------------------------------------------------------------------------------------------------------------------------------------------------"
for item in  ${items[@]}
do
    testName=${testNames[$item]}
    if [[ ("$testName" != "$prevTestName") && ($SEPARATOR -eq 1) ]]
    then
        printf "\n"
        prevTestName=$testName
    fi
    if [[ count[$item] -ne 0 ]]
    then
        avg[$item]=$(( sum[$item] / count[$item] ))
    else
        avg[$item]=0
    fi
    printf "%-*s:  %5d  %5d   %5d   %5d   %5d   %5d\n"  "$maxTestNameLen" "$item" "${count[$item]}" "${min[$item]}" "${max[$item]}" "${avg[$item]}" "${passed[$item]}" "${failed[$item]}"
done

popd > /dev/null
