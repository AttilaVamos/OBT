#!/bin/bash

PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }' 
#set -x

#
#------------------------------
#   Process:
#       - In source directory
#           - getting commit IDs between start and end
#           - getting date a merge lines from commit messages
#           - checkout a commit
#           - clean the branch
#           - deinit and update submodules
#           - if there are modified files, remove them
#       - In build directory
#           - call build.sh with " slave 4 unit plugi clean eclwa -pkg-suffix <COMMIT_ID>"
#           - install the package
#      - In RTE directory
#           - run all_denormalize
#           ./ecl-test query  --suiteDir ~/HPCC-Platform/testing/regress/ --pq 4 --config ecl-test.json --loglevel info -t hthor --jobnamesuffix $commitID all_denorm*
#       - Collect timing info:
#           QueryStat2.py [-d <DATES_IF_THESTS_OVERLAPS>]  --addHeader --compileTimeDetails=2 -g -a --timestamp [--buildBranch '<BUILD_BRANCH>']
#



#
#------------------------------
#
# Imports (settings, functions)
#

# Git branch settings

. ./settings.sh

#
#------------------------------
#
sourcePath=~/HPCC-Platform
buildPath=~/HPCC-Platform-build

BRANCH_ID=master

START_DATE="2023-03-08"
END_DATE="2023-03-11"
pushd $sourcePath
git checkout master

commitIds=( $( git log --after="$START_DATE 00:00" --before="$END_DATE 00:00" --merges --reverse  --first-parent --oneline master | awk '{ print $1 }' ) )
printf "commit id: %s\n" "${commitIds[@]}"

commitsInfo=$( git log --after="$START_DATE 00:00" --before="$END_DATE 00:00" --merges --reverse  --first-parent master |  egrep "commit|Date:|Merge pull|Merge remote" | awk '{$1=$1;print}' )

echo ""
echo "$commitsInfo"

commits=$(echo "$commitsInfo" | egrep 'commit' | awk '{ print $2}'  | xargs printf "%8.8s\n")
echo ""
echo "$commits"

for commit in ${commitIds[@]}
do
    echo "Commit id: $commit"
    alreadyBuilt=$( ls -l $buildPath | egrep -c $commit)
    [[ $alreadyBuilt -eq 0 ]] && echo  "  No" || echo "  $( ls -l $buildPath | egrep $commit | awk '{ print $9 }')"
done
