
#set -x;

getLogs=0
SOURCE_DIR="$HOME/HPCC-Platform"
PKG_DIR="$HOME/HPCC-Platform-build/"
SUITEDIR="$SOURCE_DIR/testing/regress/"
RTE_DIR="$HOME/RTE-NEWER"

#sudo sysctl fs.protected_regular=0
#sudo chown -R $USER $HOME/.kube
#chmod -R u+wrx $HOME/.kube
#
#sudo chown -R $USER $HOME/.minikube
#chmod -R u+wrx $HOME/.minikube

logfile=regressAks-$(date +%Y-%m-%d_%H-%M-%S).log 
#exec >> ${logfile} 2>&1

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
pkg="*community_$baseMajorMinor*.deb"
echo "base: ${base}"
echo "gold:$gold"
echo "base major.minor:$baseMajorMinor"

echo "pkg:$pkg"
CURRENT_PKG=$( dpkg -l | grep 'hpccsystems-pl' | awk '{ print $3 }' )
[ -z "$CURRENT_PKG" ] && CURRENT_PKG="Not installed"
echo "current installed pkg: $CURRENT_PKG"

CURRENT_PKG_MajorMinor=${CURRENT_PKG%.*}
echo "current installed pkg major.minor: $CURRENT_PKG_MajorMinor"
if [[ "$CURRENT_PKG_MajorMinor" == "$baseMajorMinor" ]]
then
    echo "The installed platform package is ok to testing cloud."
else
    echo "Need to install $pkg to testing cloud."
    candidates=$( find $PKG_DIR -iname $pkg -type f )
    if [ -n "$candidates" ]
    then
        echo "Possible candidate(s):"
        echo "$candidates"
    fi
    exit 1
fi


echo "Update obt-admin.tfvars..." 
pushd ~/terraform-azurerm-hpcc-aks

cp -v obt-admin.tfvars obt-admin.tfvars-back
	
sed -i -e 's/^\(\s*\)version\s*=\s*\(.*\)/\1version = "'"${base}"'"/g' obt-admin.tfvars
egrep '^\s*version ' obt-admin.tfvars

echo "  Done."

# Check login status
loginCheck=$(az ad signed-in-user show)
retCode=$?
echo "$loginCheck" > $logfile 2>&1
echo "$loginCheck"

if [[ $retCode != 0 ]] 
then
    # Not aleady logged in, login
    az login
fi

# Check account
account=$( az account list -o table | egrep 'us-hpccplatform-dev' )
echo "account: $account"

[[ $( echo $account | awk '{ print $6 }' ) != "True" ]] && (echo "us-hpccplatform-dev is not the default"; exit 1) 

helm repo update

res=$( terraform apply -var-file=obt-admin.tfvars -auto-approve )
echo "res:$res"
cred=$( echo "$res" | egrep 'get-credentials ' | tr -d "'" | cut -d '=' -f 2 | tr -d '"' )
cred="$cred --overwrite-existing"
echo "credentials: '$cred'"
eval ${cred}

echo "Wait until everything is up..."
tryCount=10
delay=10
e=0
r=0
while true; do  while read a b c; do r=$(( $r + $a )); e=$(( $e + $b )); printf "%-45s: %s/%s  %s\n" "$c" "$a" "$b"  $( [[ $a -ne $b ]] && echo "starting" || echo "up" ) ; done < <( kubectl get pods | egrep -v 'NAME' | awk '{ print $2 " " $1 }' | tr "/" " "); printf "\nExpected: %s, running %s (%2d)\n" "$e" "$r" "$tryCount"; [[ $r -ne 0 && $r -eq $e ]] && break || sleep ${delay}; tryCount=$(( $tryCount - 1)); [[ $tryCount -eq 0 ]] && break; e=0; r=0; done

printf "\nExpected: %s, running %s (%2d)\n" "$e" "$r" "$tryCount"

echo "Platform is up, run tests."

sleep 10
# test it
printf "\nExpected: %s, running %s (%2d)\n" "$e" "$r" "$tryCount"

if [[ $e -eq $r ]]
then
    # Pods are up

    pushd ~/RTE-NEWER
    echo "cwd: $(pwd)"

    echo "Start ECLWatch."
    kubectl annotate service eclwatch --overwrite service.beta.kubernetes.io/azure-load-balancer-internal="false"
    sleep 60
    
    ip=$( kubectl get svc | egrep 'eclwatch' | awk '{ print $4 }' )
    echo "ip: $ip"
    port=8010
    echo "port: $port"
    #echo "Press <Enter> to continue"
    #read

    [[ -z "$ip" ]] && exit 1

    # Give it some more time
    sleep 30

    echo "Run tests."
    pwd
    EXCLUSIONS='--ef pipefail.ecl,soapcall*,httpcall* -e plugin,3rdparty,embedded,python2,spray'
    CONFIG="./ecl-test-azure.json"
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
    
    # For testing
    res=$( ./ecl-test query --server $ip:$port $EXCLUSIONS --suiteDir $SUITEDIR --config $CONFIG $PQ $TIMEOUT --loglevel info teststdlib* 2>&1 )
    # For real
    #res=$( ./ecl-test run -t hthor --server $ip:$port $EXCLUSIONS --suiteDir $SUITEDIR --config $CONFIG $PQ $TIMEOUT --loglevel info 2>&1 )
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

    ./QueryStat2.py -a -v  -t $ip --port $port --obtSystem=Azure --buildBranch=$base -p Azure/ --addHeader --compileTimeDetails 1 --timestamp

    popd
else
    echo "Problem with pods start"
fi
# Get all logs:
if [[ ${getLogs} -ne 0 ]]
then
    echo "Collect logs"
    dirName="$HOME/shared/Minikube/test-$(date +%Y-%m-%d_%H-%M-%S)"; [[ ! -d $dirName ]] && mkdir -p $dirName; kubectl get pods | egrep -v 'NAME' | awk '{ print $1 }' | while read p; do [[ "$p" =~ "mydali" ]] && param="mydali" || param=""; echo "pod:$p - $param"; kubectl describe pod $p > $dirName/$p.desc;  kubectl logs $p $param > $dirName/$p.log; done; kubectl get pods > $dirName/pods.log;  kubectl get services > $dirName/services.log;  kubectl describe nodes > $dirName/nodes.desc; minikube logs >  $dirName/all.log 2>&1
else
    echo "Skip log collection"
fi    

echo "Testing finished, press <Enter> to stop pods."
read

terraform destroy -var-file=obt-admin.tfvars -auto-approve

# Wait until everyting is down
while true; do date;  e=0; r=0; while read a b c; do r=$(( $r + $a )); e=$(( $e + $b )); printf "%-45s: %s/%s  %s\n" "$c" "$a" "$b"  $( [[ $a -ne $b ]] && echo "starting" || echo "up" ) ; done < <( kubectl get pods | egrep -v 'NAME' | awk '{ print $2 " " $1 }' | tr "/" " "); printf "\nExpected: %s, running %s\n" "$e" "$r"; [[ $e -eq 0 ]] && break || sleep 10; done; echo "System is down"


echo "End."
echo "=================================="
