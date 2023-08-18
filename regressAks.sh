#!/usr/bin/bash

if [ -f ./timestampLogger.sh ]
then
    . ./timestampLogger.sh
else
    WriteLog()
    {
        msg=$1
        out=$2
        [ -z "$out" ] && out=/dev/null

        echo "$msg"
        echo "$msg" >> $out 2>&1
    }
fi

usage()
{
    WriteLog "usage:" "/dev/null"
    WriteLog "  $0 [-i] [-q] [-h]" "/dev/null"
    WriteLog "where:" "/dev/null"
    WriteLog " -i   - Interactive, stop before unistall with terraform." "/dev/null"
    WriteLog " -q   - Quick test, doesn't execute whole Regression Suite, only a subset of it." "/dev/null"
    WriteLog " -h   - This help." "/dev/null"
    WriteLog " " "/dev/null"

}

#set -x;

getLogs=0
if [ -f ./settings.sh ]
then
    # We are in OBT environment
    . ./settings.sh
    SOURCE_DIR=$SOURCE_HOME
    SUITEDIR=$TEST_ENGINE_HOME
    RTE_DIR=$REGRESSION_TEST_ENGINE_HOME
    QUERY_STAT2_DIR="$OBT_BIN_DIR"
    PERFSTAT_DIR="$HOME/Perfstat-Azure/"
    PKG_DIR=$OBT_BIN_DIR/PkgCache
    EXCLUSIONS='--ef pipefail.ecl,soapcall*,httpcall* -e plugin,3rdparty,embedded,python2,spray'
else
    # Non OBT environment, like local VM/BM
    SOURCE_DIR="$HOME/HPCC-Platform"
    SUITEDIR="$SOURCE_DIR/testing/regress/"
    RTE_DIR="$HOME/RTE-NEWER"
    PKG_DIR="$HOME/HPCC-Platform-build/"
    
    QUERY_STAT2_DIR="$RTE_DIR"
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

CONFIG="./ecl-test-azure.json"
PQ="--pq 2"
TIMEOUT="--timeout 1200"
QUICK_TEST_SET='teststdlib*'
#QUICK_TEST_SET='alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall*'
#QUICK_TEST_SET='alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall* teststdlib*'

logFile=regressAks-$(date +%Y-%m-%d_%H-%M-%S).log 

WriteLog "Start          : $0 $@" "$logFile"
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
INTERACTIVE=1
FULL_REGRESSION=0

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

pushd $SOURCE_DIR > /dev/null

res=$(git checkout -f master 2>&1)
WriteLog "$res" "$logFile"
res=$(git pull upstream master 2>&1)
WriteLog "$res" "$logFile"
res=$(git fetch --tags --all 2>&1)
WriteLog "$res" "$logFile"

baseTag=$( git tag --sort=-creatordate | egrep 'community' | head -n 1 )
res=$( git checkout $baseTag  2>&1 )
WriteLog "res: $res" "$logFile"
gold=1
[[ "$baseTag" =~ "-rc" ]] && gold=0
popd > /dev/null


