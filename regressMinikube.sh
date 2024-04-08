#!/usr/bin/bash
#set -x;

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
    WriteLog " -h       - This help." "/dev/null"
    WriteLog " " "/dev/null"
}

#set -x;
logFile=$(pwd)/regressMinikube-$(date +%Y-%m-%d_%H-%M-%S).log

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
fi

CONFIG="./ecl-test-k8s.json"
PQ="--pq 2"
TIMEOUT="--timeout 1200"
QUICK_TEST_SET='teststdlib*'
QUICK_TEST_SET='pipe* httpcall* soapcall* roxie* badindex.ecl'
#QUICK_TEST_SET='alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall*'
#QUICK_TEST_SET='alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall* teststdlib*'
EXCLUSIONS='--ef pipefail.ecl -e plugin,3rdparty,embedded,python2,spray'

WriteLog "Start          : $0 $*" "$logFile"
WriteLog "SOURCE_DIR     : $SOURCE_DIR" "$logFile"
WriteLog "SUITEDIR       : $SUITEDIR" "$logFile"
WriteLog "RTE_DIR        : $RTE_DIR" "$logFile"
WriteLog "OBT BIN DIR    : $OBT_BIN_DIR" "$logFile"
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
    done< <(git tag --sort=-creatordate | egrep 'community_'$latestMajorMinor |  head -n 10 )
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

WriteLog "Update helm repo..." "$logFile"
res=$(helm repo update 2>&1)
WriteLog "$res" "$logFile"

WriteLog "Deploy HPCC ..." "$logFile"
res=$( helm install minikube hpcc/hpcc --version=$base  -f ./obt-values.yaml  2>&1)
WriteLog "$res" "$logFile"

# Wait until everything is up
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
        #WriteLog "$(printf '%-45s: %s/%s  %s\n' $c $a $b  $( [[ $a -ne $b ]] && echo starting || echo up) )" "$logFile"; 
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

if [[ ($expected -eq $running) && ($running -ne 0 ) ]]
then
    # Pods are up

    pushd $RTE_DIR > /dev/null
    WriteLog "cwd: $(pwd)" "$logFile"

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
        WriteLog "Run regression ..." "$logFile"
        if [[ $FULL_REGRESSION -eq 1 ]]
        then
            # For full regression on hthor
            res=$( ./ecl-test run --server $ip:$port $EXCLUSIONS --suiteDir $SUITEDIR --config $CONFIG $PQ $TIMEOUT --loglevel info 2>&1 )
        else
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
        res=$( ./QueryStat2.py -a -t $ip --port $port --obtSystem=Minikube --buildBranch=$base -p $PERFSTAT_DIR --addHeader --compileTimeDetails 1 --timestamp )
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

# Get all logs if needed
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

if [[ $INTERACTIVE -eq 1 ]]
then
    WriteLog "Testing finished, press <Enter> to stop pods.\n(After 60 seconds it will continue)" "$logFile"
    read -t 60
fi

WriteLog "Uninstall PODs ..." "$logFile"
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
    while read a b c;
    do
        running=$(( $running + $a ));
        expected=$(( $expected + $b ));
        #WriteLog " $( printf '%-45s: %s/%s  %s\n' $c $a $b  $( [[ $a -ne $b ]] && echo starting || echo up ))" "$logFile" ;
    done < <( kubectl get pods | egrep -v 'NAME|No resources ' | awk '{ print $2 " " $1 }' | tr "/" " ");
    WriteLog "$( printf '\nExpected: %s, running %s (%s)\n' $expected $running $tryCount)"  "$logFile";

    [[ $expected -eq 0 ]] && break || sleep $delay;

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
WriteLog "System is down" "$logFile"

res=$(minikube stop 2>&1)
WriteLog "${res}" "$logFile"

if [[ -n "$QUERY_STAT2_DIR" ]]
then
    pushd $QUERY_STAT2_DIR > /dev/null
    if [ -f regressK8sLogProcessor.py ]
    then
        res=$( ./regressK8sLogProcessor.py --path ./  2>&1 )
        WriteLog "${res}" "$logFile"
    else
        WriteLog "regressK8sLogProcessor.py not found." "$logFile"
    fi
    popd > /dev/null
else
    WriteLog "Missing OBT binary directory, skip Minikube test log processing." "$logFile"
fi

WriteLog "End." "$logFile"
WriteLog "==================================" "$logFile"
