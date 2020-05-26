#!/bin/bash

# Git branch settings

. ./settings.sh


SHORT_DATE=$(date "+%Y-%m-%d")

#REPORT_FILE_NAME=hpcc-2018-04-09.tgz
REPORT_FILE_NAME=hpcc-$SHORT_DATE.tgz

WEEK_DAY=$(date "+%w")
REPORT_PATH=/common/nightly_builds/Coverity
#RECEIVERS=richard.chapman@lexisnexisrisk.com,gavin.halliday@lexisnexisrisk.com,attila.vamos@lexisnexisrisk.com,attila.vamos@gmail.com
RECEIVERS=attila.vamos@lexisnexisrisk.com,attila.vamos@gmail.com

if [[ -f ${REPORT_PATH}/${REPORT_FILE_NAME} ]]
then
	echo "Start Coverity scan upload."

	# To upload
	# When you upload the build can you also include the commit SHA in the version (Gavin)
	#

	echo "Get ${BRANCH_ID} branch SHA"
	pushd ~/build/CE/platform/HPCC-Platform/
          
	branchCrc=$( git log -1 | grep '^commit' | cut -s -d' ' -f 2)

	#branchCrc=db01fc58b205926f02dda2963a0c0e562b6331f3
            
	echo ${branchCrc}
	popd

	curl --form token=Z9iZGv5orqz0Kw5UJA9k6A \
	  --form email=${ADMIN_EMAIL_ADDRESS} \
	  --form file=@${REPORT_PATH}/${REPORT_FILE_NAME} \
	  --form version="${BRANCH_ID}-SHA:${branchCrc}" \
	  --form description=" " \
	  https://scan.coverity.com/builds?project=HPCC-Platform

	#echo "$res"
else
	echo "Coverity scan file not found."
fi        

echo "End."

