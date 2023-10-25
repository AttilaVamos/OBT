#!/usr/bin/bash

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
    WriteLog "  $0 [-i] [-q] [-h]" "/dev/null"
    WriteLog "where:" "/dev/null"
    WriteLog " -i       - Interactive, stop before unistall with terraform." "/dev/null"
    WriteLog " -f       - Execute full Regression Suite." "/dev/null"
    WriteLog " -t <tag> - Manually specify the tag (e.g.: 9.4.0-rc7) to be test." "/dev/null"
    WriteLog " -v       - Show more logs (about PODs deploy and destroy)." "/dev/null"
    WriteLog " -h       - This help." "/dev/null"
    WriteLog " " "/dev/null"
}

#set -x;
logFile=$(pwd)/regressAks-$(date +%Y-%m-%d_%H-%M-%S).log

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
    EXCLUSIONS='--ef pipefail.ecl -e plugin,3rdparty,embedded,python2,spray'
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
    EXCLUSIONS='--ef pipefail.ecl -e plugin,3rdparty,embedded,python2,spray'

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
fi    

TERRAFORM_DIR=~/terraform-azurerm-hpcc-aks
TERRAFORM_DIR=~/terraform-azurerm-hpcc
TERRAFORM_DIR=~/terraform-azurerm-hpcc-new
CONFIG="./ecl-test-k8s.json"
PQ="--pq 2"
TIMEOUT="--timeout 1200"
QUICK_TEST_SET='teststdlib*'
QUICK_TEST_SET='pipe* httpcall* soapcall* roxie* badindex.ecl'
#QUICK_TEST_SET='alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall*'
#QUICK_TEST_SET='alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall* teststdlib*'

WriteLog "Start          : $0 $*" "$logFile"
WriteLog "SOURCE_DIR     : $SOURCE_DIR" "$logFile"
WriteLog "SUITEDIR       : $SUITEDIR" "$logFile"
WriteLog "RTE_DIR        : $RTE_DIR" "$logFile"
WriteLog "QUERY_STAT2_DIR: $QUERY_STAT2_DIR" "$logFile"
WriteLog "PERFSTAT_DIR   : $PERFSTAT_DIR" "$logFile"
WriteLog "QUICK_TEST_SET : $QUICK_TEST_SET" "$logFile"
WriteLog "EXCLUSIONS     : $EXCLUSIONS" "$logFile"
WriteLog "PKG_DIR        : $PKG_DIR" "$logFile"
WriteLog "PKG_EXT        : $PKG_EXT" "$logFile"
WriteLog "PKG_INST_CMD   : $PKG_INST_CMD" "$logFile"
WriteLog "PKG_QRY_CMD    : $PKG_QRY_CMD" "$logFile"
WriteLog "PKG_REM_CMD    : $PKG_REM_CMD" "$logFile"
WriteLog "CONFIG         : $CONFIG" "$logFile"
WriteLog "PQ             : $PQ" "$logFile"
WriteLog "TIMEOUT        : $TIMEOUT" "$logFile"

#set -x
INTERACTIVE=0
FULL_REGRESSION=0
TAG='<latest>'
VERBOSE=0

while [ $# -gt 0 ]
do
    param=$1
    param=${param//-/}
    upperParam=${param^^}
    #WriteLog "Param: ${upperParam}" "/dev/null"
    case $upperParam in
        I)  INTERACTIVE=1
            ;;
               
        F)  FULL_REGRESSION=1
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

WriteLog "INTERACTIVE    : $INTERACTIVE" "$logFile"
WriteLog "FULL_REGRESSION: $FULL_REGRESSION" "$logFile"
WriteLog "TAG            : $TAG" "$logFile"
WriteLog "VERBOSE        : $VERBOSE" "$logFile"

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
        WriteLog "  It has deployable image, use this." "$logFile"
        found=1
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
            WriteLog "  It has deployable image, use this." "$logFile"
            found=1
            break
        else
            WriteLog "  It has not deployable image, step back one tag." "$logFile"
        fi
    done< <(git tag --sort=-creatordate | egrep 'community_'$latestBranch | head -n 10 )
fi

if [[ $found -ne 1 ]]
then
    WriteLog "Can't find a tag with deployable image in: " "$logFile"
    WriteLog "$(git tag --sort=-creatordate | egrep 'community_'$latestBranch | head -n 10). \nExit." "$logFile"
    exit 2
else
    # We have the latest version of latest release branch in '<major>.<minor>.<point>' form
    WriteLog "Final tag to test: $tagToTest$suffix" "$logFile"
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

WriteLog "$(cp -v obt-admin.tfvars obt-admin.tfvars-back 2>&1)" "$logFile"
    
sed -i -e 's/^\(\s*\)version\s*=\s*\(.*\)/\1version = "'"${base}"'"/g' obt-admin.tfvars
WriteLog "$(egrep '^\s*version ' obt-admin.tfvars)" "$logFile"
WriteLog "  Done." "$logFile"

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

#WriteLog "Update helm repo..." "$logFile"
#res=$(helm repo update 2>&1)
#WriteLog "$res" "$logFile"

WriteLog "Deploy HPCC ..." "$logFile"
res=$( terraform apply -var-file=obt-admin.tfvars -auto-approve )
if [[ $VERBOSE -ne 0 ]]
then 
    WriteLog "res:$res" "$logFile"
