#!/usr/bin/bash

PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

START_TIME=$( date "+%H:%M:%S")
START_TIME_SEC=$(date +%s)
START_CMD="$0 $*"

if [ -f ./timestampLogger.sh ]
then
    echo "Using WriteLog() from the existing timestampLogger.sh"
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
    WriteLog "  $0 [-i] [-q] [-t <tag>] [-dt <minute>] [-v] [-r] [-d] [-h]" "/dev/null"
    WriteLog "where:" "/dev/null"
    WriteLog " -i       - Interactive, stop before unistall the Platform." "/dev/null"
    WriteLog " -q       - Quick test, doesn't execute whole Regression" "/dev/null"
    WriteLog "            Suite, only a subset of it." "/dev/null"
    WriteLog " -t <tag> - Manually specify the tag (e.g.: 9.4.0-rc7)" "/dev/null"
    WriteLog "            to be test." "/dev/null"
    WriteLog " -dt      - AKS deploy timeout. A floating number with" "/dev/null"
    WriteLog "            'm' suffix for minutes. Default is: $DEPLOY_TIMEOUT." "/dev/null"
    WriteLog " -v       - Show more logs (about PODs deploy and destroy)." "/dev/null"
    WriteLog " -r       - Start resources: VNet and Storage accounts" "/dev/null"
    WriteLog "            before deploy HPCC and destroy them at the end." "/dev/null"
    WriteLog " -d       - Enable debug log." "/dev/null"
    WriteLog " -h       - This help." "/dev/null"
    WriteLog " " "/dev/null"
}

SecToTimeStr()
{
    t=$1
    echo "($(date -u --date @$t +%H:%M:%S))"
}

ProcessLog()
{ 
    result="$1"
    local -n retString=$2
    local action="$3"
    #echo "result:$result"
    #echo "action:$action"
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

    #echo "${engine[@]}"
    #echo "................."
    #echo "${total[@]}"
    #echo "................."
    #echo "${passed[@]}"
    #echo "................."
    #echo "${failed[@]}"
    #echo "................."
    #echo "${elapsed[@]}"
    #echo "................."
    
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
        #echo "capEngine: $capEngine"
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
    
    #echo "hthorErrors:${hthorErrors[@]}"
    #echo "................."
    #echo "thorErrors:${thorErrors[@]}"
    #echo "................."
    #echo "roxieErrors:${roxieErrors[@]}"
    #echo "................."

    unset errStr
    for item in ${hthorErrors[@]}
    do
        [[ -z $errStr ]] && errStr="$( echo -e "{\n\"Hthor_${action}\" : [\n")"
        errStr=$( echo -e "${errStr}\n\"$item\",")
    done
    [[ -n $errStr ]] && errStr=$( echo -e "${errStr}\n],\n},\n")
    capEngine=HTHOR_${action}
    printf -v "$capEngine"_ERROR_STR '%s' "${errStr}"

    unset errStr
    for item in ${thorErrors[@]}
    do
        [[ -z $errStr ]] && errStr="$( echo -e "{\n\"Thor_${action}\" : [\n")"
        errStr=$( echo -e "${errStr}\n\"$item\",")
    done
    [[ -n $errStr ]] && errStr=$( echo -e "${errStr}\n],\n},\n")
    capEngine=THOR_${action}
    printf -v "$capEngine"_ERROR_STR '%s' "${errStr}"

    unset errStr
    for item in ${roxieErrors[@]}
    do
        [[ -z $errStr ]] && errStr="$( echo -e "{\n\"Roxie_${action}\" :\n")"
        errStr=$( echo -e "${errStr}\n\"$item\",")
    done
    [[ -n $errStr ]] && errStr=$( echo -e "${errStr}\n],\n}\n")
    capEngine=ROXIE_${action}
    printf -v "$capEngine"_ERROR_STR '%s' "${errStr}"

    set +x
    IFS=$OLD_IFS
}

collectAllLogs()
{
    logFile=$1
    WriteLog "Collect logs" "$logFile"
    dirName="$HOME/shared/Azure/test-$(date +%Y-%m-%d_%H-%M-%S)";
    [[ ! -d $dirName ]] && mkdir -p $dirName;
    TIME_STAMP=$(date +%s)
    while read p;
    do
        [[ "$p" =~ "mydali" ]] && param="mydali" || param="";
        WriteLog "pod:$p - $param" "$logFile";
        kubectl describe pod $p > $dirName/$p.desc;
        kubectl logs $p $param > $dirName/$p.log;
        kubectl logs -p $p $param > $dirName/$p-prev.log;
    done< <(kubectl get pods | egrep -v 'NAME' | awk '{ print $1 }' )

    kubectl get pods > $dirName/pods.log;
    kubectl get services > $dirName/services.log;
    kubectl describe nodes > $dirName/nodes.desc;
    #minikube logs >  $dirName/all.log 2>&1
    COLLECT_POD_LOGS_TIME=$(( $(date +%s) - $TIME_STAMP ))
    COLLECT_POD_LOGS_TIME_STR="$COLLECT_POD_LOGS_TIME sec $(SecToTimeStr $COLLECT_POD_LOGS_TIME)."
    COLLECT_POD_LOGS_RESULT_STR="Done"
    COLLECT_POD_LOGS_RESULT_REPORT_STR="$COLLECT_POD_LOGS_RESULT_STR in $COLLECT_POD_LOGS_TIME_STR"
    WriteLog "  $COLLECT_POD_LOGS_RESULT_REPORT_STR" "$logFile"
}

