#!/bin/bash
#export PS4='+ $LINENO: ' ## single quotes prevent $LINENO being expanded immediately
#set -ux

declare -f -F WriteLog> /dev/null

if [ $? -ne 0 ]
then
    [ -f ./timestampLogger.sh ] && . ./timestampLogger.sh || . ~/build/bin/timestampLogger.sh
    # . ~/build/bin/timestampLogger.sh
fi

# Git branch settings

.  ~/build/bin/settings.sh

KillWatchDogAndWaitToDie()
{
    DELAY=10
    sudo kill $1

    while (true)
    do 
        sleep ${DELAY}
        stillRunning=$( ps aux | grep -c -i '[w]atchdog.py' )

        if [[ ${stillRunning} -eq 0 ]]
        then 
            WriteLog "WatchDog ($1) finished." "$2"
            break
        fi
        WriteLog "WatchDog ($1) is still running. Wait ${DELAY} sec and try again." "$2"
        [ -n "$(pgrep WatchDog)" ] && sudo pkill -9 WatchDog.py
    done

    rm ./WatchDog.pid
}


CloneRepo()
{
    LONG_DATE=$(date "+%Y-%m-%d_%H-%M-%S")
    CLONE_LOG_FILE=$OBT_BIN_DIR/CloneRepo-${LONG_DATE}.log
    WATCHDOG_LOG_FILE=${OBT_LOG_DIR}/WatchDog-$(date "+%Y-%m-%d_%H-%M-%S").log


    if [ -f "$OBT_BIN_DIR/WatchDog.py" ]
    then
        watchDogStartCmd="$OBT_BIN_DIR/WatchDog.py -p 'git-*' -t 900 -r 3600 -v"
        WriteLog "Start WatchDog: ${watchDogStartCmd}" "${CLONE_LOG_FILE}"
        WriteLog "Watchdog logfile: ${WATCHDOG_LOG_FILE}" "${CLONE_LOG_FILE}"

        ${watchDogStartCmd} >> ${WATCHDOG_LOG_FILE} 2>&1 &
        echo $! > ./WatchDog.pid
        WriteLog "WatchDog pid: $( cat ./WatchDog.pid )." "$CLONE_LOG_FILE"

    fi
    
    NO_ERROR=0
    RECOVERABLE_ERROR=1
    UNRECOVERABLE_ERROR=2
    DESTINATION_EXISTS_ERROR=3
    HTTP_REQUEST_ERROR=4

    tryCount=20
    tryDelay=2m
    repo=$1
    target=$2

    WriteLog "Clone $1  (into '$target')" "${CLONE_LOG_FILE}"
    WriteLog "[$( caller )] $*" "${CLONE_LOG_FILE}"

    while true
    do
        WriteLog "Try count: ${tryCount}" "${CLONE_LOG_FILE}"
        res=0

        res=$( while read line;                                                                         \
               do                                                                                       \
                   WriteLog "${line}" "${CLONE_LOG_FILE}" > /dev/null;                                  \
                   res=$( echo "${line}" | egrep -i '^fatal' | egrep -c -i 'not an empty directory' );  \
                   if [ $res -ne 0 ];                                                                   \
                   then                                                                                 \
                        echo "$DESTINATION_EXISTS_ERROR";                                               \
                        break;                                                                          \
                   fi;                                                                                  \
                   res=$( echo "${line}" | egrep -i '^fatal' | egrep -c -i 'HTTP request failed' );     \
                   if [ $res -ne 0 ];                                                                   \
                   then                                                                                 \
                        echo "$HTTP_REQUEST_ERROR";                                                     \
                        break;                                                                          \
                   fi;                                                                                  \
                   res=$( echo "${line}" | egrep -i '^fatal' | egrep -c -i 'unable to access' );        \
                   if [ $res -ne 0 ];                                                                   \
                   then                                                                                 \
                        echo "$HTTP_REQUEST_ERROR";                                                     \
                        break;                                                                          \
                   fi;                                                                                  \
                   res=$( echo "${line}" | egrep -c -i '^fatal' );                                      \
                   if [ $res -ne 0 ];                                                                   \
                   then                                                                                 \
                        echo "$UNRECOVERABLE_ERROR";                                                    \
                        break;                                                                          \
                   fi;                                                                                  \
                   res=$( echo "${line}" | egrep -c -i '^error' );                                      \
                   if [ $res -ne 0 ];                                                                   \
                   then                                                                                 \
                        echo "$RECOVERABLE_ERROR";                                                      \
                        break;                                                                          \
                   fi;                                                                                  \
                done < <( git clone $repo $target 2>&1 );                                                                                   \
             );

        if [ "${res}." == "." ] 
        then 
            WriteLog "Cloned ! " "${CLONE_LOG_FILE}"
            break
        else
            WriteLog "Error:${res}" "${CLONE_LOG_FILE}"

            case $res in
                "$RECOVERABLE_ERROR" ) WriteLog "res:'RECOVERABLE_ERROR'" "${CLONE_LOG_FILE}"
                                      # Check/set MTU with 'ip link set eth0 mtu 1400'
                                      ipResetCMD="ip link set eth0 mtu 1400"    
                                      WriteLog "Reset link: ${ipResetCMD}" "${CLONE_LOG_FILE}"
                                      ${ipResetCMD} >> ${CLONE_LOG_FILE} 2>&1 &
                                      ;;

                "$UNRECOVERABLE_ERROR" ) WriteLog "res:'UNRECOVERABLE_ERROR'" "${CLONE_LOG_FILE}"
                                      # return 1
                                      rmt=$( git ls-remote  ${repo} | wc -l )
                                      WriteLog "ls-remote returns with ${rmt} results." "${CLONE_LOG_FILE}"
                                      gitproc=$( pgrep -f 'git-' )
                                      WriteLog "git process(es): ${gitproc} ." "${CLONE_LOG_FILE}"
                                      [ -n "$gitproc" ]  && sudo pkill -KILL ${gitproc}
                                      ;;

                "$DESTINATION_EXISTS_ERROR" ) WriteLog "res:'DESTINATION_EXISTS_ERROR'. Remove target directory." "${CLONE_LOG_FILE}"
                                      rm -rf $target
                                      #mkdir build
                                      ;;
                "$HTTP_REQUEST_ERROR" ) WriteLog "res:'HTTP_REQUEST_ERROR'" "${CLONE_LOG_FILE}"
                                        WriteLog "Try it with SSH: 'git@github.com:hpcc-systems/HPCC-Platform.git'" "${CLONE_LOG_FILE}"
                                        repo='git@github.com:hpcc-systems/HPCC-Platform.git'
                                      ;;

            esac

            tryCount=$(( $tryCount-1 ))
            if [[ $tryCount -ne 0 ]]
            then
                WriteLog "Wait for ${tryDelay} to try again." "${CLONE_LOG_FILE}"
                sleep ${tryDelay}
                continue
            else
                break;
            fi
        fi
    done

    wdPid=$( cat ./WatchDog.pid )
    WriteLog "Kill WatchDog (${wdPid})." "${CLONE_LOG_FILE}"

    KillWatchDogAndWaitToDie "${wdPid}" "${CLONE_LOG_FILE}"



    if [[ $tryCount -eq 0 ]]
    then
        WriteLog "Give up ! " "${CLONE_LOG_FILE}"
        # send email to Agyi
        return 1
    fi
    
}
    
