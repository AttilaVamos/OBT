#!/usr/bin/bash
#set -x;
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

START_TIME=$( date "+%H:%M:%S")
START_TIME_SEC=$(date +%s)
START_CMD="$0 $*"

if [ -f ./timestampLogger.sh ]
then
    . ./timestampLogger.sh
else
    echo "Define a lightweight WriteLog() function"
    WriteLog()
    {
        msg=$1
        out=$2
        [ -z "$out" ] && out=/dev/null

        echo -e "$msg"
        echo -e "$msg" >> $out 2>&1
    }
fi

usage()
{
    WriteLog "usage:" "/dev/null"
    WriteLog "  $0 [-i] [-q] [-h]" "/dev/null"
    WriteLog "where:" "/dev/null"
    WriteLog " -i       - Interactive, stop before unistall helm chart and stop minikube." "/dev/null"
    WriteLog " -q       - Quick test, doesn't execute whole Regression Suite, only a subset of it." "/dev/null"
    WriteLog " -t <tag> - Manually specify the tag (e.g.: 9.4.0-rc7) to be test." "/dev/null"
    WriteLog " -v       - Show more logs (about PODs deploy and destroy)." "/dev/null"
    WriteLog " -d       - Enable debug log." "/dev/null"
    WriteLog " -h       - This help." "/dev/null"
    WriteLog " " "/dev/null"
}

SecToTimeStr()
{
    t=$1
    echo "($( date -u --date @$t +%H:%M:%S))"
}

PrintSetting()
{
    name=$1
    log=$2
    local str=$( printf "%-20s : %s" "$name" "${!name}" )
    WriteLog "$str" "$log"
}

ProcessLog()
{ 
    result="$1"
    local -n retString=$2
    local action="$3"
    local logFile=$4
    actionCap=${action,,}
    actionCap=${actionCap^}
    [[ $DEBUG == 1 ]] && WriteLog "result   : $result" "$logFile"
    [[ $DEBUG == 1 ]] && WriteLog "action   : $action" "$logFile"
    [[ $DEBUG == 1 ]] && WriteLog "actionCap: $actionCap" "$logFile"
    [[ $DEBUG == 1 ]] && WriteLog "logFile  : $logFile" "$logFile"
    #set -x
    engine=()
    engine+=( $(echo "$result" | sed -n "s/^.*[[:space:]]*Suite: \([^ ]*\).*/\1/p") )
    
    total=()
    total+=( $(echo "$result" | sed -n "s/^.*[[:space:]]*Queries:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p") )

    passed=()
    passed+=( $(echo "$result" | sed -n "s/^[[:space:]]*Passing:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p") )

    failed=()
    failed+=( $(echo "$result" | sed -n "s/^[[:space:]]*Failure:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p") )

    readarray -t errors < <( echo "$result" | egrep "Suite:|Fail " )
    OLD_IFS=$IFS
    local IFS=$'\n'
    elapsed=()
    readarray -t elapsed < <( echo "$result" | egrep "Elapsed time:" |  awk '{ print $3" "$4" "$5 }' )

    if [[ $DEBUG == 1 ]]
    then
        WriteLog "${engine[@]}" "$logFile"
        WriteLog "................." "$logFile"
        WriteLog "${total[@]}" "$logFile"
        WriteLog "................." "$logFile"
        WriteLog "${passed[@]}" "$logFile"
        WriteLog "................." "$logFile"
        WriteLog "${failed[@]}" "$logFile"
        WriteLog "................." "$logFile"
        WriteLog "${elapsed[@]}" "$logFile"
        WriteLog "................." "$logFile"
    fi

    _retStr=$(printf "%-20s %s\t%s\t%s\t%s\n\n" "Engine" "Query" "Pass" "Fail" "Time")
    for i in "${!engine[@]}"
    do
        eng=${engine[$i]}
        engines+=("$eng")
        queries[$eng]="${total[$i]}"
        passes[$eng]="${passed[$i]}"
        fails[$eng]="${failed[$i]}"
        time_str[$eng]="${elapsed[$i]}"
        _str=$(printf "%8s%-20s %5d\t%4d\t%4d\t%19s\n" " " "${engine[$i]}" "${total[$i]}" "${passed[$i]}" "${failed[$i]}" "${elapsed[$i]}") 
        _retStr=$(echo -e "${_retStr}\n${_str}")

        capEngine=${eng^^}_${action}
        [[ $DEBUG == 1 ]] && WriteLog "capEngine: $capEngine" "$logFile"
        printf -v "$capEngine"_QUERIES  '%s' "${queries[$eng]}"
        #declare -g "${capEngine}_QUERIES"="${queries[$engine]}"    # An alternative
        printf -v "$capEngine"_PASS     '%s' "${passes[$eng]}"
        printf -v "$capEngine"_FAIL     '%s' "${fails[$eng]}"
        printf -v "$capEngine"_TIME_STR '%s' "${time_str[$eng]}"
        printf -v "$capEngine"_TIME     '%s' "$(echo ${time_str[$eng]} | cut -d' ' -f1 )"
        printf -v "$capEngine"_RESULT_STR '%s' "$( [[ ${fails[$eng]} -eq 0 ]] && echo "PASSED" || echo "FAILED" )"
    done
    retString=$_retStr
    
    declare -a hthorErrors thorErrors roxieErrors
    arrayName=''
    for item in ${errors[@]}
    do
        if [[ "$item" =~ "hthor" ]]
        then
            arrayName="hthorErrors"
            continue
        fi

        if [[ "$item" =~ "thor" ]]
        then
            arrayName="thorErrors"
            continue
        fi

        if [[ "$item" =~ "roxie" ]]
        then
            arrayName="roxieErrors"
            continue
        fi

        if [[ "$arrayName" == "hthorErrors" ]]
        then

            hthorErrors+=("$item")
            continue
        fi
        
        if [[ "$arrayName" == "thorErrors" ]]
        then
            thorErrors+=("$item")
            continue
        fi

        if [[ "$arrayName" == "roxieErrors" ]]
        then
            roxieErrors+=("$item")
            continue
        fi
    done
    
    if [[ $DEBUG == 1 ]]
    then
        WriteLog "hthorErrors:${hthorErrors[@]}" "$logFile"
        WriteLog "................." "$logFile"
        WriteLog "thorErrors:${thorErrors[@]}" "$logFile"
        WriteLog "................." "$logFile"
        WriteLog "roxieErrors:${roxieErrors[@]}" "$logFile"
        WriteLog "................." "$logFile"
    fi

    unset errStr
    for item in ${hthorErrors[@]}
    do
        [[ -z $errStr ]] && errStr="$( echo -e "{\n            \"Hthor${actionCap}\" : [\n")"
        errStr=$( echo -e "${errStr}\n                \"$item\",")
    done
    [[ -n $errStr ]] && errStr=$( echo -e "${errStr}\n                ],\n            },\n")
    capEngine=HTHOR_${action}
    printf -v "$capEngine"_ERROR_STR '%s' "${errStr}"

    unset errStr
    for item in ${thorErrors[@]}
    do
        [[ -z $errStr ]] && errStr="$( echo -e "{\n            \"Thor${actionCap}\" : [\n")"
        errStr=$( echo -e "${errStr}\n                \"$item\",")
    done
    [[ -n $errStr ]] && errStr=$( echo -e "${errStr}\n            ],\n        },\n")
    capEngine=THOR_${action}
    printf -v "$capEngine"_ERROR_STR '%s' "${errStr}"

    unset errStr
    for item in ${roxieErrors[@]}
    do
        [[ -z $errStr ]] && errStr="$( echo -e "{\n            \"Roxie${actionCap}\" : [\n")"
        errStr=$( echo -e "${errStr}\n                \"$item\",")
    done
    [[ -n $errStr ]] && errStr=$( echo -e "${errStr}\n            ],\n        }\n")
    capEngine=ROXIE_${action}
    printf -v "$capEngine"_ERROR_STR '%s' "${errStr}"

    set +x
    IFS=$OLD_IFS
}