destroyResources()
{
    logFile=$1
    msg=$2
    VERBOSE_AKS=$VERBOSE
    [[ -n "$3" ]] && VERBOSE_AKS=$3
    VERBOSE_RESOURCES=$VERBOSE
    [[ -n "$4" ]] && VERBOSE_RESOURCES=$4

    WriteLog "$msg" "$logFile"
    TIME_STAMP=$(date +%s)
    res=$(terraform destroy -var-file=obt-admin.tfvars -auto-approve 2>&1)
    AKS_DESTROY_TIME=$(( $(date +%s) - $TIME_STAMP ))

    if [[ $VERBOSE_AKS -ne 0 ]]
    then
        WriteLog "res:$res" "$logFile"
    else
        WriteLog "$( echo "$res" | egrep ' Resources:')" "$logFile"
    fi
    AKS_DESTROYED_NUM_OF_RESOURCES_STR=$( echo "$res" | egrep ' Resources: ' | awk '{ print $4" resources "$5 }'  | tr -d ',.' )
    AKS_DESTROYED_NUM_OF_RESOURCES=$( echo $AKS_DESTROYED_NUM_OF_RESOURCES_STR | cut -d ' ' -f1)
    AKS_DESTROY_TIME_STR="$AKS_DESTROY_TIME sec $(SecToTimeStr $AKS_DESTROY_TIME)"
    AKS_DESTROY_RESULT_STR="Done"
    AKS_DESTROY_RESULT_REPORT_STR="$AKS_DESTROY_RESULT_STR in $AKS_DESTROY_TIME_STR, $AKS_DESTROYED_NUM_OF_RESOURCES_STR."
    WriteLog "  $AKS_DESTROY_RESULT_REPORT_STR" "$logFile"

    if [[ $START_RESOURCES -eq 1 ]]
    then
        WriteLog "Destroy storage accounts ..." "$logFile"
        pushd modules/storage_accounts > /dev/null
        TIME_STAMP=$(date +%s)
        res=$(terraform destroy -var-file=admin.tfvars -auto-approve 2>&1)
        STORAGE_DESTROY_TIME=$(( $(date +%s) - $TIME_STAMP ))
        if [[ $VERBOSE_RESOURCES -ne 0 ]]
        then
            WriteLog "res:$res" "$logFile"
        else
            WriteLog "$( echo "$res" | egrep ' Resources:')" "$logFile"
        fi
        STORAGE_DESTROYED_NUM_OF_RESOURCES_STR=$( echo "$res" | egrep ' Resources: ' | awk '{ print $4" resources "$5 }'  | tr -d ',.' )
        STORAGE_DESTROYED_NUM_OF_RESOURCES=$( echo $STORAGE_DESTROYED_NUM_OF_RESOURCES_STR | cut -d ' ' -f1)
        
        STORAGE_DESTROY_TIME_STR="$STORAGE_DESTROY_TIME sec $(SecToTimeStr $STORAGE_DESTROY_TIME)"
        STORAGE_DESTROY_RESULT_STR="Done"
        STORAGE_DESTROY_RESULT_REPORT_STR="$STORAGE_DESTROY_RESULT_STR in $STORAGE_DESTROY_TIME_STR, $STORAGE_DESTROYED_NUM_OF_RESOURCES_STR."
        WriteLog "  $STORAGE_DESTROY_RESULT_REPORT_STR" "$logFile"
        popd > /dev/null

        WriteLog "Destroy VNET ..." "$logFile"
        pushd modules/virtual_network > /dev/null
        TIME_STAMP=$(date +%s)
        res=$(terraform destroy -var-file=admin.tfvars -auto-approve 2>&1)
        VNET_DESTROY_TIME=$(( $(date +%s) - $TIME_STAMP ))
        if [[ $VERBOSE_RESOURCES -ne 0 ]]
        then
            WriteLog "res:$res" "$logFile"
        else
            WriteLog "$( echo "$res" | egrep ' Resources:')" "$logFile"
        fi
        VNET_DESTROYED_NUM_OF_RESOURCES_STR=$( echo "$res" | egrep ' Resources: ' | awk '{ print $4" resources "$5 }'  | tr -d ',.' )
        VNET_DESTROYED_NUM_OF_RESOURCES=$( echo $VNET_DESTROYED_NUM_OF_RESOURCES_STR | cut -d ' ' -f1)
        
        VNET_DESTROY_TIME_STR="$VNET_DESTROY_TIME sec $(SecToTimeStr $VNET_DESTROY_TIME)"
        VNET_DESTROY_RESULT_STR="Done"
        VNET_DESTROY_RESULT_REPORT_STR="$VNET_DESTROY_RESULT_STR in $VNET_DESTROY_TIME_STR, $VNET_DESTROYED_NUM_OF_RESOURCES_STR."
        WriteLog "  $VNET_DESTROY_RESULT_REPORT_STR" "$logFile"
        popd > /dev/null
    fi

}