CloneRTE()
{
    # Get the latest Regression Test Engine 
    WriteLog "Get the latest Regression Test Engine..." "${CLONE_LOG_FILE}"
    [[ -d $REGRESSION_TEST_ENGINE_HOME ]] && rm -rf $REGRESSION_TEST_ENGINE_HOME
    # We are cloning, so don't create dir for it
    #[[ ! -d $REGRESSION_TEST_ENGINE_HOME ]]  && mkdir -p $REGRESSION_TEST_ENGINE_HOME
    
    #pushd $target
    
    # Check Regression Test Engine version by last commit id of master branch
    #branch=$( git status | egrep 'On branch' | cut -d' ' -f 3 )
    #[[ "$branch" != "master" ]] && echo "res: $(git checkout master)"
    
    #newCommitId=$( git log -1 | grep '^commit'  | cut -d ' ' -f 2)
    #[[ -f $REGRESSION_TEST_ENGINE_HOME/commit.id ]] && oldCommitId=$( cat $REGRESSION_TEST_ENGINE_HOME/commit.id ) || oldCommitId="none"
    # Force to always get RTE from master (until it will be fixed)
    oldCommitId="none"
    
    if [[ "$oldCommitId" != "$newCommitId" ]]
    then
        WriteLog "There is a newest version ($newCommitId) in GitHub (we have $oldCommitId) get it." "${CLONE_LOG_FILE}"
        # Copy latest Regression Test Engine into <OBT binary dir>/rte directory
        #res=$( cp -v testing/regress/ecl-test* $REGRESSION_TEST_ENGINE_HOME/. 2>&1)
        #WriteLog "res: ${res}" "${CLONE_LOG_FILE}"
        
        #res=$(cp -v -r testing/regress/hpcc $REGRESSION_TEST_ENGINE_HOME/hpcc 2>&1 )

        # clone RTE from GitHub
        res=$( CloneRepo "https://github.com/AttilaVamos/RTE.git" "$REGRESSION_TEST_ENGINE_HOME" )
        WriteLog "res: ${res}" "${CLONE_LOG_FILE}"
        
        echo "$newCommitId" > $REGRESSION_TEST_ENGINE_HOME/commit.id
    else
        WriteLog "We have the latest version." "${CLONE_LOG_FILE}"
    fi
    
    #popd
    
    WriteLog "End." "${CLONE_LOG_FILE}"
    return 0
}

