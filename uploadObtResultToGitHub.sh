#!/usr/bin/bash

PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

. ./setttings.sh

#
# The process is:
# 1. get parameters and token
# 2. Check if TestResult alrady cloned
# 2.a. If yes, update it.
# 2.b. If not then clone it and set up origin with the token
# 3. Copy ~/diagrams.zip into  TestResults repo Perfromance/<OBT_ID>/
# 3. Rsync the result file from OBT dir to  TestResults repo dir
# 4. Add al lneew file
# 5. Commit them
# 6. Push
# 7. Clean-up


START_TIME=$( date "+%H:%M:%S")
START_TIME_SEC=$(date +%s)
START_CMD="$0 $*"
DEBUG=0
[[ -z $OBT_BIN_DIR ]] && OBT_BIN_DIR=~/build/bin

echo "Start..."

OBT_RESULT_DIR=$OBT_BIN_DIR
TEST_RESULT_REPO="https://github.com/AttilaVamos/TestResults.git "
LOCAL_TEST_RESULT_REPO_DIR=~/TestResults

case $OBT_ID in

    VM-18_04) OBT_RESULT_DIR=~/shared/OBT-AWS02/
                        ;;
                        
    UbuntuDockerPlaygroundVM)
                        OBT_RESULT_DIR=~/OBT/
                        ;;
esac

echo "Result dir is: $OBT_RESULT_DIR"

if [[ -f TestResultsToken.dat ]]
then
    echo "GitHub token file found."
    token=$(<./TestResultsToken.dat)
else
    echo "GitHub token file not found, exit."
    exit 1
fi


pushd ${HOME} > /dev/null
echo "Check $LOCAL_TEST_RESULT_REPO_DIR directory."
if [[ -d $LOCAL_TEST_RESULT_REPO_DIR ]]
then
    echo "  It is exist, udate.."
    pushd $LOCAL_TEST_RESULT_REPO_DIR
    res=$(git checkout master 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "res : $res"
    
    res=$(git pull origin master 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "res : $res"
    popd
    echo "  Done."
else
    echo "  It is not exist, clone it.."
    pushd ~/
    echo "Clone TestResults repo into ~/TestResults directory"
    res=$(git clone https://github.com/AttilaVamos/TestResults.git 2>&1)
    retCode=$?

    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "res : $res"

    cd $LOCAL_TEST_RESULT_REPO_DIR

    if [[ "$(pwd)" != "$LOCAL_TEST_RESULT_REPO_DIR" ]]
    then
        echo "The '$LOCAL_TEST_RESULT_REPO_DIR' directory is missing. Exit."
        exit -1
    fi

    res=$(git remote remove origin 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "res : $res"

    
    res=$(git remote add origin https://AttilaVamos:$token@github.com/AttilaVamos/TestResults.git 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "res : $res"
    
    popd
    echo "  Done."
fi  

cd $LOCAL_TEST_RESULT_REPO_DIR

echo "  Synch result files from $OBT_RESULT_DIR."
res=$(rsync -va $OBT_RESULT_DIR/[rO]*.json OBT-Results/ 2>&1)
retCode=$?

[[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "ret code: $retCode"
[[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "res : $res"

echo "  Done."

# Store diagrams.zip
if [[ -f ~/diagrams.zip ]]
then
    echo "Copy  '~/diagrams.zip' into  'Performance/${OBT_ID}'."
    [[ ! -d Performance/${OBT_ID} ]] && mkdir -p Performance/${OBT_ID}

    res=$(cp -v ~/diagrams.zip Performance/${OBT_ID}/diagrams.zip  2>&1)
    retCode=$?

    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "res : $res"

fi

[[ $DEBUG -ne 0 ]] && echo "Git status ..."
res=$(git status 2>&1)
retCode=$?

[[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
[[ $DEBUG -ne 0 ]] && echo "res : $res"

CURRENT_README=''

if [[ "$res" =~ "Untracked files" ]]
then
    echo "  Add $(echo "$res" | egrep '.json|.zip' | wc -l) new result file(s) to TestResults repo"
    echo "  $(echo "$res" | egrep '.json|.zip' )"
    res=$(git add . 2>&1)
    retCode=$?

    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res : $res"

    echo "$res" | egrep 'new file' | awk '{ print "  -"$1" "$2" "$3}' 
    
    [[ $DEBUG -ne 0 ]] && echo "git status ..."
    res=$(git status 2>&1)
    retCode=$?

    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res : $res"

    numOfNewFiles=$( echo "$res" | egrep 'new file' | wc -l )

    # Update README.rst
    echo "  Updated on: $(date)." >  README.rst
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
    res=$(git push origin master 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "res : $res"

else
    echo "  No new file added."
fi

TODAY=$(date +%s)
DAYS_TO_KEEP=60
DAYS_TO_KEEP_IN_SEC=$(( $DAYS_TO_KEEP * 24 * 60 * 60 )); 
OLDEST_DAY_IN_SEC=$(( $TODAY - $DAYS_TO_KEEP_IN_SEC )); 

echo "Check if there is any OBT result file older than $DAYS_TO_KEEP days."
FILES_ARCHIVED=0
pushd OBT-Results
while read fileName
do
    fName=${fileName#./}                    # Delete leading './' from the fileName but keep the original, need it to zip and git
    fName=${fName//candidate-/}         # Delete 'candidate-' to make filenames uniform
    source=$(echo "$fName" | cut -d'-' -f1)
    [[ $DEBUG -ne 0 ]] && printf "fName: '%50s', source: '%-15s', " "$fName" "$source"
    
    if [[ "$source" =~ "regress" ]]
    then
        # For AKS and Minikube results
        dateStamp=$(echo "$fName" | tr '_' '-' | awk -F '-' '{ print $2"-"$3"-"$4 }' );
        zipDateStamp=$(echo "$fName" | awk -F '-' '{ print $2"-"$3 }' )
    else
        dateStamp=$(echo "$fName" | awk -F '-' '{ print $4"-"$5"-"$6 }' );
        zipDateStamp=$(echo "$fName" | awk -F '-' '{ print $4"-"$5 }' )
    fi
    secStamp=$(date -d $dateStamp +%s)
    [[ $DEBUG -ne 0 ]] && printf "dateStamp: '%s', secStamp: %s, zipDateStamp: %s\n" "$dateStamp" "$secStamp" "$zipDateStamp"
    
    if [[ $secStamp -lt $OLDEST_DAY_IN_SEC ]]
    then
        echo "  Add $fileName to results-${zipDateStamp}.zip"
        res=$( zip -m results-${zipDateStamp}.zip $fileName 2>&1)
        retCode=$?
        [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
        [[ $DEBUG -ne 0 ]] && echo "res: $res"
        
        FILES_ARCHIVED=$(( FILES_ARCHIVED + 1 ))
        
        [[ $DEBUG -ne 0 ]] && echo "git rm $fileName"
        res=$( git rm $fileName 2>&1)
        retCode=$?
        [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
        [[ $DEBUG -ne 0 ]] && echo "res: $res"
    fi

done< <( find . -iname '*.json' -type f -print | sort )
popd

if [[ $FILES_ARCHIVED -ne 0 ]]
then
    [[ -n "$CURRENT_README" ]] && echo "$CURRENT_README" > README.rst
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
    res=$(git push origin master 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 || $retCode -ne 0 ]] && echo "res: $res"
else
    echo "  No file found to archive."
fi

popd > /dev/null

ELAPS_TIME=$(( $(date +%s) - $START_TIME_SEC ))
echo "Finished in $ELAPS_TIME sec."