GenerateReports()
{
    WriteLog "Generate reports..." "$logFile"
    cd $OBT_DIR
    TIME_STAMP=$(date +%s)
    report1=$(<./regressAksReport.templ)
    # Do it with 'eval'
    eval "resolved1=\"$report1\""
    echo "$resolved1" > regressAks-$START_DATE.report

    report2=$(<./regressAksReportJson.templ)
    eval "resolved2=\"$report2\""
    echo "$resolved2" > regressAks-$START_DATE.json

    REPORT_GENERATION_TIME=$(( $(date +%s) - $TIME_STAMP ))
    REPORT_GENERATION_TIME_STR="$REPORT_GENERATION_TIME sec $(SecToTimeStr $REPORT_GENERATION_TIME)."
    WriteLog "  Report generation is done in $REPORT_GENERATION_TIME_STR." "$logFile"
}

PrintSetting()
{
    name=$1
    log=$2
    local str=$( printf "%-25s : %s" "$name" "${!name}" )
    WriteLog "$str" "$log"
}

handler()
{
    echo ""
    echo "*************************"
    echo "*  Ne vicelj ma' Bela.  *"
    echo "*************************"
    echo ""
}


#trap handler 2; 
#set -x;
OBT_DIR=$(pwd)
START_DATE=$(date +%Y-%m-%d_%H-%M-%S)
logFile=$OBT_DIR/regressAks-$START_DATE.log

getLogs=0
if [[ -f ./settings.sh && ( "$OBT_ID" =~ "OBT" ) ]]
then
    WriteLog "We are in OBT environment" "$logFile"
    . ./settings.sh
    SOURCE_DIR=$SOURCE_HOME
    SUITEDIR=$TEST_ENGINE_HOME
    RTE_DIR=$REGRESSION_TEST_ENGINE_HOME
    QUERY_STAT2_DIR="$OBT_BIN_DIR"
    PERFSTAT_DIR="$HOME/Perfstat-Azure/"
    PKG_DIR=$OBT_BIN_DIR/PkgCache
else
    WriteLog "Non OBT environment, like local VM/BM" "$logFile"
    SOURCE_DIR="$HOME/HPCC-Platform"
    SUITEDIR="$SOURCE_DIR/testing/regress/"
    RTE_DIR="$HOME/RTE-NEWER"
    [[ ! -d $RTE_DIR ]] && RTE_DIR="$HOME/RTE"
    [[ ! -d $RTE_DIR ]] && RTE_DIR=$SUITEDIR
    PKG_DIR="$HOME/HPCC-Platform-build/"

    QUERY_STAT2_DIR="$RTE_DIR"
    [[ ! -f $QUERY_STAT2_DIR/QueryStat2.py ]] && QUERY_STAT2_DIR=$(pwd)
    [[ ! -f $QUERY_STAT2_DIR/QueryStat2.py ]] && QUERY_STAT2_DIR=''
    PERFSTAT_DIR="Azure/"

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

#TERRAFORM_DIR=~/terraform-azurerm-hpcc-aks
#TERRAFORM_DIR=~/terraform-azurerm-hpcc-new
#TERRAFORM_DIR=~/terraform-azurerm-hpcc-pr-28
TERRAFORM_DIR=~/terraform-azurerm-hpcc

RTE_CONFIG="./ecl-test-k8s.json"
RTE_PQ="--pq 2"
RTE_TIMEOUT="--timeout 1200"
RTE_QUICK_TEST_SET='teststdlib*'
RTE_QUICK_TEST_SET='pipe* httpcall* soapcall* roxie* badindex.ecl'
# Alternatives
#RTE_QUICK_TEST_SET='alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall*'
#RTE_QUICK_TEST_SET='alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall* teststdlib*'

RTE_EXCLUSIONS='--ef pipefail.ecl -e embedded-r,embedded-js,3rdpartyservice,mongodb,spray'

INTERFACE=$(ip -o link show | awk -F': ' '{ print $2 }' | grep '^en')
LOCAL_IP="$(ip addr show $INTERFACE | grep 'inet\b' | awk '{ print $2 }' | cut -d/ -f1)"

# Timeouts
VNET_DEPLOY_TIMEOUT="5.0m"          # Usually <2 minutes
STORAGE_DEPLOY_TIMEOUT="7.0m"   # Usually <3 minutes
AKS_DEPLOY_TIMEOUT="30.0m"          # Usually <12 Minutes

#set -x
INTERACTIVE=0
FULL_REGRESSION=1
TAG='<latest>'
VERBOSE=0
DEBUG=0
START_RESOURCES=0
IGNORE_AUTOMATION_ERROR=0   # Should control with a CLI parameter