SubmoduleUpdate()
{
    LONG_DATE=$(date "+%Y-%m-%d_%H-%M-%S")
    SUBMODULE_LOG_FILE=$OBT_BIN_DIR/SubmoduleUpdate-${LONG_DATE}.log
    WATCHDOG_LOG_FILE=${OBT_LOG_DIR}/WatchDog-$(date "+%Y-%m-%d_%H-%M-%S").log

    if [ -f "$OBT_BIN_DIR/WatchDog.py" ]
    then
        watchDogStartCmd="$OBT_BIN_DIR/WatchDog.py -p 'git-*' -t 1800 -r 3600 -v"
        WriteLog "Start WatchDog: ${watchDogStartCmd}" "${SUBMODULE_LOG_FILE}"
        WriteLog "Watchdog logfile: ${WATCHDOG_LOG_FILE}" "${SUBMODULE_LOG_FILE}"
        ${watchDogStartCmd} >> ${WATCHDOG_LOG_FILE} 2>&1 &
        echo $! > ./WatchDog.pid
        WriteLog "WatchDog pid: $( cat ./WatchDog.pid )." "${SUBMODULE_LOG_FILE}"
    fi


    tryCount=10
    tryDelay=2m

    export GIT_CURL_VERBOSE=1
    export GIT_CURL_RETRY=10
    export CURLOPT_RETRY=10
    export CURL_RETRY=10

    NO_ERROR=0
    SINGLE_REVISION_NEEDED_ERROR=1
    RECOVERABLE_ERROR=2
    NOT_GIT_REPO_ERROR=3

    WriteLog "git submodule update $1" "${SUBMODULE_LOG_FILE}"
    WriteLog "[$( caller )] $*" "${SUBMODULE_LOG_FILE}"
    while true
    do
        WriteLog "Try count: ${tryCount}" "${SUBMODULE_LOG_FILE}"
        res=$NO_ERROR

        res=$( while read line;                                                                           \
               do                                                                                         \
                   WriteLog "${line}" "${SUBMODULE_LOG_FILE}" > /dev/null;                                \
                                                                                                          \
                   res=$( echo "${line}" | egrep -i '^fatal' | egrep -c -i 'Needed a single revision' );  \
                   if [ $res -ne 0 ];                                                                     \
                   then                                                                                   \
                       echo "$SINGLE_REVISION_NEEDED_ERROR";                                              \
                       break;                                                                             \
                   fi;                                                                                    \
                   res=$( echo "${line}" | egrep -i '^fatal' | egrep -c -i 'Not a git repository' );      \
                   if [ $res -ne 0 ];                                                                     \
                   then                                                                                   \
                       echo "$NOT_GIT_REPO_ERROR";                                                        \
                       break;                                                                             \
                   fi;                                                                                    \
                                                                                                          \
                   res=$( echo "${line}" | egrep -c -i '^fatal|^error|Killed|failed' );                   \
                   if [ $res -ne 0 ];                                                                     \
                   then                                                                                   \
                       echo "$RECOVERABLE_ERROR";                                                         \
                       break;                                                                             \
                   fi;                                                                                    \
                                                                                                          \
               done < <(  git submodule update $1 2>&1 ) ;                                                \
             );

        if [ "${res}." == "." ] 
        then 
            WriteLog "Submodule update finished ! " "${SUBMODULE_LOG_FILE}"
            break
        else
            set -x
            WriteLog "Error: $res" "${SUBMODULE_LOG_FILE}"

            case $res in
                "$SINGLE_REVISION_NEEDED_ERROR" ) 
                                      WriteLog "res:'SINGLE_REVISION_NEEDED_ERROR'" "${SUBMODULE_LOG_FILE}"
                                      while read module;                                                            \
                                      do                                                                            \
                                          WriteLog "module: ${module}" "${SUBMODULE_LOG_FILE}";                      \
                                          cleanUpCmd='rm -rf "'$module'"';                                           \
                                          WriteLog "cmd: ${cleanUpCmd}" "${SUBMODULE_LOG_FILE}";                     \
                                          ${cleanUpCmd} >> ${SUBMODULE_LOG_FILE} 2>&1 ;                             \
                                      done < <(  git config --file .gitmodules --get-regexp path | awk '{ print $2 }' ); 
                                      ;;

                "$RECOVERABLE_ERROR" ) WriteLog "res:'RECOVERABLE_ERROR'" "${SUBMODULE_LOG_FILE}"
                                      while read submodule;                                                         \
                                      do                                                                            \
                                          WriteLog "submodule: ${submodule}" "${SUBMODULE_LOG_FILE}";                \
                                          cleanUpCmd2='rm -rf "'${submodule}'"';                                     \
                                          WriteLog "cmd: ${cleanUpCmd2}" "${SUBMODULE_LOG_FILE}";                    \
                                          ${cleanUpCmd2} >> ${SUBMODULE_LOG_FILE} 2>&1 ;                            \
                                      done < <( git config --file .gitmodules --get-regexp path | awk '{ print $2 }' );                                                                          
                                      ;;                                                                             
                                                                                                                     
                 "$NOT_GIT_REPO_ERROR" ) WriteLog "res:'NOT_GIT_REPO_ERROR'" "${SUBMODULE_LOG_FILE}"                   
                                        tryCount=0
                                        break                                                                   
                                        ;;                                                                           

            esac
            set +x
            tryCount=$(( $tryCount-1 ))
            if [[ $tryCount -ne 0 ]]
            then
                WriteLog "Wait for ${tryDelay} to try again." "${SUBMODULE_LOG_FILE}"
                sleep ${tryDelay}
                continue
            else
                break;
            fi
        fi
       
    done

    wdPid=$( cat ./WatchDog.pid )
    WriteLog "Kill WatchDog (${wdPid})." "${SUBMODULE_LOG_FILE}"

    KillWatchDogAndWaitToDie "${wdPid}" "${SUBMODULE_LOG_FILE}"


    if [[ $tryCount -eq 0 ]]
    then
        WriteLog "Give up ! " "${SUBMODULE_LOG_FILE}"
        # send email to Agyi
        return 1
    fi
    WriteLog "End." "${SUBMODULE_LOG_FILE}"
    return 0

}
