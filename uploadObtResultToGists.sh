#!/usr/bin/bash

PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

#
# The process is:
# 1. get parameters and token
# 2. Clone result gists
# 3. Rsync the result file from OBT dir to gists dir
# 4. Add al lneew file
# 5. Commit them
# 6. Push
# 7. Clean-up


START_TIME=$( date "+%H:%M:%S")
START_TIME_SEC=$(date +%s)
START_CMD="$0 $*"

echo "Start..."

OBT_RESULT_DIR=$OBT_BIN_DIR

case $OBT_ID in

    VM-18_04) OBT_RESULT_DIR=~/shared/OBT-AWS03/
                        ;;
                        
    UbuntuDockerPlaygroundVM)
                        OBT_RESULT_DIR=~/OBT/
                        ;;
esac

echo "Result dir is: $OBT_RESULT_DIR"

if [[ -f gitHubToken.dat ]]
then
    token=$(<./gitHubToken.dat)
else
    echo "GitHub token file not found, exit."
    exit 1
fi

if [[ -f gistId.dat ]]
then
    gistId=$(<./gistId.dat)
else
    echo "Result gists id file not found, exit."
    exit 1
fi


pushd ${HOME}
[[ -d gists ]] && rm -rf gists

res=$(git clone https://$token@gist.github.com/$gistId.git gists 2>&1)
retCode=$?

echo "ret code: $retCode"
echo "res : $res"

cd gists

res=$(rsync -va $OBT_RESULT_DIR/*.json . 2>&1)
retCode=$?

echo "ret code: $retCode"
echo "res : $res"

res=$(git status 2>&1)
retCode=$?

echo "ret code: $retCode"
echo "res : $res"

if [[ "$res" =~ "Untracked files" ]]
then

    res=$(git add . 2>&1)
    retCode=$?

    echo "ret code: $retCode"
    echo "res : $res"

    res=$(git status 2>&1)
    retCode=$?

    echo "ret code: $retCode"
    echo "res : $res"

    numOfNewFiles=$( echo "$res" | egrep 'new file' | wc -l )
#if [[ $numOfNewFiles -ne 0 ]]
#then

    # Update README.rst
    echo "Updated on: $(date)." >  README.rst
    echo "$res" | egrep 'new file' | awk '{ print "  -"$1" "$2" "$3}' >> README.rst

    echo ""
    cat README.rst

    res=$(git commit -a -s -m"Upload new results." 2>&1)
    echo "ret code: $retCode"
    echo "res : $res"

    res=$(git push origin main 2>&1)
    echo "ret code: $retCode"
    echo "res : $res"

else
    echo "No new file added. Nothing to do."
fi
    
popd
ELAPS_TIME=$(( $(date +%s) - $START_TIME_SEC ))
echo "Finished in $ELAPS_TIME sec."
