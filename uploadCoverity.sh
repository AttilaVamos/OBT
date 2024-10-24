#!/bin/bash

# Enable to upload any of the possible hpcc-yyyy-mm-dd.tgz and hpcc-cloud-yyyy-mm-dd.tgz results


# Git branch settings

. ./settings.sh

# To enable to specify different coverity result file date than the today's date
# use "yyyy-mm-dd" format
# TO-DO: do it nicer and enable to specify source path to get the corret commit ID
#
if [ "$1." == "." ]
then
    SHORT_DATE=$(date "+%Y-%m-%d")
else
    SHORT_DATE=$1
fi

REPORT_FILE_NAME=hpcc-$SHORT_DATE.tgz
CONTAINERIZED=0

if [[ -f ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} ]]
then
        COVERITY_PROJECT_NAME=HPCC-Platform
        PROJECT_ID=1115
        if [ -f coverityToken.dat ]
        then
            echo "Get Coverity upload token."
            COVERITY_TOKEN=$(cat coverityToken.dat)
            echo "Done."
        else
            echo "Send Email to ${RECEIVERS} about missing 'coverityToken'."
            echo -e "Hi,\n\nCoverity analysis at ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} failed on missing coverityToken.\n\nThanks\n\nOBT" | mailx -s "Missing coverityToken" -u root  ${RECEIVERS}
            exit -1
        fi
else
    REPORT_FILE_NAME=hpcc-cloud-$SHORT_DATE.tgz
    if [[ -f ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} ]]
    then
            CONTAINERIZED=1
            COVERITY_PROJECT_NAME=HPCC-Platform-Cloud
            PROJECT_ID=29342

            if [ -f coverityTokenCloud.dat ]
            then
                echo "Get Coverity Cloud upload token."
                COVERITY_TOKEN=$(cat coverityTokenCloud.dat)
                echo "Done."
            else
                echo "Send Email to ${RECEIVERS} about missing 'coverityTokenCloud.dat'."
                echo -e "Hi,\n\nCoverity analysis at ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} failed on missing coverityCloudToken.\n\nThanks\n\nOBT" | mailx -s "Missing coverityCloudToken" -u root  ${RECEIVERS}
                exit -1
            fi
    else
        echo "Coverity scan file for $SHORT_DATE not found."
        echo "To upload an older (hpcc[-cloud]-*-YYYY-MM-DD.tgz), but not yet analysed result, use $0 <YYYY-MM-DD>."
        exit -1
    fi
fi

RECEIVERS=attila.vamos@lexisnexisrisk.com,attila.vamos@gmail.com

echo "Start Coverity scan upload."

# To upload
# When you upload the build can you also include the commit SHA in the version (Gavin)
#
echo "Get ${COVERITY_TEST_BRANCH} branch SHA"
# Need to use the correct path which is PCC-Platform-master-<timestamp>
branchDir=$(find ~/build/CE/platform/ -iname 'HPCC-Platform-'$COVERITY_TEST_BRANCH'*' -type d )
if [[ -d $branchDir ]]
then
    pushd $branchDir
    branchCrc=$( git log -1 | grep '^commit' | cut -s -d' ' -f 2)
    popd   
else
    echo "$branchDir not found"
    branchCrc="NotFound"
fi

echo ${branchCrc}

echo "Send Email to ${RECEIVERS}"
echo -e "Hi,\n\nCoverity analysis at ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} is ready to upload.\nversion=\"${BRANCH_ID}-SHA:${branchCrc}\"\n\nThanks\n\nOBT" | mailx -s "Today coverity result" -u root  ${RECEIVERS}

# Need to add error handling and retrying
echo "Uploading started"
echo "REPORT_FILE_NAME: '$REPORT_FILE_NAME'"
echo "PROJECT_ID      : '$PROJECT_ID'"

echo "Get upload parameters:"
res=$(curl -X POST -d version="${BRANCH_ID}-SHA:${branchCrc}" -d description="Upload by $OBT_ID" -d email=attila.vamos@gmail.com -d token=$COVERITY_TOKEN -d file_name="${REPORT_FILE_NAME}" https://scan.coverity.com/projects/$PROJECT_ID/builds/init | tee response )
retCode=$?
echo -e "Ret code: $retCode\nResult: ${res}"

# Check the response
# If
#     "Your build is already in the queue for analysis...."
# or
#     "The build submission quota for this project has been reached..."
# is there then nothing to do
#
if [[ "$res" =~ "already in the queue" || "$res" =~ "submission quota" ]]
then
    echo "Skip the rest, result is already uploaded."
else
    uploadUrl=$( echo -e "$res" | sed -n 's/.*"url":"\([^"]*\)",.*/\1/p' )
    #uploadUrl=$(jq -r '.url' response)
    echo "uploadUrl: '$uploadUrl'"

    buildId=$(echo "$res" | sed -n 's/.*"build_id":\([^,]*\).*/\1/p' )
    #buildId=$(jq -r '.build_is' response)
    echo "buildId: $buildId"

    echo -e "Upload  ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} file\nuploadUrl:'${uploadUrl}'"
    res=$(curl -X PUT --header 'Content-Type: application/json' --upload-file ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} --http1.1 "${uploadUrl}")
    echo "Result: ${res}"
    
    if [[ "$res" =~ "<Error>" ]]
    then
        echo "Problem with upload. Skip the rest."
    else
        echo "Trigger the build on Scan."
        res=$(curl -X PUT -d token=$COVERITY_TOKEN https://scan.coverity.com/projects/$PROJECT_ID/builds/$buildId/enqueue)
        echo "Result: ${res}"
    fi
fi

echo "End."