while [ $# -gt 0 ]
do
    param=$1
    param=${param//-/}
    upperParam=${param^^}
    #WriteLog "Param: ${upperParam}" "/dev/null"
    case $upperParam in
        I)  INTERACTIVE=1
            ;;
               
        Q)  FULL_REGRESSION=0
            ;;
            
        DT) shift
            AKS_DEPLOY_TIMEOUT=$1
            ;;
            
        T)  shift
            TAG=$1
            ;;

        V) VERBOSE=1
            ;;
           
        D) DEBUG=1
            ;;
           
        R) START_RESOURCES=1
            ;;

        H) usage
           exit 0
           ;;

        *)
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
PrintSetting "QUERY_STAT2_DIR" "$logFile"
PrintSetting "PERFSTAT_DIR" "$logFile"
PrintSetting "TERRAFORM_DIR" "$logFile"
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
PrintSetting "VNET_DEPLOY_TIMEOUT" "$logFile"
PrintSetting "STORAGE_DEPLOY_TIMEOUT" "$logFile"
PrintSetting "AKS_DEPLOY_TIMEOUT" "$logFile"
PrintSetting "INTERACTIVE" "$logFile"
PrintSetting "FULL_REGRESSION" "$logFile"
PrintSetting "TAG" "$logFile"
PrintSetting "VERBOSE" "$logFile"
PrintSetting "START_RESOURCES" "$logFile"
PrintSetting "IGNORE_AUTOMATION_ERROR" "$logFile"  # !!!!

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
        resMsg=$(helm search repo --devel  --version=$tag hpcc/hpcc |  egrep $tag )

        if [[ -n "$resMsg" ]]
        then
            WriteLog "  The helm chart is ready, use this tag." "$logFile"
            found=1
        else
            WriteLog "  The helm chart not found." "$logFile"
            WriteLog "  resMsg:'$resMsg'"  "$logFile"
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
                WriteLog "  resMsg: '$resMsg'" "$logFile"
                WriteLog "  Step back one tag." "$logFile"
            fi        
        else
            WriteLog "  It has not deployable image, step back one tag." "$logFile"
        fi
    done< <(git tag --sort=-creatordate | egrep 'community_'$latestMajorMinor | head -n 10 )
fi

if [[ $found -ne 1 ]]
then
    WriteLog "Can't find a tag with deployable image in: " "$logFile"
    WriteLog "$(git tag --sort=-creatordate | egrep 'community_'$latestBranch | head -n 10). \nExit." "$logFile"
    exit 2
else
    # We have the latest version of latest release branch in '<major>.<minor>.<point>' form
    TAG_TO_TEST="$tagToTest$suffix"
    WriteLog "Final tag to test: $TAG_TO_TEST" "$logFile"
    
fi

# Use that version for get the lates tag of the latest branch
res=$( git checkout $tagToTest  2>&1 )
WriteLog "checkout $tagToTest\nres: $res" "$logFile"
popd > /dev/null

base=$tag
# Remove the point build
baseMajorMinor=${base%.*}
pkg="*community?$baseMajorMinor*$PKG_EXT"
WriteLog "base: ${base}" "$logFile"

WriteLog "base major.minor:$baseMajorMinor" "$logFile"
WriteLog "pkg:$pkg" "$logFile"
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
            WriteLog "Done." "$logFile"
        else
            WriteLog "Platform install package:$pkd not found, exit." "$logFile"
            exit 1
        fi
    fi
fi

WriteLog "Update obt-admin.tfvars..." "$logFile"
pushd $TERRAFORM_DIR > /dev/null

WriteLog "$(cp -vf $OBT_DIR/obt-admin.tfvars . 2>&1)" "$logFile"
WriteLog "$(cp -v obt-admin.tfvars obt-admin.tfvars-back 2>&1)" "$logFile"
WriteLog "$(rm -v terraform.tfstate* 2>&1)" "$logFile"

sed -i -e 's/^\(\s*\)version\s*=\s*\(.*\)/\1version = "'"${base}"'"/g' -e 's/^\(\s*\)image_version\s*=\s*\(.*\)/\1image_version = "'"${base}"'"/g' obt-admin.tfvars
WriteLog "$(egrep '^\s*version ' obt-admin.tfvars)" "$logFile"
WriteLog "  Done." "$logFile"

WriteLog "Upgrade terraform..." "$logFile"
TIME_STAMP=$(date +%s)
WriteLog "$(terraform init -upgrade 2>&1)" "$logFile"
TERRAFORM_UPGRADE_TIME=$(( $(date +%s) - $TIME_STAMP ))
TERRAFORM_UPGRADE_TIME_STR="$TERRAFORM_UPGRADE_TIME sec $(SecToTimeStr $TERRAFORM_UPGRADE_TIME)."
TERRAFORM_UPGRADE_RESULT_STR="Done"
TERRAFORM_VERSION=$(terraform --version | head -n 1)
TERRAFORM_UPGRADE_RESULT_REPORT_STR="$TERRAFORM_UPGRADE_RESULT_STR in $TERRAFORM_UPGRADE_TIME_STR, version: $TERRAFORM_VERSION"
WriteLog "  $TERRAFORM_UPGRADE_RESULT_REPORT_STR" "$logFile"

# Check login status
loginCheck=$(az ad signed-in-user show)
retCode=$?
WriteLog "$loginCheck" "$logFile"

if [[ $retCode != 0 ]] 
then
    # Not logged in, login
    az login