#set -x;
START_DATE=$(date +%Y-%m-%d_%H-%M-%S)
logFile=$(pwd)/regressMinikube-$START_DATE.log

getLogs=0
if [[ -f ./settings.sh && ( "$OBT_ID" =~ "OBT" ) ]]
then
    WriteLog "We are in OBT environment" "$logFile"
    . ./settings.sh
    SOURCE_DIR=$SOURCE_HOME
    SUITEDIR=$TEST_ENGINE_HOME
    RTE_DIR=$REGRESSION_TEST_ENGINE_HOME
    QUERY_STAT2_DIR="$OBT_BIN_DIR"
    PERFSTAT_DIR="$HOME/Perfstat-Minikube/"
    PKG_DIR=$OBT_BIN_DIR/PkgCache
else
    WriteLog "Non OBT environment, like local VM/BM" "$logFile"
    SOURCE_DIR="$HOME/HPCC-Platform"
    SUITEDIR="$SOURCE_DIR/testing/regress/"
    RTE_DIR="$HOME/RTE-NEWER"
    [[ ! -d $RTE_DIR ]] && RTE_DIR="$HOME/RTE"
    [[ ! -d $RTE_DIR ]] && RTE_DIR=$SUITEDIR
    PKG_DIR="$HOME/HPCC-Platform-build/"
    OBT_BIN_DIR=$(pwd)

    QUERY_STAT2_DIR="$RTE_DIR"
    [[ ! -f $QUERY_STAT2_DIR/QueryStat2.py ]] && QUERY_STAT2_DIR=$(pwd)
    [[ ! -f $QUERY_STAT2_DIR/QueryStat2.py ]] && QUERY_STAT2_DIR=''
    PERFSTAT_DIR="Minikube/"

    PKG_DIR="$HOME/HPCC-Platform-build"
    PKG_IS_DEB=$( type "dpkg" 2>&1 | grep -v -c "not found" )
    if [[ $PKG_IS_DEB -eq 1 ]]
    then    
        PKG_EXT=".deb"
        PKG_INST_CMD="dpkg -i "
        PKG_QRY_CMD="dpkg -l "
        PKG_REM_CMD="dpkg -r "
    else
        PKG_EXT=".rpm"
        PKG_INST_CMD="rpm -i --nodeps "
        PKG_QRY_CMD="rpm -qa "
        PKG_REM_CMD="rpm -e --nodeps "
    fi
    
    # Get system info 
    SYSTEM_ID=$( cat /etc/*-release | egrep -i "^PRETTY_NAME" | cut -d= -f2 | tr -d '"' )
    if [[ "${SYSTEM_ID}" == "" ]]
    then
        SYSTEM_ID=$( cat /etc/*-release | head -1 )
    fi
    SYSTEM_ID=${SYSTEM_ID// (*)/}
    SYSTEM_ID=${SYSTEM_ID// /_}
    SYSTEM_ID=${SYSTEM_ID//./_}

fi

RTE_CONFIG="./ecl-test-k8s.json"
RTE_PQ="--pq 2"
RTE_TIMEOUT="--timeout 1200"
#RTE_QUICK_TEST_SET='teststdlib*'
#RTE_QUICK_TEST_SET='alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall*'
#RTE_QUICK_TEST_SET='alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall* teststdlib*'
#RTE_QUICK_TEST_SET='pipe* httpcall* soapcall* roxie* badindex.ecl'
RTE_QUICK_TEST_SET='pipe* httpcall* soapcall* roxie* badindex.ecl cryptoplugin_pke_lfn.ecl external.ecl'  # To generate errors as well

RTE_EXCLUSIONS='--ef pipefail.ecl -e embedded-r,embedded-js,3rdpartyservice,mongodb,spray'

INTERFACE=$(ip -o link show | awk -F': ' '{ print $2 }' | grep '^en')
LOCAL_IP="$(ip addr show $INTERFACE | grep 'inet\b' | awk '{ print $2 }' | cut -d/ -f1)"

#set -x
DEBUG=0
INTERACTIVE=0
FULL_REGRESSION=1
TAG='<latest>'
VERBOSE=0

while [ $# -gt 0 ]
do
    param=$1
    param=${param//-/}
    upperParam=${param^^}
    #WriteLog "Param: ${upperParam}" "/dev/null"
    case $upperParam in
        D) DEBUG=1
            ;;
            
        I)  INTERACTIVE=1
            ;;
               
        Q)  FULL_REGRESSION=0
            ;;

        T)  shift
            TAG=$1
            ;;

        V) VERBOSE=1
           ;;

        H* | *)
            WriteLog "Unknown parameter: ${upperParam}" "/dev/null"
            usage
            exit 1
            ;;
    esac
    shift
done


PrintSetting "START_CMD" "$logFile"
PrintSetting "SOURCE_DIR" "$logFile"
PrintSetting "SUITEDIR" "$logFile"
PrintSetting "RTE_DIR" "$logFile"
PrintSetting "OBT_BIN_DIR" "$logFile"
PrintSetting "QUERY_STAT2_DIR" "$logFile"
PrintSetting "PERFSTAT_DIR" "$logFile"
PrintSetting "RTE_QUICK_TEST_SET" "$logFile"
PrintSetting "RTE_EXCLUSIONS" "$logFile"
PrintSetting "PKG_DIR" "$logFile"
PrintSetting "PKG_EXT" "$logFile"
PrintSetting "PKG_INST_CMD" "$logFile"
PrintSetting "PKG_QRY_CMD" "$logFile"
PrintSetting "PKG_REM_CMD" "$logFile"
PrintSetting "RTE_CONFIG" "$logFile"
PrintSetting "RTE_PQ" "$logFile"
PrintSetting "RTE_TIMEOUT" "$logFile"
PrintSetting "INTERACTIVE" "$logFile"
PrintSetting "FULL_REGRESSION" "$logFile"
PrintSetting "TAG" "$logFile"
PrintSetting "VERBOSE" "$logFile"
PrintSetting "LOCAL_IP" "$logFile"

WriteLog "Update helm repo..." "$logFile"
TIME_STAMP=$(date +%s)
res=$(helm repo update 2>&1)
HELM_UPDATE_TIME=$(( $(date +%s) - $TIME_STAMP ))
WriteLog "$res" "$logFile"
HELM_UPDATE_TIME_STR="$HELM_UPDATE_TIME sec $(SecToTimeStr $HELM_UPDATE_TIME)"
HELM_UPDATE_RESULT_STR="Done"
HELM_UPDATE_RESULT_REPORT_STR="$HELM_UPDATE_RESULT_STR in $HELM_UPDATE_TIME_STR"
WriteLog "  $HELM_UPDATE_RESULT_REPORT_STR" "$logFile"

pushd $SOURCE_DIR > /dev/null

res=$(git checkout -f master 2>&1)
WriteLog "git checkout -f master\n  $res" "$logFile"
res=$(git clean -f -fd 2>&1)
WriteLog "git clean -f -fd\n  $res" "$logFile"
res=$(git fetch --tags --all 2>&1)
WriteLog "git fetch --tags --all\n  $res" "$logFile"

gold=0
suffix=""
found=0
# If lates release no available set manually to an older one
# Use parameter if given
if [[  "$TAG" != "<latest>" ]]
then
    tagToTest=$TAG
    WriteLog "Manually set tag to test: '$tagToTest'" "$logFile"
    if [[ ! "$tagToTest" =~ "community_" ]]
    then 
        WriteLog "add 'community_' prefix to '$tagToTest'" "$logFile"
        base=$tagToTest
        tagToTest="community_$TAG"
    else
        # Clear the 'community_' prefix
        base=${tagToTest##community_}
    fi
    
    # If gold, remove the '-x' suffix
    if [[ ! "$base" =~ "-rc" ]]
    then 
        tag=${base%-*}
        gold=1
        suffix=" Gold"
    else
        tag=$base
        suffix=""
    fi
    WriteLog "Check the $tag$suffix has image to deploy in k8s." "$logFile"
    res=$(curl -s https://hub.docker.com/v2/repositories/hpccsystems/platform-core/tags/$tag 2>&1)
    if [[  "$res" =~ "image" ]]
    then
        WriteLog "  It has deployable image, check the helm chart." "$logFile"
        resMsg=$(helm search repo --devel --version=$tag hpcc/hpcc |  egrep $tag )
        if [[ -n "$resMsg" ]]
        then
            WriteLog "  The helm chart is ready, use this tag." "$logFile"
            found=1
        else
            WriteLog "  The helm chart not found." "$logFile"
            WriteLog "  resMsg: '$resMsg'"  "$logFile"
            WriteLog "  Try later or with a different tag." "$logFile"
        fi
    else
        WriteLog "  It has not deployable image, try a different tag." "$logFile"
        exit 2
    fi
else
    # We need this magic, because somebody can cretate new tag for previous minor or major release
    # and in this case it would be the first in the result of 'git tag --sort=-creatordate' command
    # Get the last 25 tags, sort them by version in reverse order, and get the first (it will be
    # related to the latest branch)
    latestBranchTag=$(git tag --sort=-creatordate | egrep 'community_' |  head -n 25 | sort -rV | head -n 1)
    latestBranch=${latestBranchTag%-*}
    latestBranch=${latestBranch##community_}
    latestMajorMinor=${latestBranch%.*}
    WriteLog "Latest branch : $latestBranch (tag: $latestBranchTag, latest major.minor: $latestMajorMinor)" "$logFile"

    while read tagToTest
    do
        WriteLog "Test candidate tag: $tagToTest" "$logFile"

        # Clear the 'community_' prefix
        tag=${tagToTest##community_}
        # If it is gold, remove -x suffix
        if [[ ! "$tag" =~ "-rc" ]]
        then 
            tag=${tag%-*}
            gold=1
            suffix=" Gold"
        else
            gold=0
            suffix=""
        fi
        
        WriteLog "Check the $tag$suffix has image to deploy in k8s." "$logFile"
        res=$(curl -s https://hub.docker.com/v2/repositories/hpccsystems/platform-core/tags/$tag 2>&1)
        if [[  "$res" =~ "image" ]]
        then
            WriteLog "  It has deployable image, check the helm chart." "$logFile"
            resMsg=$(helm search repo --devel --version=$tag hpcc/hpcc |  egrep $tag )
            if [[ -n "$resMsg" ]]
            then
                WriteLog "  The helm chart is ready, use this tag." "$logFile"
                found=1
                break
            else
                WriteLog "  The helm chart not found." "$logFile"
                WriteLog "  resMsg: '$resMsg'"  "$logFile"
                WriteLog "  Try later or with a different tag." "$logFile"
            fi        
        else
            WriteLog "  It has not deployable image, step back one tag." "$logFile"
        fi
    done< <(git tag --sort=-creatordate | egrep 'community_'$latestMajorMinor |  head -n 10 )
fi

if [[ $found -ne 1 ]]
then
    WriteLog "Can't find a tag with deployable image in: " "$logFile"
    WriteLog "$(git tag --sort=-creatordate | egrep 'community_'$latestBranch | head -n 10). \nExit." "$logFile"
    exit 2
else
    # We have the latest version of latest release branch in '<major>.<minor>.<point>' form
    TAG_TO_TEST="$tagToTest$suffix"
    WriteLog "Final tag to test: $tagToTest$suffix" "$logFile"
fi

# Use that version for get the lates tag of the latest branch
res=$( git checkout $tagToTest  2>&1 )
WriteLog "checkout $tagToTest\nres: $res" "$logFile"

# Patch all aaa*.ecl setup ecl with '//library' tag.
WriteLog "Path setup library files with '//library' tag..." "$logFile"
while read fn
do
    WriteLog "  $fn" "$logFile"
    res=$( sed -i 's/\(\/\/publish\)/\1\n\/\/library\n/g' $fn 2>&1)
    retCode=$?
    [[ $retCode -ne 0 ]] && WriteLog "    retCode: $retCode\n   res:$res" "$logFile"

    res=$( egrep -A1 '\/\/publish'; )
    retCode=$?
    WriteLog "    retCode: $retCode,\nres: '$res'" "$logFile"
done< <(find testing/regress/ecl/setup -iname 'aaa*.ecl' -type f )
WriteLog "  Done." "$logFile"

popd > /dev/null

base=$tag
# Remove the point build
baseMajorMinor=${base%.*}
pkg="*community?$baseMajorMinor*$PKG_EXT"
WriteLog "base: ${base}" "$logFile"

WriteLog "base major.minor:$baseMajorMinor" "$logFile"
WriteLog "pkg:$pkg" "$logFile"
TIME_STAMP=$(date +%s)
if [ "$PKG_EXT" == ".deb" ]
then
    CURRENT_PKG=$( ${PKG_QRY_CMD} | grep 'hpccsystems-pl' | awk '{ print $3 }' )
else
    CURRENT_PKG=$( ${PKG_QRY_CMD} | grep 'hpccsystems-pl' | awk -F - '{ print $3 }' )
fi
[ -z "$CURRENT_PKG" ] && CURRENT_PKG="Not installed"
WriteLog "current installed pkg: $CURRENT_PKG" "$logFile"

CURRENT_PKG_MajorMinor=${CURRENT_PKG%.*}
WriteLog "current installed pkg major.minor: $CURRENT_PKG_MajorMinor" "$logFile"
if [[ "$CURRENT_PKG_MajorMinor" == "$baseMajorMinor" ]]
then
    WriteLog "The installed platform package is ok to testing cloud." "$logFile"
else
    WriteLog "Need to install $pkg to testing cloud." "$logFile"
    if [[ $INTERACTIVE -eq 1 ]]
    then
        candidates=$( find $PKG_DIR -maxdepth 1 -iname $pkg -type f )
        if [ -n "$candidates" ]
        then
            WriteLog "Possible candidate(s):" "$logFile"
            WriteLog "$candidates" "$logFile"
        fi
        exit 1
    else
        candidate=$( find $PKG_DIR -maxdepth 2 -iname $pkg -type f | sort -rV | head -n 1 )
        if [ -n "$candidate" ]
        then
            WriteLog "Install $candidate" "$logFile"
            sudo ${PKG_INST_CMD} $candidate
            retCode=$?
            if [[ $retCode -ne 0 ]]
            then
                WriteLog "Install $candiadate failed with $retCode." "$logFile"
                exit 1
            fi
            CURRENT_PKG=$dandiate
            WriteLog "Done." "$logFile"
        else
            WriteLog "Platform install package:$pkd not found, exit." "$logFile"
            exit 1
        fi
    fi
fi

PLATFORM_INSTALL_TIME=$(( $(date +%s) - $TIME_STAMP ))
PLATFORM_INSTALL_TIME_STR="$PLATFORM_INSTALL_TIME sec $(SecToTimeStr $PLATFORM_INSTALL_TIME)"
PLATFORM_INSTALL_RESULT_STR="Done"
PLATFORM_INSTALL_RESULT_REPORT_STR="$PLATFORM_INSTALL_RESULT_STR in $PLATFORM_INSTALL_TIME_STR"
WriteLog "  $PLATFORM_INSTALL_RESULT_REPORT_STR" "$logFile"

TIME_STAMP=$(date +%s)
isMinikubeUp=$( minikube status | egrep -c 'Running|Configured'  )
if [[ $isMinikubeUp -ne 4 ]]
then
    WriteLog "Minikube is down." "$logFile"
    # Let's do some Minikube cahce maintenance
    if [[ -f $OBT_BIN_DIR/platformTag.txt ]]
    then 
        oldTag=$( cat $OBT_BIN_DIR/platformTag.txt)
        if [[ "$oldTag" != "$base" ]]
        then
            echo "$base" > $OBT_BIN_DIR/platformTag.txt
            WriteLog "There is a new tag, remove all older cached images to save disk space." "$logFile"
            WriteLog "Before:\n\t$(df -h .)" "$logFile"
            # Remove all cached images
            res=$( minikube delete 2>&1 ) 
            [[ $VERBOSE == 1 ]] && WriteLog "Minikube delete res:\n$res" "$logFile"
            WriteLog "After:\n\t$(df -h .)" "$logFile"
        fi
    else
        echo "$base" > $OBT_BIN_DIR/platformTag.txt
    fi
    WriteLog "Start Minikube." "$logFile"
    res=$(minikube start 2>&1)
    WriteLog "$res" "$logFile"
    
else
    WriteLog "Minikube is up." "$logFile"
fi

MINIKUBE_START_TIME=$(( $(date +%s) - $TIME_STAMP ))
MINIKUBE_START_TIME_STR="$MINIKUBE_START_TIME sec $(SecToTimeStr $MINIKUBE_START_TIME)"
MINIKUBE_START_RESULT_STR="Done"
MINIKUBE_START_RESULT_REPORT_STR="$MINIKUBE_START_RESULT_STR in $MINIKUBE_START_TIME_STR"
WriteLog "  $MINIKUBE_START_RESULT_REPORT_STR" "$logFile"

TIME_STAMP=$(date +%s)
WriteLog "Deploy HPCC ..." "$logFile"
res=$( helm install minikube hpcc/hpcc --version=$base  -f ./obt-values.yaml  2>&1)
WriteLog "$res" "$logFile"
PLATFORM_DEPLOY_TIME=$(( $(date +%s) - $TIME_STAMP ))
PLATFORM_DEPLOY_TIME_STR="$PLATFORM_DEPLOY_TIME sec $(SecToTimeStr $PLATFORM_DEPLOY_TIME)"
PLATFORM_DEPLOY_RESULT_STR="Done"
PLATFORM_DEPLOY_RESULT_REPORT_STR="$PLATFORM_DEPLOY_RESULT_STR in $PLATFORM_DEPLOY_TIME_STR"
WriteLog "  $PLATFORM_DEPLOY_RESULT_REPORT_STR" "$logFile"

# Wait until everything is up
WriteLog "Wait for PODs" "$logFile"
TIME_STAMP=$(date +%s)
tryCount=60
delay=10
expected=0
running=0
while true; 
do  
    while read a b c; 
    do 
        running=$(( $running + $a )); 
        expected=$(( $expected + $b )); 
        [[ $DEBUG == 1 ]] && WriteLog "$(printf '%-45s: %s/%s  %s\n' $c $a $b  $( [[ $a -ne $b ]] && echo starting || echo up) )" "$logFile"; 
    done < <( kubectl get pods | egrep -v 'NAME' | awk '{ print $2 " " $1 }' | tr "/" " "); 
    WriteLog "$( printf 'Expected: %s, running %s (%2d)\n' $expected $running $tryCount)" "$logFile"; 

    [[ $running -ne 0 && $running -eq $expected ]] && break || sleep ${delay}; 

    tryCount=$(( $tryCount - 1)); 
    [[ $tryCount -eq 0 ]] && break; 

    expected=0; 
    running=0; 
done

sleep 10
# test it
WriteLog "$(printf '\nExpected: %s, running %s (%2d)\n' $expected $running $tryCount )" "$logFile"
PODS_START_TIME=$(( $(date +%s) - $TIME_STAMP ))
PODS_START_TIME_STR="$PODS_START_TIME sec $(SecToTimeStr $PODS_START_TIME)"
PODS_START_RESULT_STR="Done"
NUMBER_OF_RUNNING_PODS=$running
PODS_START_RESULT_SUFFIX_STR="$NUMBER_OF_RUNNING_PODS PODs are up."
PODS_START_RESULT_REPORT_STR="$PODS_START_RESULT_STR in $PODS_START_TIME_STR, $PODS_START_RESULT_SUFFIX_STR"
WriteLog "  $PODS_START_RESULT_REPORT_STR" "$logFile"

if [[ ($expected -eq $running) && ($running -ne 0 ) ]]
then
    # Pods are up

    pushd $RTE_DIR > /dev/null
    WriteLog "cwd: $(pwd)" "$logFile"
    
    TIME_STAMP=$(date +%s)
    WriteLog "Start ECLWatch." "$logFile"
    res=$( minikube service eclwatch 2>&1)
    WriteLog "$res" "$logFile"
    sleep 30
    
    uri=$( minikube service list | egrep 'eclwatch' | awk '{ print $8 }' | cut -d '/' -f3 )
    WriteLog "uri: $uri" "$logFile"
    ip=$( echo $uri | cut -d ':' -f 1 )
    WriteLog "ip: $ip" "$logFile"
    port=$( echo $uri | cut -d ':' -f 2 )
    WriteLog "port: $port" "$logFile"
    #echo "Press <Enter> to continue"
    #read
    ECLWATCH_START_TIME=$(( $(date +%s) - $TIME_STAMP ))
    ECLWATCH_START_TIME_STR="$ECLWATCH_START_TIME sec $(SecToTimeStr $ECLWATCH_START_TIME)"
    ECLWATCH_START_RESULT_REPORT_STR="$ECLWATCH_START_RESULT_STR in $ECLWATCH_START_TIME_STR"
    WriteLog "  $ECLWATCH_START_RESULT_REPORT_STR" "$logFile"
    
    WriteLog "Run tests." "$logFile"
     [[ $DEBUG == 1 ]] && pwd

    setupPass=1
    WriteLog "Run regression setup ..." "$logFile"
    res=$( ./ecl-test setup --server $ip:$port --suiteDir $SUITEDIR --config $RTE_CONFIG  $RTE_PQ --timeout 900 --loglevel info 2>&1 )
    retCode=$?
    isError=$( echo "${res}" | egrep -c 'Fail ' )
    WriteLog "retCode: ${retCode}, isError: ${isError}" "$logFile"
     if [[ ${retCode} -ne 0  || ${isError} -ne 0 ]] 
    then
        getLogs=1
        setupPass=0
        SETUP_RESULT_STR="FAILED"
    else
        SETUP_RESULT_STR="PASSED"
    fi
    
    _res=$(echo "$res" | egrep 'Suite:|Queries:|Passing:|Failure:|Elapsed|Fail ' )
    WriteLog "$_res" "$logFile"
    declare -A queries passes fails time_str 
    declare -a errors=()
    declare -a engines=()
    SETUP_RESULT_REPORT_STR=''
    action="SETUP"
    ProcessLog "$res" SETUP_RESULT_REPORT_STR $action  "$logFile"
    WriteLog "action: '$action'" "$logFile"
    WriteLog "SETUP_RESULT_REPORT_STR:\n$SETUP_RESULT_REPORT_STR" "$logFile"

    
    NUMBER_OF_PUBLISHED=0
    if [[ $setupPass -eq 1 ]]
    then
        # Experimental code for publish Queries to Roxie
        WriteLog "Publish queries to Roxie ..." "$logFile"
        # To proper publish we need in SUITEDIR/ecl to avoid compile error for new queries
        pushd $SUITEDIR/ecl
        TIME_STAMP=$(date +%s)
        # New RTE deploys queries to roxie
#        while read query
#        do
#            WriteLog "Query: $query" "$logFile"
#            res=$( ecl publish -t roxie --server $ip --port $port $query 2>&1 )
#            WriteLog "$res" "$logFile"
#            NUMBER_OF_PUBLISHED=$(( NUMBER_OF_PUBLISHED + 1 ))
#        done< <(egrep -l '\/\/publish' setup/*.ecl)
#        
        QUERIES_PUBLISH_TIME=$(( $(date +%s) - $TIME_STAMP ))
        popd
        QUERIES_PUBLISH_TIME_STR="$QUERIES_PUBLISH_TIME sec $(SecToTimeStr $QUERIES_PUBLISH_TIME)"
        QUERIES_PUBLISH_RESULT_STR="Done"
        QUERIES_PUBLISH_RESULT_SUFFIX_STR="$NUMBER_OF_PUBLISHED queries published to Roxie."
        QUERIES_PUBLISH_REPORT_STR="$QUERIES_PUBLISH_RESULT_STR in $QUERIES_PUBLISH_TIME_STR, $QUERIES_PUBLISH_RESULT_SUFFIX_STR"
        WriteLog "  $QUERIES_PUBLISH_REPORT_STR" "$logFile"

        REGRESS_START_TIME=$( date "+%H:%M:%S")
        REGRESS_RESULT_REPORT_STR=''
        # Regression stage
        if [[ $FULL_REGRESSION -eq 1 ]]
        then
            WriteLog "Run Regression Suite ..." "$logFile"
            # For full regression on hthor
            REGRESS_CMD="./ecl-test run --server $ip:$port $RTE_EXCLUSIONS --suiteDir $SUITEDIR --config $RTE_CONFIG $RTE_PQ $RTE_TIMEOUT --loglevel info"
            res=$( ./ecl-test run --server $ip:$port $RTE_EXCLUSIONS --suiteDir $SUITEDIR --config $RTE_CONFIG $RTE_PQ $RTE_TIMEOUT --loglevel info 2>&1 )
        else
            # For sanity testing on all engines
            WriteLog "Run regression quick sanity chceck with ($RTE_QUICK_TEST_SET)" "$logFile"
            REGRESS_CMD="./ecl-test query --server $ip:$port --suiteDir $SUITEDIR $RTE_EXCLUSIONS --config $RTE_CONFIG $RTE_PQ $RTE_TIMEOUT --loglevel info $RTE_QUICK_TEST_SET"
            res=$( ./ecl-test query --server $ip:$port $RTE_EXCLUSIONS --suiteDir $SUITEDIR --config $RTE_CONFIG $RTE_PQ $RTE_TIMEOUT --loglevel info $RTE_QUICK_TEST_SET 2>&1 )
        fi

        retCode=$?
        isError=$( echo "${res}" | egrep -c 'Fail ' )
        WriteLog "retCode: ${retCode}, isError: ${isError}" "$logFile"
        if [[ ${retCode} -ne 0  || ${isError} -ne 0 ]]
        then
            getLogs=1
            REGRESS_RESULT_STR="FAILED"
            WriteLog "cmd: '$REGRESS_CMD'" "$logFile"
            WriteLog "pwd: '$(pwd)', dirs: '$(dirs)'" "$logFile"
            if [[ $retCode -ne 0 ]]
            then
                # RTE itself reported error, log the problem
                WriteLog "$res" "$logFile"
                REGRESS_RESULT_REPORT_STR="$res"
            else
                # Report the failed tet cases
                _res=$(echo "$res" | egrep 'Suite:|Queries:|Passing:|Failure:|Elapsed|Fail ' )
                WriteLog "$_res" "$logFile"
                REGRESS_RESULT_REPORT_STR="$_res"
            fi
        else
            _res=$(echo "$res" | egrep 'Suite:|Queries:|Passing:|Failure:|Elapsed|Fail ' )
            WriteLog "$_res" "$logFile"
            REGRESS_RESULT_STR="PASSED"
        fi
        
        action="REGRESS"
        ProcessLog "$res" REGRESS_RESULT_REPORT_STR $action  "$logFile"
        WriteLog "action: '$action'" "$logFile"
        [[ $DEBUG == 1 ]] && WriteLog "REGRESS_RESULT_REPORT_STR:\n$REGRESS_RESULT_REPORT_STR" "$logFile"
    
    else
        WriteLog "Setup is failed, skip regression tessting." "$logFile"
        QUERIES_PUBLISH_RESULT_STR="Skipped based on setup error"
        QUERIES_PUBLISH_TIME=0
        QUERIES_PUBLISH_TIME_STR="$QUERIES_PUBLISH_TIME sec $(SecToTimeStr $QUERIES_PUBLISH_TIME)"
        QUERIES_PUBLISH_REPORT_STR="Skipped based on setup error"
        
        REGRESS_START_TIME=$( date "+%H:%M:%S")
        REGRESS_RESULT_STR="Skipped based on setup error"
        REGRESS_RESULT_REPORT_STR="$REGRESS_RESULT_STR"
    fi

    if [[ -n "$QUERY_STAT2_DIR" ]]
    then
        TIME_STAMP=$(date +%s)
        pushd $QUERY_STAT2_DIR > /dev/null
        res=$( ./QueryStat2.py -a -t $ip --port $port --obtSystem=Minikube --buildBranch=$base -p $PERFSTAT_DIR --addHeader --compileTimeDetails 1 --timestamp )
        QUERY_STAT2_TIME=$(( $(date +%s) - $TIME_STAMP ))
        WriteLog "${res}" "$logFile"
        QUERY_STAT2_TIME_STR="$QUERY_STAT2_TIME sec $(SecToTimeStr $QUERY_STAT2_TIME)."
        QUERY_STAT2_RESULT_STR="Done"
        WriteLog "  $QUERY_STAT2_RESULT_STR in $QUERY_STAT2_TIME_STR" "$logFile"
        popd > /dev/null
    else
        WriteLog "Missing QueryStat2.py, skip cluster and compile time query." "$logFile"
    fi

    popd > /dev/null
else
    WriteLog "Problem with pods start" "$logFile"
    getLogs=1
fi

# Get all logs if needed
TIME_STAMP=$(date +%s)
if [[ ${getLogs} -ne 0 ]]
then
    WriteLog "Collect logs" "$logFile"
    dirName="$HOME/shared/Minikube/test-$(date +%Y-%m-%d_%H-%M-%S)"; 
    [[ ! -d $dirName ]] && mkdir -p $dirName; 
    kubectl get pods | egrep -v 'NAME' | awk '{ print $1 }' | while read podId; 
    do 
        [[ "$podId" =~ "mydali" ]] && param="mydali" || param=""; 
        WriteLog "pod:$podId - $param" "$logFile"; 
        kubectl describe pod $podId > $dirName/$podId.desc;  
        kubectl logs $podId $param > $dirName/$podId.log; 
    done; 
    kubectl get pods > $dirName/pods.log;  
    kubectl get services > $dirName/services.log;  
    kubectl describe nodes > $dirName/nodes.desc; 
    minikube logs >  $dirName/all.log 2>&1
else
    WriteLog "Skip log collection" "$logFile"
fi
COLLECT_POD_LOGS_TIME=$(( $(date +%s) - $TIME_STAMP ))
COLLECT_POD_LOGS_TIME_STR="$COLLECT_POD_LOGS_TIME sec $(SecToTimeStr $COLLECT_POD_LOGS_TIME)."
COLLECT_POD_LOGS_RESULT_STR="Done"
WriteLog "  $COLLECT_POD_LOGS_RESULT_STR in $COLLECT_POD_LOGS_TIME_STR" "$logFile"

if [[ $INTERACTIVE -eq 1 ]]
then
    WriteLog "Testing finished, press <Enter> to stop pods.\n(After 60 seconds it will continue)" "$logFile"
    read -t 60
fi

WriteLog "Uninstall PODs ..." "$logFile"
TIME_STAMP=$(date +%s)
res=$(helm uninstall minikube 2>&1)
WriteLog "${res}" "$logFile"

# Wait until everyting is down
tryCount=60
delay=10
while true
do
    #date;
    expected=0;
    running=0;
    [[ $DEBUG == 1 ]] && set -x
    while read a b c
    do
        [[ $DEBUG == 1 ]] && WriteLog "a:'$a', b:'$b', c:'$c'" "$logFile"
        running=$(( $running + $a ));
        #expected=$(( $expected + $b ));
        [[ $DEBUG == 1 ]] && WriteLog " $( printf '%-45s: %s/%s  %s\n' $c $a $b  $( [[ $a -ne $b ]] && echo starting || echo up ))" "$logFile" ;
    done < <( kubectl get pods | egrep -v 'NAME|No resources ' | awk '{ print $2 " " $1 }' | tr "/" " "  );
    #done < <( kubectl get pods | egrep -v 'NAME|No resources ' | awk '{ print $2 " " $1 }' | tr "/" " " | cut -d ' ' -f1,2,3 | awk '{ print $1" "$2" "$3}' );
    [[ $DEBUG == 1 ]] && set +x
    WriteLog "$( printf '\nExpected: %s, running %s (%s)\n' $expected $running $tryCount)"  "$logFile";

    [[ $running -eq 0 ]] && break || sleep $delay;

    tryCount=$(( $tryCount - 1 ))

    if [[ $tryCount -eq 0 ]]
    then
        WriteLog "Try count exhauset, but there are $running still running pods, collect logs about then delete them."  "$logFile"
        # Collect logs from still running pods
        dirName="$HOME/shared/Minikube/test-$(date +%Y-%m-%d_%H-%M-%S)"; 
        [[ ! -d $dirName ]] && mkdir -p $dirName; 
        kubectl get pods | egrep -v 'NAME' | awk '{ print $1 }' | while read podId; 
        do 
            [[ "$podId" =~ "mydali" ]] && param="mydali" || param=""; 
            WriteLog "pod:$podId - $param"; 
            kubectl describe pod $podId > $dirName/$podId.desc; 
            kubectl logs $podId $param > $dirName/$podId.log; 
            kubectl logs -p $podId $param > $dirName/$podId-prev.log; 
        done; 
        kubectl get pods > $dirName/pods.log;  
        kubectl get services > $dirName/services.log;  
        kubectl describe nodes > $dirName/nodes.desc; 
        minikube logs >  $dirName/all.log 2>&1

        # delete them with 1 Minute grace period
        for podId in `kubectl get pods | grep -v ^NAME | awk '{print $1}'` ;
        do
            kubectl delete pod $podId --grace-period=60  # or with --force
        done

        # give it 10 more attempts
        tryCount=10
    fi
done;
[[ $DEBUG == 1 ]] && set +x
WriteLog "System is down" "$logFile"
UNINSTALL_PODS_TIME=$(( $(date +%s) - $TIME_STAMP ))
UNINSTALL_PODS_TIME_STR="$UNINSTALL_PODS_TIME sec $(SecToTimeStr $UNINSTALL_PODS_TIME)"
UNINSTALL_PODS_RESULT_STR="Done"
UNINSTALL_PODS_RESULT_SUFFIX_STR="$running PODs are running."
WriteLog "  $UNINSTALL_PODS_RESULT_STR in $UNINSTALL_PODS_TIME_STR, $UNINSTALL_PODS_RESULT_SUFFIX_STR" "$logFile"

WriteLog "Stop Minikube" "$logFile"
TIME_STAMP=$(date +%s)
res=$(minikube stop 2>&1)
WriteLog "${res}" "$logFile"
MINIKUBE_STOP_TIME=$(( $(date +%s) - $TIME_STAMP ))
MINIKUBE_STOP_TIME_STR="$MINIKUBE_STOP_TIME sec $(SecToTimeStr $MINIKUBE_STOP_TIME)."
MINIKUBE_STOP_TIME_RESULT="Done"
WriteLog "  $MINIKUBE_STOP_TIME_RESULT in $MINIKUBE_STOP_TIME_STR" "$logFile"

if [[ -n "$QUERY_STAT2_DIR" ]]
then
    WriteLog "Start log processor..." "$logFile"
    pushd $QUERY_STAT2_DIR > /dev/null
    if [ -f regressK8sLogProcessor.py ]
    then
        TIME_STAMP=$(date +%s)
        res=$( ./regressK8sLogProcessor.py --path ./  2>&1 )
        WriteLog "${res}" "$logFile"
        REGRESS_LOG_PROCESSING_TIME=$(( $(date +%s) - $TIME_STAMP ))
        REGRESS_LOG_PROCESSING_TIME_STR="$REGRESS_LOG_PROCESSING_TIME sec $(SecToTimeStr $REGRESS_LOG_PROCESSING_TIME)."
        REGRESS_LOG_PROCESSING_RESULT_STR="Done"
        WriteLog "  $REGRESS_LOG_PROCESSING_RESULT_STR in $REGRESS_LOG_PROCESSING_TIME_STR" "$logFile"
    else
        WriteLog "regressK8sLogProcessor.py not found." "$logFile"
    fi
    popd > /dev/null
else
    WriteLog "Missing OBT binary directory, skip Minikube test log processing." "$logFile"
fi

END_TIME=$( date "+%H:%M:%S")
RUN_TIME=$((  $(date +%s) - $START_TIME_SEC ))
RUN_TIME_STR="$RUN_TIME sec $(SecToTimeStr $RUN_TIME)"
END_TIME_STR="$END_TIME, run time: $RUN_TIME_STR"

WriteLog "Generate reports..." "$logFile"
TIME_STAMP=$(date +%s)
WriteLog "  Text" "$logFile"
report1=$(<./regressMinikubeReport.templ)
# Do it with 'eval'
eval "resolved1=\"$report1\""

[[ $DEBUG == 1 ]] && WriteLog "resolved1:\n$resolved1" "$logFile"
echo "$resolved1" > regressMinikube-$START_DATE.report

WriteLog "  JSON" "$logFile"
report2=$(<./regressMinikubeReportJson.templ)
eval "resolved2=\"$report2\""

[[ $DEBUG == 1 ]] && WriteLog "resolved2:\n$resolved2" "$logFile"
echo "$resolved2" > regressMinikube-$START_DATE.json

REPORT_GENERATION_TIME=$(( $(date +%s) - $TIME_STAMP ))
REPORT_GENERATION_TIME_STR="$REPORT_GENERATION_TIME sec $(SecToTimeStr $REPORT_GENERATION_TIME)"
WriteLog "  Report generation is done in $REPORT_GENERATION_TIME_STR." "$logFile"

WriteLog "End ($RUN_TIME_STR)." "$logFile"
WriteLog "==================================" "$logFile"