else
    WriteLog "$( echo "$res" | egrep ' Resources:')" "$logFile"
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
    WriteLog "Destroy AKS to remove leftovers ..." "$logFile"
    res=$(terraform destroy -var-file=obt-admin.tfvars -auto-approve 2>&1)
    WriteLog "${res}" "$logFile"
    WriteLog "  Done, exit." "$logFile"
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
    res=$(kubectl annotate service eclwatch --overwrite service.beta.kubernetes.io/azure-load-balancer-internal="false")
    WriteLog "res:$res" "$logFile"

    sleep 60
    
    ip=$( kubectl get svc | egrep 'eclwatch' | awk '{ print $4 }' )
    WriteLog "ip: $ip" "$logFile"
    port=8010
    WriteLog "port: $port" "$logFile"
    #echo "Press <Enter> to continue"
    #read

    [[ -z "$ip" ]] && exit 1

    # Give it some more time
    sleep 30

    WriteLog "Run tests." "$logFile"
    #pwd

    setupPass=1
    WriteLog "Run regression setup ..." "$logFile"
    res=$( ./ecl-test setup --server $ip:$port --suiteDir $SUITEDIR --config $CONFIG  $PQ --timeout 900 --loglevel info 2>&1 )
    retCode=$?
    isError=$( echo "${res}" | egrep -c 'Fail ' )
    WriteLog "retCode: ${retCode}, isError: ${isError}" "$logFile"
    if [[ ${retCode} -ne 0  || ${isError} -ne 0 ]] 
    then
        getLogs=1
        setupPass=0
    fi
    _res=$(echo "$res" | egrep 'Suite:|Queries:|Passing:|Failure:|Elapsed|Fail ' )
    WriteLog "$_res" "$logFile"

    if [[ $setupPass -eq 1 ]]
    then
        # Experimental code for publish Queries to Roxie
        WriteLog "Publish queries to Roxie ..." "$logFile"
        # To proper publish we need in SUITEDIR/ecl to avoid compile error for new queries
        pushd $SUITEDIR/ecl
        while read query
        do
            WriteLog "Query: $query" "$logFile"
            res=$( ecl publish -t roxie --server $ip --port $port $query 2>&1 )
            WriteLog "$res" "$logFile"
        done< <(egrep -l '\/\/publish' setup/*.ecl)
        popd
        WriteLog "  Done." "$logFile"

        # Regression stage
        if [[ $FULL_REGRESSION -eq 1 ]]
        then
            WriteLog "Run Regression Suite ..." "$logFile"
            # For full regression on hthor
            res=$( ./ecl-test run --server $ip:$port $EXCLUSIONS --suiteDir $SUITEDIR --config $CONFIG $PQ $TIMEOUT --loglevel info 2>&1 )
        else
            WriteLog "Run regression quick sanity chceck with ($QUICK_TEST_SET)" "$logFile"
            # For sanity testing on all engines
            res=$( ./ecl-test query --server $ip:$port $EXCLUSIONS --suiteDir $SUITEDIR --config $CONFIG $PQ $TIMEOUT --loglevel info $QUICK_TEST_SET 2>&1 )
        fi

        retCode=$?
        isError=$( echo "${res}" | egrep -c 'Fail ' )
        WriteLog "retCode: ${retCode}, isError: ${isError}" "$logFile"
        if [[ ${retCode} -ne 0  || ${isError} -ne 0 ]]
        then
            getLogs=1
        fi
        _res=$(echo "$res" | egrep 'Suite:|Queries:|Passing:|Failure:|Elapsed|Fail ' )
        WriteLog "$_res" "$logFile"
    else
        WriteLog "Setup is failed, skip regression tessting." "$logFile"
    fi

    if [[ -n "$QUERY_STAT2_DIR" ]]
    then
        pushd $QUERY_STAT2_DIR > /dev/null
        res=$(./QueryStat2.py -a -t $ip --port $port --obtSystem=Azure --buildBranch=$base -p Azure/ --addHeader --compileTimeDetails 1 --timestamp)
        WriteLog "${res}" "$logFile"
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
    WriteLog "Collect logs" "$logFile"
    dirName="$HOME/shared/Azure/test-$(date +%Y-%m-%d_%H-%M-%S)"; [[ ! -d $dirName ]] && mkdir -p $dirName; kubectl get pods | egrep -v 'NAME' | awk '{ print $1 }' | while read p; do [[ "$p" =~ "mydali" ]] && param="mydali" || param=""; echo "pod:$p - $param"; kubectl describe pod $p > $dirName/$p.desc;  kubectl logs $p $param > $dirName/$p.log; done; kubectl get pods > $dirName/pods.log;  kubectl get services > $dirName/services.log;  kubectl describe nodes > $dirName/nodes.desc; minikube logs >  $dirName/all.log 2>&1
else
    WriteLog "Skip log collection" "$logFile"
fi    

if [[ $INTERACTIVE -eq 1 ]]
then
    WriteLog "Testing finished, press <Enter> to stop pods.\n(After 60 seconds it will continue)" "$logFile"
    read -t 60
fi

WriteLog "To destroy AKS is started ..." "$logFile"
res=$(terraform destroy -var-file=obt-admin.tfvars -auto-approve 2>&1)
if [[ $VERBOSE -ne 0 ]]
then 
    WriteLog "res:$res" "$logFile"
else
    WriteLog "$( echo "$res" | egrep ' Resources:')" "$logFile"
fi

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

WriteLog "End." "$logFile"
WriteLog "==================================" "$logFile"
