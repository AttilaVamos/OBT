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
DEBUG=1

echo "Start..."

OBT_RESULT_DIR=$OBT_BIN_DIR

case $OBT_ID in

    VM-18_04) OBT_RESULT_DIR=~/shared/OBT-AWS02/
                        ;;
                        
    UbuntuDockerPlaygroundVM)
                        OBT_RESULT_DIR=~/OBT/
                        ;;
esac

echo "Result dir is: $OBT_RESULT_DIR"

if [[ -f gitHubToken.dat ]]
then
    echo "GitHub token file found."
    token=$(<./gitHubToken.dat)
else
    echo "GitHub token file not found, exit."
    exit 1
fi

if [[ -f gistId.dat ]]
then
    echo "Result gists id file found."
    gistId=$(<./gistId.dat)
else
    echo "Result gists id file not found, exit."
    exit 1
fi


pushd ${HOME} > /dev/null
echo "Clean-up 'gists' directory."
[[ -d gists ]] && rm -rf gists

echo "Clone OBT results into gists directory"
res=$(git clone https://$token@gist.github.com/$gistId.git gists 2>&1)
retCode=$?

[[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
[[ $DEBUG -ne 0 ]] && echo "res : $res"

cd gists

echo "  Synch result files from $OBT_RESULT_DIR."
res=$(rsync -va $OBT_RESULT_DIR/[rO]*.json . 2>&1)
retCode=$?

[[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
[[ $DEBUG -ne 0 ]] && echo "res : $res"

res=$(git status 2>&1)
retCode=$?

[[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
[[ $DEBUG -ne 0 ]] && echo "res : $res"

CURRENT_README=''

if [[ "$res" =~ "Untracked files" ]]
then
    echo "  Add new result file(s) to gist"
   
    res=$(git add . 2>&1)
    retCode=$?

    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res : $res"

    res=$(git status 2>&1)
    retCode=$?

    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res : $res"

    numOfNewFiles=$( echo "$res" | egrep 'new file' | wc -l )

    # Update README.rst
    echo "Updated on: $(date)." >  README.rst
    echo "$res" | egrep 'new file' | awk '{ print "  -"$1" "$2" "$3}' >> README.rst

    [[ $DEBUG -ne 0 ]] && echo ""
    [[ $DEBUG -ne 0 ]] && cat README.rst
    CURRENT_README=$(<./README.rst)

    echo "  Commit changes"
    res=$(git commit -a -s -m"Upload new results." 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res : $res"

    echo "  Push changes"
    res=$(git push origin main 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res : $res"

else
    echo "  No new file added."
fi

DAYS_TO_KEEP=60
echo "Check if there is any older than $DAYS_TO_KEEP days file."
FILES_ARCHIVED=0

while read fileName
do
    fName=${fileName#./}                    # Delete leading './' from the fileName but keep the original, need it to zip and git
    fName=${fName//candidate-/}         # Delete 'candidate-' to make filenames uniform
    source=$(echo "$fName" | cut -d'-' -f1)
    [[ $DEBUG -ne 0 ]] && printf "%30s, %20s," "$fName" "$source"
    
    dateStamp=$(echo "$fName" | awk -F '-' '{ print $4"-"$5 }' )
    [[ $DEBUG -ne 0 ]] && printf "%s\n" "$dateStamp"
    
    res=$( zip -m results-${dateStamp}.zip $fileName 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res: $res"
    
    FILES_ARCHIVED=$(( FILES_ARCHIVED + 1 ))
    
    res=$( git rm $fileName 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res: $res"

done< <( find . -iname '*.json' -mtime +${DAYS_TO_KEEP} -type f -print )

echo "$CURRENT_README" > README.rst
if [[ $FILES_ARCHIVED -ne 0 ]]
then
    # Update README.rst
    echo " " >>  README.rst
    echo "$FILES_ARCHIVED result files (older than $DAYS_TO_KEEP days) archived." >> README.rst
    
    echo "  $FILES_ARCHIVED old result files archived."
    
     [[ $DEBUG -ne 0 ]] && echo "  git status"
    res=$(git status 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res: $res"
    
    numOfNewFiles=$( echo "$res" | egrep 'new file' | wc -l )

    if [[ "$res" =~ "Untracked files" ]]
    then
        [[ $DEBUG -ne 0 ]] && echo "  git add ."
        res=$(git add . 2>&1)
        retCode=$?
        [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
        [[ $DEBUG -ne 0 ]] && echo "res: $res"
        
        [[ $DEBUG -ne 0 ]] && echo "  git status"
        res=$(git status 2>&1)
        retCode=$?
        [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
        [[ $DEBUG -ne 0 ]] && echo "res: $res"

        numOfNewFiles=$( echo "$res" | egrep 'new file' | wc -l )
        echo "$numOfNewFiles new archive added."
        echo "$numOfNewFiles new archive added." >> README.rst
        echo "$res" | egrep 'new file' | awk '{ print "  -"$1" "$2" "$3}' >> README.rst
    fi 

    [[ $DEBUG -ne 0 ]] && echo ""
    [[ $DEBUG -ne 0 ]] && echo "README.rst:"
    [[ $DEBUG -ne 0 ]] && cat README.rst

    echo " Commit changes"
    res=$(git commit -a -s -m"Upload new results." 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res: $res"

    echo " Push changes"
    res=$(git push origin main 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res: $res"
else
    echo "  No file found to archive."
fi
   
popd > /dev/null

ELAPS_TIME=$(( $(date +%s) - $START_TIME_SEC ))
echo "Finished in $ELAPS_TIME sec."