WriteLog "baseTag: ${baseTag}" "$logFile"
base=${baseTag##community_}
[[ $gold -eq 1 ]] && base=${base%-*}
baseMajorMinor=${base%.*}
pkg="*community?$baseMajorMinor*$PKG_EXT"
WriteLog "base: ${base}" "$logFile"
WriteLog "gold:$gold" "$logFile"
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
pushd ~/terraform-azurerm-hpcc-aks > /dev/null

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
    # Not aleady logged in, login
    az login
fi

# Check account
account=$( az account list -o table | egrep 'us-hpccplatform-dev' )
WriteLog "account: $account" "$logFile"

[[ $( echo $account | awk '{ print $6 }' ) != "True" ]] && (WriteLog "us-hpccplatform-dev is not the default"  "$logFile"; exit 1) 

WriteLog "Update helm repo..." "$logFile"
res=$(helm repo update 2>&1)
WriteLog "$res" "$logFile"

WriteLog "Deploy HPCC ..." "$logFile"
res=$( terraform apply -var-file=obt-admin.tfvars -auto-approve )
WriteLog "res:$res" "$logFile"
cred=$( echo "$res" | egrep 'get-credentials ' | tr -d "'" | cut -d '=' -f 2 | tr -d '"' )
cred="$cred --overwrite-existing"
WriteLog "credentials: '$cred'" "$logFile"
res=$( eval ${cred} 2>&1 )
WriteLog "$res" "$logFile"

WriteLog "Wait until everything is up..." "$logFile"
tryCount=10
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
    done < <( kubectl get pods | egrep -v 'NAME' | awk '{ print $2 " " $1 }' | tr "/" " "); 
    WriteLog "$( printf 'Expected: %s, running %s (%2d)\n' $expected $running $tryCount)" "$logFile"
    [[ $running -ne 0 && $running -eq $expected ]] && break || sleep ${delay}; 
    tryCount=$(( $tryCount - 1)); 
    [[ $tryCount -eq 0 ]] && break; 
    expected=0; 
    running=0; 
done

WriteLog "$(printf 'Expected: %s, running %s (%2d)\n' $e $r $tryCount )" "$logFile"

WriteLog "Platform is up, run tests." "$logFile"

sleep 10
# test it
#printf "\nExpected: %s, running %s (%2d)\n" "$e" "$r" "$tryCount"

if [[ $e -eq $r ]]
then
    # Pods are up

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
    pwd

    WriteLog "Run regression setup ..." "$logFile"
    res=$( ./ecl-test setup --server $ip:$port --suiteDir $SUITEDIR --config $CONFIG  $PQ --timeout 900 --loglevel info 2>&1 )
    retCode=$?
    isError=$( echo "${res}" | egrep -c 'Fail ' )
    WriteLog "retCode: ${retCode}, isError: ${isError}" "$logFile"
    if [[ ${retCode} -ne 0  || ${isError} -ne 0 ]] 
    then
        getLogs=1
        echo "${res}"
    else
        _res=$(echo "$res" | egrep 'Suite|Queries|Passing|Failure|Elapsed' )
        WriteLog "$_res" "$logFile"
    fi

    WriteLog "Run regression ..." "$logFile"    
    # For testing
    res=$( ./ecl-test query --server $ip:$port $EXCLUSIONS --suiteDir $SUITEDIR --config $CONFIG $PQ $TIMEOUT --loglevel info teststdlib* 2>&1 )
    # For real
    #res=$( ./ecl-test run -t hthor --server $ip:$port $EXCLUSIONS --suiteDir $SUITEDIR --config $CONFIG $PQ $TIMEOUT --loglevel info 2>&1 )
    retCode=$?

    isError=$( echo "${res}" | egrep -c 'Fail ' )
    WriteLog "retCode: ${retCode}, isError: ${isError}" "$logFile"
    if [[ ${retCode} -ne 0  || ${isError} -ne 0 ]] 
    then
        getLogs=1
        echo "${res}"
    else
        _res=$(echo "$res" | egrep 'Suite|Queries|Passing|Failure|Elapsed' )
        WriteLog "$_res" "$logFile"
    fi

    pushd $QUERY_STAT2_DIR > /dev/null
    res=$(./QueryStat2.py -a -t $ip --port $port --obtSystem=Azure --buildBranch=$base -p Azure/ --addHeader --compileTimeDetails 1 --timestamp)
    WriteLog "${res}" "$logFile"
    popd > /dev/null

    popd > /dev/null
else
    WriteLog "Problem with pods start" "$logFile"
fi
# Get all logs:
if [[ ${getLogs} -ne 0 ]]
then
    WriteLog "Collect logs" "$logFile"
    dirName="$HOME/shared/Minikube/test-$(date +%Y-%m-%d_%H-%M-%S)"; [[ ! -d $dirName ]] && mkdir -p $dirName; kubectl get pods | egrep -v 'NAME' | awk '{ print $1 }' | while read p; do [[ "$p" =~ "mydali" ]] && param="mydali" || param=""; echo "pod:$p - $param"; kubectl describe pod $p > $dirName/$p.desc;  kubectl logs $p $param > $dirName/$p.log; done; kubectl get pods > $dirName/pods.log;  kubectl get services > $dirName/services.log;  kubectl describe nodes > $dirName/nodes.desc; minikube logs >  $dirName/all.log 2>&1
else
    WriteLog "Skip log collection" "$logFile"
fi    

if [[ $INTERACTIVE -eq 1 ]]
then
    WriteLog "Testing finished, press <Enter> to stop pods." "$logFile"
    read
fi

res=$(terraform destroy -var-file=obt-admin.tfvars -auto-approve 2>&1)
WriteLog "${res}" "$logFile"

# Wait until everyting is down
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
    done < <( kubectl get pods | egrep -v 'NAME' | awk '{ print $2 " " $1 }' | tr "/" " "); 
    WriteLog "$( printf '\nExpected: %s, running %s (%s)\n' $expected $running $tryCount)"  "$logFile";

    [[ $expected -eq 0 ]] && break || sleep 10; 
done; 
WriteLog "System is down" "$logFile"


WriteLog "End." "$logFile"
WriteLog "==================================" "$logFile"