fi

# Check account
account=$( az account list -o table | egrep 'us-hpccplatform-dev' )
WriteLog "account: $account" "$logFile"

[[ $( echo $account | awk '{ print $6 }' ) != "True" ]] && (WriteLog "us-hpccplatform-dev is not the default"  "$logFile"; exit 1) 

if [[ $START_RESOURCES -eq 1 ]]
then
    WriteLog "Create VNET ... (timeout is $VNET_DEPLOY_TIMEOUT)" "$logFile"
    pushd modules/virtual_network > /dev/null
    TIME_STAMP=$(date +%s)
    res=$(timeout  -s 15 --preserve-status $VNET_DEPLOY_TIMEOUT terraform apply -var-file=admin.tfvars -auto-approve 2>&1)
    VNET_START_TIME=$(( $(date +%s) - $TIME_STAMP ))
    if [[ $VERBOSE -ne 0 ]]
    then 
        WriteLog "res:$res" "$logFile"
    else
        WriteLog "$( echo "$res" | egrep ' Resources:')" "$logFile"
    fi
    VNET_NUM_OF_RESOURCES_STR=$( echo "$res" | egrep ' Resources: ' | awk '{ print $4" resources "$5 }'  | tr -d ',.' )
    VNET_NUM_OF_RESOURCES=$( echo $VNET_NUM_OF_RESOURCES_STR | cut -d ' ' -f1)
    VNET_START_TIME_STR="$VNET_START_TIME sec $(SecToTimeStr $VNET_START_TIME)"
    VNET_START_RESULT_STR="Done"
    VNET_START_RESULT_REPORT_STR="$VNET_START_RESULT_STR in $VNET_START_TIME_STR, $VNET_NUM_OF_RESOURCES_STR"
    WriteLog "  $VNET_START_RESULT_REPORT_STR" "$logFile"
    popd > /dev/null
     
    WriteLog "Create storage accounts ... (timeout is $STORAGE_DEPLOY_TIMEOUT)" "$logFile"
    pushd modules/storage_accounts > /dev/null
    TIME_STAMP=$(date +%s)
    res=$(timeout  -s 15 --preserve-status $STORAGE_DEPLOY_TIMEOUT terraform apply -var-file=admin.tfvars -auto-approve 2>&1)
    STORAGE_START_TIME=$(( $(date +%s) - $TIME_STAMP ))
    if [[ $VERBOSE -ne 0 ]]
    then 
        WriteLog "res:$res" "$logFile"
    else
        WriteLog "$( echo "$res" | egrep ' Resources:')" "$logFile"
    fi
    STORAGE_NUM_OF_RESOURCES_STR=$( echo "$res" | egrep ' Resources: ' | awk '{ print $4" resources "$5 }'  | tr -d ',.' )
    STORAGE_NUM_OF_RESOURCES=$( echo $STORAGE_NUM_OF_RESOURCES_STR | cut -d ' ' -f1)
    STORAGE_START_TIME__STR="$STORAGE_START_TIME sec $(SecToTimeStr $STORAGE_START_TIME)"
    STORAGE_START_RESULT_STR="Done"
    STORAGE_START_RESULT_REPORT_STR="$STORAGE_START_RESULT_STR in $STORAGE_START_TIME__STR, $STORAGE_NUM_OF_RESOURCES_STR"
    WriteLog "  $STORAGE_START_RESULT_REPORT_STR" "$logFile"
    popd > /dev/null

fi


WriteLog "Deploy HPCC ... (timeout is $AKS_DEPLOY_TIMEOUT)" "$logFile"
TIME_STAMP=$(date +%s)
res=$( timeout  -s 15 --preserve-status $AKS_DEPLOY_TIMEOUT  terraform apply -var-file=obt-admin.tfvars -auto-approve 2>&1 )
#res=$( times terraform apply -var-file=obt-admin.tfvars -auto-approve )
#res=$( terraform apply -var-file=obt-admin.tfvars -auto-approve )
retCode=$?
AKS_START_TIME=$(( $(date +%s) - $TIME_STAMP ))
AKS_START_TIME_STR="$AKS_START_TIME sec $(SecToTimeStr $AKS_START_TIME)"
isError=$( echo "$res" | egrep 'Error:' )
# TO-DO What to do if more than the automation error happens?
isAutomationError=$( echo "isError" |egrep -c 'creating Automation Account')
WriteLog "retCode: $retCode, ignoreAutomationError: $IGNORE_AUTOMATION_ERROR, isAutomationError: $isAutomationError" "$logFile"

AKS_NUM_OF_RESOURCES_STR=$( echo "$res" | egrep ' Resources: ' | awk '{ print $4" resources "$5 }'  | tr -d ',.' )
AKS_NUM_OF_RESOURCES=$( echo $AKS_NUM_OF_RESOURCES_STR | cut -d ' ' -f1)

