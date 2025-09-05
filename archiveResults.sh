TODAY=$(date +%s)
DAYS_TO_KEEP=6
DAYS_TO_KEEP_IN_SEC=$(( $DAYS_TO_KEEP * 24 * 60 * 60 )); 
OLDEST_DAY_IN_SEC=$(( $TODAY - $DAYS_TO_KEEP_IN_SEC )); 

FILES_ARCHIVED=0

DIR_TO_COMPRESS="."
# To do it in other directory 
DIR_TO_COMPRESS=$HOME/shared/Azure/
#DIR_TO_COMPRESS=$HOME/shared/Minikube/
#DIR_TO_COMPRESS=$HOME/shared/AWS-Minikube/
[[ "$DIR_TO_COMPRESS" != "." ]] && pushd $DIR_TO_COMPRESS

# TW trough result directories in loop to clean-up both directory.
DIRS_TO_COMPRESS=( . $HOME/shared/Azure/ $HOME/shared/Minikube/ $HOME/shared/AWS-Minikube/ )

for dir in ${DIRS_TO_COMPRESS[@]}
do
    echo "Check if there are any file older than $DAYS_TO_KEEP days in '$dir'."

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
        fi

    done< <( find . -iname 'regress*.[jlr]*' -type f -print | sort )

    echo "$FILES_ARCHIVED file(s) archived in '$dir'."
done
echo "  End."
