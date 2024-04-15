#!/bin/bash
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

testCase="genjoin"

contains() {
    item="$1"
    shift
    list=("$@")
    local retVal=0
    local e
    for e in "${list[@]}"
    do
        if [[ "$e" == "$item" ]]
        then
            retVal=1
            break
        fi
    done
    echo $retVal
}

pushd ~/common/nightly_builds/HPCC/

echo "testCase: $testCase"
declare -A count  min  max sum avg
declare items=()
while read fn
do
    branchName=${fn#*/}
    branchName=${branchName%%/*}
    
    line=$(egrep "(Pass |Fail )$testCase" ${fn})
    printf "%s\n%s\n" "$fn" "$line"
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
done< <(find . -iname 'thor.2*.log' -type f -print)

printf "%-20s:\t%s\t%s\t%s\t%s\n" "Test" "count" "min(s)" "max(s)" "avg(s)"
echo "------------------------------------------------------"
for item in "${items[@]}"
do
    avg[$item]=$(( sum[$item] / count[$item] ))
    printf "%-20s:\t%3d\t%5d\t%5d\t%5d\n" "$item" "${count[$item]}" "${min[$item]}" "${max[$item]}" "${avg[$item]}"
done

popd
