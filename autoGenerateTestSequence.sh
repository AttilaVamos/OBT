#!/bin/bash

PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

#--------------------------------------------------------------------------
#
# This script generates obtSeqience.inc (used by obtSequencer.sh) from the
# master and the latest maxAutoBranch number of candidate-<major>.<minor>.x branches.
# Based on the value of 'isMultiChannelTest' it generates a single version with 1 channel / thor slave or
# 1 ch/sl and 4ch/sl versions for each .x branches, except the last one, because all versioned test makes 
# the daily test cycle longer.
#
#  It can be use either:
#
# 1. Put it into test machine crontab and execute it after the update.sh and before obtSequencer.sh started.
#
# 2. Manually generate obtSequence.inc, copy it to the relevant machine settings
#     directory (e.c. OBT-AWS02/) then push changes into GitHub.
#
#--------------------------------------------------------------------------

#set -x

echo "Start ..."
echo "----------------------------"
pushd ~/HPCC-Platform > /dev/null

branches=( "'master' " )
maxAutoBranch=5

runs=()
runArray=()
runArray+=("RUN_ARRAY=(")

addRun()
{
  index=$1
  br=$2
  kind=$3
  retVal=""
  case $kind in
    0) retVal="RUN_$index=(\"BRANCH_ID=$br\")"
       ;;

    1) retVal="RUN_$index=(\"BRANCH_ID=$br\" \"REGRESSION_NUMBER_OF_THOR_CHANNELS=4\")"
       ;;

    2) retVal="RUN_$index=(\"BRANCH_ID=$br\" \"KEEP_VCPKG_CACHE=1\")"
       ;;

  esac
  runs+=("$retVal")
  runArray+=("  RUN_$index[@]    # $br ($( [[ $kind -eq 1 ]] && echo '4 ch/th sl' || echo '1 ch/th sl' ))")
  #echo $retVal
}

addRun "1" "master" "0"

isMultiChannelTest=0

branchIndex=1
runIndex=$(( branchIndex * 2 ))

while read branch
do
  printf "%d: %s\n" "$branchIndex" "$branch"
  branches+="'$branch' "

  # Each branch testing in 2 settings except the last (the oldest) one
  
  if [[ $isMultiChannelTest -eq 1 ]]
  then
      addRun "$runIndex" "$branch" "1"
  else
      addRun "$runIndex" "$branch" "0"
  fi    
  runIndex=$(( runIndex + 1 ))

  if [[ ($branchIndex -ne $maxAutoBranch) && ($isMultiChannelTest -eq 1) ]]
  then
    addRun "$runIndex" "$branch" "2"
    runIndex=$(( runIndex + 1 ))
  fi

  branchIndex=$(( branchIndex + 1 ))

done < <(git branch -r | egrep -v '\->|origin' | egrep 'candidate\-[0-9]*.[0-9]*.x' | sort -rV | head -n $maxAutoBranch | cut -d '/' -f 2)

popd > /dev/null

runArray+=(")")

#
# Start to generate obtSequence.inc file
#
echo "Start to generate the sequence file..."
outFile="obtSequence.inc"

echo "BRANCHES_TO_TEST=( $branches)"
echo "BRANCHES_TO_TEST=( $branches)" > $outFile
echo " "  >> $outFile

OLD_IFS=$IFS
IFS=$'\n'

echo "# For versioning" >> $outFile
for ((i = 0; i < ${#runs[@]}; i++))
do
    echo "$i: ${runs[$i]}"
    echo "${runs[$i]}" >> $outFile
done

echo " " >> $outFile

echo "Release"
echo "if [[ \"\$BUILD_TYPE\" == \"RelWithDebInfo\" ]]" >> $outFile
echo "then" >> $outFile

for (( i = 0; i < ${#runArray[@]}; i++))
do
  echo "${runArray[$i]}"
  echo "  ${runArray[$i]}"  >> $outFile
done

echo "Debug"
echo "else" >> $outFile
echo "  # The debug testing is slow, use less branches and versions" >> $outFile
for (( i = 0; i < 2 * ${#runArray[@]} / 3 ; i++))
do
  echo "${runArray[$i]}"
  echo "  ${runArray[$i]}"  >> $outFile
done
echo "  ${runArray[-1]}"
echo "  ${runArray[-1]}"  >> $outFile

echo "fi" >> $outFile

echo "File generation done."
IFS=$OLD_IFS
set +x

echo "----------------------------"
echo "   End."

