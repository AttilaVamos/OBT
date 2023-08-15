#!/usr/bin/bash


myEcho()
{
    msg=$1
    out=$2
    [ -z "$out" ] && out=/dev/null

    echo "$msg"
    echo "$msg" >> $out 2>&1
}

usage()
{
    echo "usage:"
    echo "  $0 [-i] [-q] [-h]"
    echo "where:"
    echo " -i   - Interactive, stop before unistall helm chart and stop minikube."
    echo " -q   - Quick test, doesn't execute whole Regression Suite, only a subset"
    echo "        of it."
    echo " -h   - This help."
    echo " "

}

#set -x;

getLogs=0
if [ -f ./settings.sh ]
then
    . ./settings.sh
    SOURCE_DIR=$SOURCE_HOME
    SUITEDIR=$TEST_ENGINE_HOME
    RTE_DIR=$REGRESSION_TEST_ENGINE_HOME
    QUERY_STAT2_DIR="$OBT_BIN_DIR"
    PKG_DIR=$OBT_BIN_DIR/PkgCache
else
    SOURCE_DIR="$HOME/HPCC-Platform"
    SUITEDIR="$SOURCE_DIR/testing/regress/"
    RTE_DIR="$HOME/RTE-NEWER"
    #RTE_DIR="$SOURCE_DIR/testing/regress"
    #RTE_DIR="$HOME/RTE-NEW"
    QUERY_STAT2_DIR="$RTE_DIR"

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

logFile=regressMinikube-$(date +%Y-%m-%d_%H-%M-%S).log 
#gnome-terminal --title "regressMinikube log" -- bash -c "tail -f -n 200 $logFile" &
#exec >> ${logFile} 2>&1

#set -x
INTERACTIVE=0
FULL_REGRESSION=1

while [ $# -gt 0 ]
do
    param=$1
    param=${param//-/}
    upperParam=${param^^}
    echo "Param: ${upperParam}"
    case $upperParam in
        I)  INTERACTIVE=1
            ;;
               
        Q)  FULL_REGRESSION=0
            ;;

        H* | *)  
            usage
            exit 1
            ;;
    esac
    shift
done

echo "INTERACTIVE    : $INTERACTIVE"
echo "FULL_REGRESSION: $FULL_REGRESSION"

pushd $SOURCE_DIR

git checkout -f master
git pull upstream master
git fetch --tags --all

baseTag=$( git tag --sort=-creatordate | egrep 'community' | head -n 1 )
res=$( git checkout $baseTag  2>&1 )
echo "res: $res"
gold=1
[[ "$baseTag" =~ "-rc" ]] && gold=0
popd > /dev/null