if [[ ($retCode -eq 0) || ( ($IGNORE_AUTOMATION_ERROR -eq 1) && ($isAutomationError -ne 0 )) ]]
then
   [[ ( ($IGNORE_AUTOMATION_ERROR -eq 1) && ($isAutomationError -ne 0 )) ]] && WriteLog "Automation error ignored." "$logFile"
    if [[ $VERBOSE -ne 0 ]]
    then 
        WriteLog "res:$res" "$logFile"
    else
        WriteLog "$( echo "$res" | egrep ' Resources:')" "$logFile"
    fi
    AKS_START_RESULT_STR="Done"
    AKS_START_RESULT_REPORT_STR="$AKS_START_RESULT_STR in $AKS_START_TIME_STR, $AKS_NUM_OF_RESOURCES_STR."
    WriteLog "  $AKS_START_RESULT_REPORT_STR" "$logFile"
else
    WriteLog "Error in deploy hpcc. \nRet code is: $retCode." "$logFile"
    WriteLog "res:$res" "$logFile"
    ERROR_STR=$(echo "$res" | egrep -A 4 'Error: ')
    AKS_START_RESULT_STR="Failed"
    AKS_START_ERROR_STR="\n      - Error: $ERROR_STR"
    AKS_START_RESULT_REPORT_STR="$AKS_START_RESULT_STR in $AKS_START_TIME_STR $AKS_START_ERROR_STR."
    WriteLog "  $AKS_START_RESULT_REPORT_STR" "$logFile"

    collectAllLogs "$logFile"

    destroyResources "$logFile" "Destroy AKS to remove leftovers ..." "1" 
    
    ECLWATCH_START_RESULT_STR="Skipped based on error in deploy AKS."
    ECLWATCH_START_RESULT_REPORT_STR="$ECLWATCH_START_RESULT_STR"
    
    SETUP_RESULT_STR="$ECLWATCH_START_RESULT_STR"
    SETUP_RESULT_REPORT_STR="$ECLWATCH_START_RESULT_STR"
    
    QUERIES_PUBLISH_RESULT_STR="$ECLWATCH_START_RESULT_STR"
    QUERIES_PUBLISH_REPORT_STR="$ECLWATCH_START_RESULT_STR"

    REGRESS_RESULT_STR="$ECLWATCH_START_RESULT_STR"
    REGRESS_RESULT_REPORT_STR="$ECLWATCH_START_RESULT_STR"
    
    GenerateReports
    WriteLog "Exit." "$logFile"
    exit 1
fi

cred=$( echo "$res" | egrep 'get-credentials ' | tr -d "'" | cut -d '=' -f 2 | tr -d '"[]' )
if [[ -n "$cred" ]]
then
    WriteLog "cred: $cred" "$logFile"
    WriteLog "Is there '(local-exec)': $( echo $cred | egrep -c 'local-exec')" "$logFile"
    if [[ $( echo $cred | egrep -c 'local-exec') -eq 0 ]]
    then
        cred="$cred --overwrite-existing"
        WriteLog "credentials: '$cred'" "$logFile"
        res=$( eval ${cred} 2>&1 )
        WriteLog "$res" "$logFile"
    else
        WriteLog "The credentials already aquired." "$logFile"
    fi
else
    WriteLog "Error in deploy hpcc." "$logFile"
    VERBOSE=1
    destroyResources "$logFile" "Destroy AKS to remove leftovers ..." "1"

    GenerateReports
    WriteLog "Exit." "$logFile"
    exit 1
fi

WriteLog "Wait until everything is up..." "$logFile"
tryCount=30
delay=10
expected=0
running=0
while true; 
do  
    while read a b c; 
    do 
        running=$(( $running + $a )); 
        expected=$(( $expected + $b )); 
        #printf "%-45s: %s/%s  %s\n" "$c" "$a" "$b"  $( [[ $a -ne $b ]] && echo "starting" || echo "up" ) ; 
    done < <( kubectl get pods 2>&1| egrep -v 'NAME' | awk '{ print $2 " " $1 }' | tr "/" " ");
    WriteLog "$( printf 'Expected: %s, running %s (%2d)\n' $expected $running $tryCount)" "$logFile"
    [[ $running -ne 0 && $running -eq $expected ]] && break || sleep ${delay}; 
    tryCount=$(( $tryCount - 1)); 
    [[ $tryCount -eq 0 ]] && break; 
    expected=0; 
    running=0; 
done

WriteLog "$(printf 'Expected: %s, running %s (%2d)\n' $expected $running $tryCount )" "$logFile"

sleep 10

