#!/bin/bash
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

testCase=""
engine="thor"
VERBOSE=0
DEBUG=0
ALL_TESTS_RESULTS=0
SEPARATOR=0
FIRST_FILE_ONLY=0

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
    echo "               Default: Thor. Use 'all' for all engenes'"
    echo " -all        - Use all test results Pass/Fail. Default: Pass only."
    echo " -addsep     - Add separator line betwent tests. Default: no"
    echo " -1          - Process the latest test result file only."
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
        [[ $DEBUG == 1 ]] && echo "Param: ${upperParam}"

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
                [[ "$engine" == 'all' ]] && engine='*'
                ;;
                
            H)
                usage
                exit 1
                ;;

            1)
                FIRST_FILE_ONLY=1
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

printf "Log directory: %s\n" "$LOG_DIR"

pushd $LOG_DIR > /dev/null

printf "Engine       : %s\n" "$( [[ $engine == '*' ]] && echo 'all' || echo $engine)"

printf "Test case    : '$testCase' %s\n" "$( [[ $testCase == '*' ]] && echo '(all)' || echo '')"
[[ "$testCase" == '*' ]] && testCase=''

printf "Result filter: "
[[ $ALL_TESTS_RESULTS -eq 1 ]] && echo "All tests" || echo "Pass only"
[[ $FIRST_FILE_ONLY -eq 1 ]] && echo "Process the first/oldest file only"

maxTestNameLen=0
filesProcessed=0
declare -A count  min  max sum avg testNames failed passed
declare items=()
while read fn
do
    printf "\r%-60s\r" "$fn"
    branchName=${fn#*/}
    branchName=${branchName#candidate-}
    branchName=${branchName%%/*}
    [[ $DEBUG == 1 ]] && printf "Branch: %s\n" "$branchName"

    testEngine=${fn##*/}
    testEngine=${testEngine%%.*}
    [[ $DEBUG == 1 ]] && printf "Test engine: %s\n" "$testEngine"
   
    # Need to escape the '(' to '\(' and ')' to '\)' for grep
    escapedTestCase=$( echo $testCase | sed -e 's/(/\\(/g' -e 's/)/\\)/g')
    [[ $DEBUG == 1 ]] && printf "escapedTestCase: %s\n" "$escapedTestCase"
    
    if [[ $ALL_TESTS_RESULTS -eq 1 ]]
    then
        lines=$(egrep "(Pass |Fail )$escapedTestCase" ${fn})
    else
        lines=$(egrep "Pass $escapedTestCase" ${fn})
    fi
    
    [[ $DEBUG == 1 ]] && printf "File:%s\nline:%s\n" "$fn" "$lines"
    IFS=$'\n'
    for line in $lines
    do 
        line=$(echo "$line" | tr '()' '[]')
        [[ $DEBUG == 1 ]] && printf "\nline: '%s'\n" "$line"

        versionedTestCase=$( echo "${line}" | egrep -c 'version:')
        if [[  $versionedTestCase -ne 0 ]]
        then
            IFS=$';' read -r status testName version runTime < <(echo "$line" | sed -n 's/^\s*.*\([PF].*\)\s\(.*\)\.ecl\s\(\[.*\]\)\s*.*\[\(.*\) sec\].*$/\1;\2;\3;\4/p')
        else
            IFS=$';' read -r status testName runTime < <(echo "$line" | sed -n 's/^\s*.*\([PF].*\)\s\(.*\)\.ecl\s\-\sW[0-9\-]*\s*\[\(.*\) sec\].*$/\1;\2;\3/p')
            version=''
        fi

        [[ $DEBUG == 1 ]] && printf "\nline:test name: '%s',version: '%s', runtime: %s sec, status: '%s'\n" "$testName" "$version" "$runTime" "$status"
        if [[ $versionedTestCase -gt 0 ]]
        then
            verTag="$( echo "$version" | tr -d " []:'" | tr '=,' '-_')"
            verTag=${verTag##version}
            [[ $DEBUG == 1 ]] && echo "version tag: '$verTag'"
            
            # Create a unique key
            item="$testName-$verTag-$branchName-$testEngine"
            [[ $DEBUG == 1 ]] && echo "item: $item"        
            
            testName="$testName-$verTag"
            [[ $DEBUG == 1 ]] && echo "testName: $testName"        
        else
            # Create a unique key
            item="$testName-$branchName-$testEngine"
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
    done
    set +x

    [[ $DEBUG == 1 ]] && echo -e "--------------------------\n\n"

    filesProcessed=$(( filesProcessed + 1 ))

    [[ $FIRST_FILE_ONLY -eq 1 ]] &&  break

done< <(find . -iname $engine'.2*.log' -type f -print | egrep -v '-exclusion' | sort -r )
echo ""

printf "%5d file(s) processed.\n" "$filesProcessed"

if [[ ${#items[@]} -eq 0 ]]
then
    printf "\nNo test match to '$testCase'. Exit.\n"
    exit 1
fi

printf "%5d result(s) generated.\n" "${#items[@]}"

[[ ($VERBOSE -eq 1) || ($DEBUG == 1) ]] && echo "maxTestNameLen: $maxTestNameLen"
items=( $( printf "%s\n" "${items[@]}" | sort ) )
prevTestName=${testNames[${items[0]}]}
[[  ($VERBOSE -eq 1) || ($DEBUG == 1)]] && echo "testName: '$prevTestName'"
echo ""
if [[ $ALL_TESTS_RESULTS -eq 1 ]]
then
    printf "%6s: %-*s:  %-5s  %-6s  %-6s  %-6s  %-6s  %-6s\n" "  No." "$maxTestNameLen" "Test" "count" "min(s)" "max(s)" "avg(s)" " Pass " " Fail "
    headerLen=$(( $maxTestNameLen + 56 ))
else
    printf "%6s: %-*s:  %-5s  %-6s  %-6s  %-6s\n" "  No." "$maxTestNameLen" "Test" "count" "min(s)" "max(s)" "avg(s)"
    headerLen=$(( $maxTestNameLen + 40 ))
fi
printf "%.*s\n"  "$headerLen"  "--------------------------------------------------------------------------------------------------------------------------------------------------------------"

itemNo=1
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

    if [[ $ALL_TESTS_RESULTS -eq 1 ]]
    then
        printf "%6d: %-*s:  %5d  %5d   %5d   %5d   %5d   %5d\n"  "$itemNo" "$maxTestNameLen" "$item" "${count[$item]}" "${min[$item]}" "${max[$item]}" "${avg[$item]}" "${passed[$item]}" "${failed[$item]}"
    else
        printf "%6d: %-*s:  %5d  %5d   %5d   %5d\n"  "$itemNo" "$maxTestNameLen" "$item" "${count[$item]}" "${min[$item]}" "${max[$item]}" "${avg[$item]}"
    fi

    itemNo=$(( itemNo + 1 ))
done

popd > /dev/null