echo "baseTag: ${baseTag}"
base=${baseTag##community_}
[[ $gold -eq 1 ]] && base=${base%-*}
baseMajorMinor=${base%.*}
pkg="*community?$baseMajorMinor*$PKG_EXT"
#if [ "$PKG_EXT" == ".deb" ]
#then
#    pkg="*community_$baseMajorMinor*$PKG_EXT"
#else
#    pkg="*community-$baseMajorMinor*$PKG_EXT"
#fi
echo "base: ${base}"
echo "gold:$gold"
echo "base major.minor:$baseMajorMinor"
echo "pkg:$pkg"
if [ "$PKG_EXT" == ".deb" ]
then
    CURRENT_PKG=$( ${PKG_QRY_CMD} | grep 'hpccsystems-pl' | awk '{ print $3 }' )
else
    CURRENT_PKG=$( ${PKG_QRY_CMD} | grep 'hpccsystems-pl' | awk -F - '{ print $3 }' )
fi
[ -z "$CURRENT_PKG" ] && CURRENT_PKG="Not installed"
echo "current installed pkg: $CURRENT_PKG"

CURRENT_PKG_MajorMinor=${CURRENT_PKG%.*}
echo "current installed pkg major.minor: $CURRENT_PKG_MajorMinor"
if [[ "$CURRENT_PKG_MajorMinor" == "$baseMajorMinor" ]]
then
    echo "The installed platform package is ok to testing cloud."
else
    echo "Need to install $pkg to testing cloud."
    if [[ $INTERACTIVE -eq 1 ]]
    then
        candidates=$( find $PKG_DIR -maxdepth 1 -iname $pkg -type f )
        if [ -n "$candidates" ]
        then
            echo "Possible candidate(s):"
            echo "$candidates"
        fi
        exit 1
    else
        candidate=$( find $PKG_DIR -maxdepth 2 -iname $pkg -type f | sort -rV | head -n 1 )
        if [ -n "$candidate" ]
        then
            echo "Install $candidate"
            sudo ${PKG_INST_CMD} $candidate
            retCode=$?
            if [[ $retCode -ne 0 ]]
            then
                echo "Install $candiadate failed with $retCode."
                exit 1
            fi
            echo "Done."
        else
            echo "Platform install package:$pkd not found, exit."
            exit 1
        fi
    fi
fi

isMinikubeUp=$( minikube status | egrep -c 'Running|Configured'  )
if [[ $isMinikubeUp -ne 4 ]]
then
    echo "Minikube is down, start it up."
    minikube start
    
else
    echo "Minikube is up."
fi

helm repo update

helm install minikube hpcc/hpcc --version=$base  -f ./obt-values.yaml

# Wait until everything is up
tryCount=60
delay=10
e=0
r=0
while true; do  while read a b c; do r=$(( $r + $a )); e=$(( $e + $b )); printf "%-45s: %s/%s  %s\n" "$c" "$a" "$b"  $( [[ $a -ne $b ]] && echo "starting" || echo "up" ) ; done < <( kubectl get pods | egrep -v 'NAME' | awk '{ print $2 " " $1 }' | tr "/" " "); printf "\nExpected: %s, running %s (%2d)\n" "$e" "$r" "$tryCount"; [[ $r -ne 0 && $r -eq $e ]] && break || sleep ${delay}; tryCount=$(( $tryCount - 1)); [[ $tryCount -eq 0 ]] && break; e=0; r=0; done

sleep 10
# test it
printf "\nExpected: %s, running %s (%2d)\n" "$e" "$r" "$tryCount"

if [[ $e -eq $r ]]
then
    # Pods are up

    pushd $RTE_DIR
    echo "cwd: $(pwd)"

    echo "Start ECLWatch."
    minikube service eclwatch
    sleep 30
    
    uri=$( minikube service list | egrep 'eclwatch' | awk '{ print $8 }' | cut -d '/' -f3 )
    echo "uri: $uri"
    ip=$( echo $uri | cut -d ':' -f 1 )
    echo "ip: $ip"
    port=$( echo $uri | cut -d ':' -f 2 )
    echo "port: $port"
    #echo "Press <Enter> to continue"
    #read

    echo "Run tests."
    pwd
    #EXCLUSIONS='--ef pipefail.ecl,soapcall*,httpcall* -e plugin,3rdparty,embedded,python2,spray'
    EXCLUSIONS='--ef pipefail.ecl -e plugin,3rdparty,embedded,python2,spray'
    
    CONFIG="./ecl-test-minikube.json"
    PQ="--pq 2"
    TIMEOUT="--timeout 1200"

    res=$( ./ecl-test setup --server $ip:$port --suiteDir $SUITEDIR --config $CONFIG  $PQ --timeout 900 --loglevel info 2>&1 )
    retCode=$?
    isError=$( echo "${res}" | egrep -c 'Fail ' )
    echo "retCode: ${retCode}, isError: ${isError}"
    if [[ ${retCode} -ne 0  || ${isError} -ne 0 ]] 
    then
        getLogs=1
        echo "${res}"
    else
        echo "${res}" | egrep 'Suite|Queries|Passing|Failure|Elapsed'
    fi
    
    if [[ $FULL_REGRESSION -eq 1 ]]
    then 
        # For full regression on hthor
        res=$( ./ecl-test run --server $ip:$port $EXCLUSIONS --suiteDir $SUITEDIR --config $CONFIG $PQ $TIMEOUT --loglevel info 2>&1 )
    else
        # For sanity testing on all engines
        #res=$( ./ecl-test query --server $ip:$port $EXCLUSIONS --suiteDir $SUITEDIR --config $CONFIG $PQ $TIMEOUT --loglevel info teststdlib* 2>&1 )
        res=$( ./ecl-test query --server $ip:$port $EXCLUSIONS --suiteDir $SUITEDIR --config $CONFIG $PQ $TIMEOUT --loglevel info alien2.ecl badindex.ecl csvvirtual.ecl fileposition.ecl keydiff.ecl keydiff1.ecl httpcall_* soapcall* teststdlib* 2>&1 )
    fi    
    
    retCode=$?
    isError=$( echo "${res}" | egrep -c 'Fail ' )
    echo "retCode: ${retCode}, isError: ${isError}"
    if [[ ${retCode} -ne 0  || ${isError} -ne 0 ]] 
    then
        getLogs=1
        echo "${res}"
    else
        echo "${res}" | egrep 'Suite|Queries|Passing|Failure|Elapsed'
    fi

    pushd $QUERY_STAT2_DIR
    ./QueryStat2.py  -a -v  -t $ip --port $port --obtSystem=Minikube --buildBranch=$base -p Minikube/ --addHeader --compileTimeDetails 1 --timestamp
    popd

    popd
else
    echo "Problem with pods start"
fi
# Get all logs if needed
if [[ ${getLogs} -ne 0 ]]
then
    echo "Collect logs"
    dirName="$HOME/shared/Minikube/test-$(date +%Y-%m-%d_%H-%M-%S)"; [[ ! -d $dirName ]] && mkdir -p $dirName; kubectl get pods | egrep -v 'NAME' | awk '{ print $1 }' | while read p; do [[ "$p" =~ "mydali" ]] && param="mydali" || param=""; echo "pod:$p - $param"; kubectl describe pod $p > $dirName/$p.desc;  kubectl logs $p $param > $dirName/$p.log; done; kubectl get pods > $dirName/pods.log;  kubectl get services > $dirName/services.log;  kubectl describe nodes > $dirName/nodes.desc; minikube logs >  $dirName/all.log 2>&1
else
    echo "Skip log collection"
fi

if [[ $INTERACTIVE -eq 1 ]]
then
    echo "Testing finished, press <Enter> to stop pods."
    read
fi

helm uninstall minikube 

# Wait until everyting is down
tryCount=60
delay=10
while true
do
    date;
    expected=0;
    running=0;
    while read a b c;
    do
        running=$(( $running + $a ));
        expected=$(( $expected + $b ));
        printf "%-45s: %s/%s  %s\n" "$c" "$a" "$b"  $( [[ $a -ne $b ]] && echo "starting" || echo "up" ) ;
    done < <( kubectl get pods | egrep -v 'NAME' | awk '{ print $2 " " $1 }' | tr "/" " ");
    printf "\nExpected: %s, running %s (%s)\n" "$expected" "$running" "$tryCount";

    [[ $expected -eq 0 ]] && break || sleep $delay;

    tryCount=$(( $tryCount - 1 ))

    if [[ $tryCount -eq 0 ]]
    then
        echo "Try count exhauset, but there are $running still runing pods, collect logs about then delete them."
        # Collect logs from still running pods
        dirName="$HOME/shared/Minikube/test-$(date +%Y-%m-%d_%H-%M-%S)"; [[ ! -d $dirName ]] && mkdir -p $dirName; kubectl get pods | egrep -v 'NAME' | awk '{ print $1 }' | while read p; do [[ "$p" =~ "mydali" ]] && param="mydali" || param=""; echo "pod:$p - $param"; kubectl describe pod $p > $dirName/$p.desc;  kubectl logs $p $param > $dirName/$p.log; done; kubectl get pods > $dirName/pods.log;  kubectl get services > $dirName/services.log;  kubectl describe nodes > $dirName/nodes.desc; minikube logs >  $dirName/all.log 2>&1

        # delete them with 1 Minute grace period
        for f in `kubectl get pods | grep -v ^NAME | awk '{print $1}'` ;
        do
            kubectl delete pod $f --grace-period=60  # or with --force
        done

        # give it 10 more attempts
        tryCount=10
    fi
done;
echo "System is down"

minikube stop

echo "End."
echo "=================================="
