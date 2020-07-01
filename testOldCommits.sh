#!/bin/bash


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


PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }' 
#set -x

sourcePath=~/build/CE/platform/HPCC-Platform
BRANCH_ID=master

TIME_SERVER=$( grep ^server /etc/ntp.conf | head -n 1 | cut -d' ' -f2 )


IS_SCL=$( type "scl" 2>&1 )
if [[ "${IS_SCL}" =~ "not found" ]]
then 
    printf "SCL is not installed."
else 
    id=$( scl -l | grep -c 'devtoolset' )
    if [[ $id -ne 0 ]]
    then
        DEVTOOLSET=$(  scl -l | tail -n 1 )
        printf "%s is installed." "${DEVTOOLSET}"
        . scl_source enable ${DEVTOOLSET}
        export CL_PATH=/opt/rh/${DEVTOOLSET}/root/usr;
    else
        printf "DEVTOOLSET is not installed."
    fi
fi

GetCommitSha()
{
    #set -x
    testDate=$1
    sourceDate=$( date -I -d "$testDate - 1 day" )
    
    pushd ${sourcePath} > /dev/null

    # to restore whole commit tree
    git checkout -f ${BRANCH_ID} > /dev/null 2>&1
    
    sha=$( git log --after="$sourceDate 00:00" --before="$testDate 00:00$" --merges | grep -A3 'commit' | head -n 1 | cut -d' ' -f2 )
    until [[ -n "$sha" ]]
    do
        # step one day back
        sourceDate=$( date -I -d "$sourceDate - 1 day" )
        # Get SHA
        sha=$( git log --after="$sourceDate 00:00" --before="$testDate 00:00$" --merges | grep -A3 'commit' | head -n 1 | cut -d' ' -f2 )
    done

    # to restore whole commit tree
    git checkout -f ${BRANCH_ID} > /dev/null 2>&1

    
    popd > /dev/null
    #set +x
    
    echo $sha
}


CWD=$( pwd ) 
targetFile="${PWD}/settings.inc"

# Forward
#firsTestDate="2017-11-01"
#lastTestDate="2017-12-08"


# Backward
lastTestDate="2017-08-27"
firsTestDate="2017-08-21"
# back 4 weeks
#firsTestDate=$( date -I -d "$lastTestDate - 27 days")
# back one week
#firsTestDate=$( date -I -d "$lastTestDate - 6 days")


printf "from %s to %s\n" "$firsTestDate" "$lastTestDate"
dayCount=0
direction="backward"
daySkip=1

if [[ "$direction" == "forward" ]]
then
    # forward 
    testDate=$firsTestDate
else
    # backward
    testDate=$lastTestDate
fi

sudo service ntpd stop


printf "Test date\tcommit\n"
# forward
#until [[ "$testDate" > "$lastTestDate" ]]
# backward
until [[ "$testDate" < "$firsTestDate" ]]
do 
    testSha=$( GetCommitSha "$testDate" )
    
    printf "%s\t%s\n" "$testDate" "$testSha"
    
    # create setting.inc with SHA
    printf "# test date:%s \n" "$testDate" > ${targetFile}
    printf "SHA=%s\n\n" "$testSha" >> ${targetFile}

    # magic with date set it back to original test date (one minute after midnight)
    sudo date -s "$testDate 00:01:00"

    date

    # Execute OBT with performance test
    ./obtMain.sh perf
    
    #  Restore the correct date with NTPD 
    #sudo ntpdate time.nist.gov
    sudo ntpd -gq
    date
    
    # next test date
    if [[ "$direction" == "forward" ]]
    then
        testDate=$( date -I -d "$testDate + $daySkip day")
    else
        testDate=$( date -I -d "$testDate - $daySkip day")
    fi
    dayCount=$(( $dayCount + 1 ))

done

printf "day counts:%d\n" $dayCount

sudo service ntpd start