if [[ ($expected -eq $running) && ($running -ne 0)]]
then
    # Pods are up
    WriteLog "Platform is up, run tests." "$logFile"

    pushd $RTE_DIR > /dev/null
    WriteLog "cwd: $(pwd)" "$logFile"

    WriteLog "Start ECLWatch." "$logFile"
    TIME_STAMP=$(date +%s)
    res=$(kubectl annotate service eclwatch --overwrite service.beta.kubernetes.io/azure-load-balancer-internal="false")
    WriteLog "res:$res" "$logFile"

    sleep 60
    
    ip=$( kubectl get svc | egrep 'eclwatch' | awk '{ print $4 }' )
    WriteLog "ip: $ip" "$logFile"
    port=8010
    WriteLog "port: $port" "$logFile"
    WriteLog "URL: http://$ip:$port" "$logFile"
    #echo "Press <Enter> to continue"
    #read
    ECLWATCH_START_TIME=$(( $(date +%s) - $TIME_STAMP ))
    ECLWATCH_START_TIME_STR="$ECLWATCH_START_TIME sec $(SecToTimeStr $ECLWATCH_START_TIME)"
    ECLWATCH_START_RESULT_STR="Done"
    ECLWATCH_START_RESULT_REPORT_STR="$ECLWATCH_START_RESULT_STR in $ECLWATCH_START_TIME_STR"
    WriteLog "  $ECLWATCH_START_RESULT_REPORT_STR" "$logFile"
    
    if [[ -z "$ip" ]] 
    then
        GenerateReports
        exit 1
    fi
    # Give it some more time
    sleep 30

    WriteLog "Run tests." "$logFile"
    #pwd

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
    ProcessLog "$res" SETUP_RESULT_REPORT_STR $action
    WriteLog "action: '$action'" "$logFile"
    WriteLog "SETUP_RESULT_REPORT_STR:\n$SETUP_RESULT_REPORT_STR" "$logFile"
    
    
    NUMBER_OF_PUBLISHED=0
    if [[ $setupPass -eq 1 ]]
    then
        # Experimental code for publish Queries to Roxie
        WriteLog "Publish queries to Roxie ..." "$logFile"
        # To proper publish we need in SUITEDIR/ecl to avoid compile error for new queries
        pushd $SUITEDIR/ecl
        WriteLog "pwd: '$(pwd)', dirs: '$(dirs)'" "$logFile"
        TIME_STAMP=$(date +%s)
        while read query
        do
            WriteLog "Query: $query" "$logFile"
            res=$( ecl publish -t roxie --server $ip --port $port $query 2>&1 )
            WriteLog "$res" "$logFile"
            NUMBER_OF_PUBLISHED=$(( NUMBER_OF_PUBLISHED + 1 ))
        done< <(egrep -l '\/\/publish' setup/*.ecl)
        
        QUERIES_PUBLISH_TIME=$(( $(date +%s) - $TIME_STAMP ))
        popd
        WriteLog "pwd: '$(pwd)', dirs: '$(dirs)'" "$logFile"
        QUERIES_PUBLISH_TIME_STR="$QUERIES_PUBLISH_TIME sec $(SecToTimeStr $QUERIES_PUBLISH_TIME)"
        QUERIES_PUBLISH_RESULT_STR="Done"
        QUERIES_PUBLISH_RESULT_SUFFIX_STR="$NUMBER_OF_PUBLISHED queries published to Roxie."
        QUERIES_PUBLISH_RESULT_REPORT_STR="$QUERIES_PUBLISH_RESULT_STR in $QUERIES_PUBLISH_TIME_STR, $QUERIES_PUBLISH_RESULT_SUFFIX_STR"
        WriteLog "  $QUERIES_PUBLISH_RESULT_REPORT_STR" "$logFile"

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
            WriteLog "Run regression quick sanity chceck with ($RTE_QUICK_TEST_SET)" "$logFile"
            # For sanity testing on all engines
            REGRESS_CMD="./ecl-test query --server $ip:$port --suiteDir $SUITEDIR $RTE_EXCLUSIONS --config $RTE_CONFIG $RTE_PQ $RTE_TIMEOUT --loglevel info $RTE_QUICK_TEST_SET"
            res=$( ./ecl-test query --server $ip:$port  --suiteDir $SUITEDIR $RTE_EXCLUSIONS --config $RTE_CONFIG $RTE_PQ $RTE_TIMEOUT --loglevel info $RTE_QUICK_TEST_SET 2>&1 )
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
        ProcessLog "$res" REGRESS_RESULT_REPORT_STR $action
        WriteLog "action: '$action'" "$logFile"
        WriteLog "REGRESS_RESULT_REPORT_STR:\n$REGRESS_RESULT_REPORT_STR" "$logFile"

    else
        WriteLog "Setup is failed, skip regression tessting." "$logFile"
        QUERIES_PUBLISH_RESULT_STR="Skipped based on setup error"
        QUERIES_PUBLISH_TIME=0
        QUERIES_PUBLISH_TIME_STR="$QUERIES_PUBLISH_TIME sec $(SecToTimeStr $QUERIES_PUBLISH_TIME)"
        QUERIES_PUBLISH_REPORT_STR="Skipped based on setup error"
        
        REGRESS_START_TIME=$( date "+%H:%M:%S")
        REGRESS_RESULT_STR="Skipped based on setup error"
        REGRESS_RESULT_REPORT_STR="$REGRESSION_RESULT_STR"
    fi

    if [[ -n "$QUERY_STAT2_DIR" ]]
    then
        WriteLog "Run QueryStat2.py ..." "$logFile"
        pushd $QUERY_STAT2_DIR > /dev/null
        TIME_STAMP=$(date +%s)
        res=$(./QueryStat2.py -a -t $ip --port $port --obtSystem=Azure --buildBranch=$base -p Azure/ --addHeader --compileTimeDetails 1 --timestamp)
        QUERY_STAT2_TIME=$(( $(date +%s) - $TIME_STAMP ))
        WriteLog "${res}" "$logFile"
        QUERY_STAT2_TIME_STR="$QUERY_STAT2_TIME sec $(SecToTimeStr $QUERY_STAT2_TIME)."
        QUERY_STAT2_RESULT_STR="Done"
        QUERY_STAT2_RESULT_REPORT_STR="$QUERY_STAT2_RESULT_STR in $QUERY_STAT2_TIME_STR"
        WriteLog "  $QUERY_STAT2_RESULT_REPORT_STR" "$logFile"
        popd > /dev/null
    else
        WriteLog "Missing QueryStat2.py, skip cluster and compile time query." "$logFile"
    fi

    popd > /dev/null
else
    WriteLog "Problem with pods start" "$logFile"
    getLogs=1
fi

# Get all logs:
if [[ ${getLogs} -ne 0 ]]
then
    collectAllLogs "$logFile"
else
    WriteLog "Skip log collection" "$logFile"
    COLLECT_POD_LOGS_TIME=0
    COLLECT_POD_LOGS_TIME_STR="$COLLECT_POD_LOGS_TIME sec $(SecToTimeStr $COLLECT_POD_LOGS_TIME)."
    COLLECT_POD_LOGS_RESULT_STR="PODs log collection skipped"
    COLLECT_POD_LOGS_RESULT_REPORT_STR="$COLLECT_POD_LOGS_RESULT_STR in $COLLECT_POD_LOGS_TIME_STR"
    WriteLog "  $COLLECT_POD_LOGS_RESULT_REPORT_STR" "$logFile"
fi    

if [[ $INTERACTIVE -eq 1 ]]
then
    WriteLog "Testing finished, press <Enter> to stop pods.\n(After 60 seconds it will continue)" "$logFile"
    read -t 60
fi

destroyResources "$logFile" "To destroy AKS is started ..."

TIME_STAMP=$(date +%s)
# Wait until everyting is down
tryCount=30  # To avoid infinite loop if something went wrong (connection, AKS, Azure, M$)
while true; 
do 
    date;  
    expected=0; 
    running=0; 
    while read a b c; 
    do 
        running=$(( $running + $a )); 
        expected=$(( $expected + $b )); 
        #printf "%-45s: %s/%s  %s\n" "$c" "$a" "$b"  $( [[ $a -ne $b ]] && echo "starting" || echo "up" ) ; 
    done < <( kubectl get pods 2>&1 | egrep -v 'NAME' | awk '{ print $2 " " $1 }' | tr "/" " ");
    WriteLog "$( printf '\nExpected: %s, running %s (%s)\n' $expected $running $tryCount)"  "$logFile";

    [[ $expected -eq 0 ]] && break || sleep 10; 
    tryCount=$(( $tryCount - 1)); 
    [[ $tryCount -eq 0 ]] && break; 
done;

if [[ $expected -eq 0 ]]
then
    WriteLog "AKS system is down." "$logFile"
else
   WriteLog "Something went wrong. Try to destroy AKS manually via https://portal.azure.com ." "$logFile"
fi

# IS IT CORRECT?
DESTROY_AKS_TIME=$(( $(date +%s) - $TIME_STAMP ))
WriteLog "  Done in $DESTROY_AKS_TIME sec $(SecToTimeStr $DESTROY_AKS_TIME)." "$logFile"

if [[ -n "$QUERY_STAT2_DIR" ]]
then
    WriteLog "Start log processor..." "$logFile"
    pushd $QUERY_STAT2_DIR > /dev/null
    if [ -f regressK8sLogProcessor.py ]
    then
        TIME_STAMP=$(date +%s)
        res=$( ./regressK8sLogProcessor.py --path ./  2>&1 )
        WriteLog "${res}" "$logFile"
        WriteLog "  End." "$logFile"
        REGRESS_LOG_PROCESSING_TIME=$(( $(date +%s) - $TIME_STAMP ))
        REGRESS_LOG_PROCESSING_TIME_STR="$REGRESS_LOG_PROCESSING_TIME sec $(SecToTimeStr $REGRESS_LOG_PROCESSING_TIME)."
        REGRESS_LOG_PROCESSING_RESULT_STR="Done"
        REGRESS_LOG_PROCESSING_RESULT_REPORT_STR="$REGRESS_LOG_PROCESSING_RESULT_STR in $REGRESS_LOG_PROCESSING_TIME_STR."
        WriteLog "  $REGRESS_LOG_PROCESSING_RESULT_REPORT_STR" "$logFile"
    else
        WriteLog "regressK8sLogProcessor.py not found." "$logFile"
    fi
    popd > /dev/null
else
    WriteLog "Missing OBT binary directory, skip Minikube test log processing." "$logFile"
fi

trap 2

END_TIME=$( date "+%H:%M:%S")
RUN_TIME=$((  $(date +%s) - $START_TIME_SEC ))
RUN_TIME_STR="$RUN_TIME sec $(SecToTimeStr $RUN_TIME)"
END_TIME_STR="$END_TIME, run time: $RUN_TIME_STR"

GenerateReports

WriteLog "End ($RUN_TIME_STR)." "$logFile"
WriteLog "==================================" "$logFile"
