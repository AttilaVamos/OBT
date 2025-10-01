#!/bin/bash
clear 

#
#------------------------------
#
# Import settings
#
# Git branch

[[ -f ~/.bash_profile ]] && . ~/.bash_profile


. ./settings.sh

# WriteLog() function

. ./timestampLogger.sh

# UninstallHPCC() fuction

. ./UninstallHPCC.sh


. ./cloneRepo.sh

#
#------------------------------
#
# Constants
#

COVERAGE_ROOT=~/coverage
#TEST_ROOT=~/build/CE/platform
TEST_HOME=${TEST_ROOT}/HPCC-Platform/testing/regress
#BUILD_HOME=~/build/CE/platform/build
BUILD_LOG=${COVERAGE_ROOT}/build_log
LONG_DATE=$(date "+%Y-%m-%d_%H-%M-%S")
COVERAGE_LOG_FILE=${OBT_LOG_DIR}/coverage-${LONG_DATE}.log
LOGDIR=~/HPCCSystems-regression/log

BUILD_ONLY=1
#NUMBER_OF_CPUS=1
WIPE_OUT=1
COVERAGE_BUILD=1
COVERAGE_SOURCE_HOME=~/HPCC-Platform
PKG_SUFFIX="coverage-$(date +%Y-%m-%d)"

DEFAULT_UMASK=$(umask)

#
#----------------------------------------------------
#
# Start Coverage process
#

WriteLog "Coverage test started" "${COVERAGE_LOG_FILE}"

gnome-terminal --title "Build log" -- bash -c "tail -f -n 200 $COVERAGE_LOG_FILE" &

WriteLog "Build type: ${BUILD_TYPE}" $COVERAGE_LOG_FILE


#
#----------------------------------------------------
#
# Clean-up
#

WriteLog "Clean system" "${COVERAGE_LOG_FILE}"

WriteLog "Clean system!" ${BUILD_LOG}

[ ! -e $COVERAGE_ROOT ] && mkdir -p $COVERAGE_ROOT

#${SUDO} rm -rf ${COVERAGE_ROOT}/*
#cd  ${COVERAGE_ROOT}


CLEAN_UP=0 #0   # If coverage build, always clean up first.
BUILD_TYPE=RelWithDebInfo
USE_CPPUNIT=1
SLAVES=4
ECLWATCH_BUILD_STRATEGY=0 #IF_MISSING
TEST_PLUGINS=1  # Need for deploy java queries in Setup
SKIP_PLAYWRIGHT_TEST=1
# Check and patch source files

pushd $COVERAGE_SOURCE_HOME

WriteLog "Check 'cmake_modules/commonSetup.cmake'." "${COVERAGE_LOG_FILE}"
if [[ $(egrep -c 'D_COVERAGE' cmake_modules/commonSetup.cmake) -eq 0 ]]
then
    WriteLog "  Patch it." "${COVERAGE_LOG_FILE}"
    sed -i 's/\(\s*\)if (GENERATE_COVERAGE_INFO)/\1if (GENERATE_COVERAGE_INFO)\
\1  add_definitions (-D_COVERAGE)/g' cmake_modules/commonSetup.cmake
else
    WriteLog "  Already patched" "${COVERAGE_LOG_FILE}"
fi

WriteLog "Check 'system/jlib/jmisc.cpp'." "${COVERAGE_LOG_FILE}"
if [[ $(egrep -c 'Sleep\(5000\)' system/jlib/jmisc.cpp) -eq 0 ]]
then
    WriteLog "  Patch it." "${COVERAGE_LOG_FILE}"
    sed -i 's/\(\s*\)#ifdef _COVERAGE/\1#ifdef _COVERAGE\
\1        __gcov_dump();/g' system/jlib/jmisc.cpp

    sed -i 's/\(\s*\)ClearModuleObjects/\1\/\/ClearModuleObjects/g' system/jlib/jmisc.cpp

    sed -i '/static void UnixAbortHandler(int signo)/ { N; s/static void UnixAbortHandler(int signo)/\nextern "C" void  __gcov_dump(void);\n\n&/ }' system/jlib/jmisc.cpp

else
    WriteLog "  Already patched" "${COVERAGE_LOG_FILE}"
fi


filesToPatch=('ecl/eclcc/eclcc.cpp' 'system/jlib/jmisc.cpp' 'tools/start-stop-daemon/start-stop-daemon.c' 'roxie/ccd/ccdmain.cpp' 'system/jlib/jexcept.cpp')
for fileToPatch in ${filesToPatch[*]}
do
    WriteLog "Check '$fileToPatch'." "${COVERAGE_LOG_FILE}"
    if [[ $(egrep -c '_COVERAGE' $fileToPatch) -eq 0 ]]
    then
        WriteLog "  Patch it." "${COVERAGE_LOG_FILE}"
        sed -i 's/\(\s*\)_exit\(.*\)/\
#ifdef _COVERAGE\
\1exit\2\
#else\
\1_exit\2\
#endif/g' $fileToPatch
    else
        WriteLog "  Already patched" "${COVERAGE_LOG_FILE}"
    fi
done

# Get the current branch information
currentBranch=$( git branch | grep '^\*' | awk '{ print $2 }' )
WriteLog "Current branch: ${currentBranch}" "${COVERAGE_LOG_FILE}"

BRANCH_VERSION=${currentBranch//candidate-/}
WriteLog "Current branch version: ${BRANCH_VERSION}" "${COVERAGE_LOG_FILE}"

branchDate=$( git log -1 | grep '^Date' )
WriteLog "Branch date   : ${branchDate}" "${COVERAGE_LOG_FILE}"

branchCrc=$( git log -1 | grep '^commit' )
WriteLog "Branch Crc    : ${branchCrc}" "${COVERAGE_LOG_FILE}"

popd

WriteLog "Clean-up coverage environment..." "${COVERAGE_LOG_FILE}"

[ ! -d ~/coverage ] && mkdir ~/coverage
export coverage=1
WriteLog "  Done"  "${COVERAGE_LOG_FILE}"

# The '-fprofile-update=atomic' PR merged, but need to do with this linker stuff as well:
# SET (CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fprofile-arcs -ftest-coverage -fprofile-update=atomic")
# SET (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS}  -fprofile-arcs -ftest-coverage -fprofile-update=atomic")


# With '0' skip the patch to check whether this caused the coverage degradation or not. (2025-06-17)
isCoverageFixed=0  # $(egrep -c 'profile-update=atomic' ~/HPCC-Platform/cmake_modules/commonSetup.cmake)
if [[ $isCoverageFixed -eq 1 ]]
then
    sed -i '/fprofile-update=atomic/a \
          # Inserted by build.sh \
          SET (CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fprofile-arcs -ftest-coverage -fprofile-update=atomic") \
          SET (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS}  -fprofile-arcs -ftest-coverage -fprofile-update=atomic")' ~/HPCC-Platform/cmake_modules/commonSetup.cmake
fi
egrep 'profile-update=atomic' ~/HPCC-Platform/cmake_modules/commonSetup.cmake


#--------------------------------------------
# This TinyProxy related part needs to be move after the build is success
# Check if Tinyproxy is running. If yes stop it
if [[ -n "$(pgrep tinyproxy)" ]]
then
    WriteLog "Tinyproxy is running, but probably with default configuration. Stop it."  "${COVERAGE_LOG_FILE}"
    sudo systemctl stop tinyproxy
fi

# Check if Tinyproxy is isntalled, if yes start it
res=$(type "tinyproxy" 2>&1 )
if [[ $? -eq 0 ]]
then
    WriteLog "Tinyproxy is installed, start it with our configuration." "${COVERAGE_LOG_FILE}"
    pushd ~/OBT
    ./checkTinyproxy.sh
    popd
fi
#---------------------------------


pushd $BUILD_HOME
WriteLog "sudo find . -name "*.dir" -type d -exec chmod -R 6777 {} \;" "${COVERAGE_LOG_FILE}"
sudo find . -name "*.dir" -type d -exec chmod -R 6777 {} \;

WriteLog "lcov --zerocounters --directory ." "${COVERAGE_LOG_FILE}"
lcov --zerocounters --directory .

if [[ $CLEAN_UP -eq 1 ]]
then
    WriteLog "Do 'make clean'" "${COVERAGE_LOG_FILE}"
    make clean
    WriteLog "  done." "${COVERAGE_LOG_FILE}"
else
    WriteLog "Skip 'make clean'" "${COVERAGE_LOG_FILE}"
fi

popd


if [[ $COVERAGE_BUILD -eq 1 ]]
then
    WriteLog "                                           " "${COVERAGE_LOG_FILE}"
    WriteLog "*******************************************" "${COVERAGE_LOG_FILE}"
    WriteLog " Build HPCC Platform from ${BUILD_HOME} ..." "${COVERAGE_LOG_FILE}"
    WriteLog "                                           " "${COVERAGE_LOG_FILE}"


    #----------------------------------------------------
    #
    # Uninstall HPCC
    #

    WriteLog "Uninstall HPCC-Platform" "${COVERAGE_LOG_FILE}"

    UninstallHPCC "${COVERAGE_LOG_FILE}" "$WIPE_OUT"


    # --------------------------------------------------------------
    #
    # Build HPCC with coverage
    #

    WriteLog "Build HPCC with coverage in ${BUILD_HOME}" "${COVERAGE_LOG_FILE}"

    [[ ! -d ${BUILD_HOME} ]] && mkdir -p ${BUILD_HOME}

    cd ${BUILD_HOME}

    #CMD="cmake -DGENERATE_COVERAGE_INFO=ON -DCMAKE_BUILD_TYPE=Release"
    #CMD+=" -DUSE_LIBXSLT=ON -DXALAN_LIBRARIES="
    #CMD+=" -DMYSQL_LIBRARIES=/usr/lib64/mysql/libmysqlclient.so -DMYSQL_INCLUDE_DIR=/usr/include/mysql -DMAKE_MYSQLEMBED=1"
    #CMD+="  ../HPCC-Platform"

    GENERATOR="Unix Makefiles"
    CMAKE_CMD=$'cmake '
    #CMAKE_CMD+=$' -G "'${GENERATOR}$'"'
    #CMAKE_CMD+=$' --debug-output'
    #CMAKE_CMD+=$' --trace'
    CMAKE_CMD+=$' -D CMAKE_BUILD_TYPE='$BUILD_TYPE
    CMAKE_CMD+=$' -DINCLUDE_PLUGINS=1 -DTEST_PLUGINS=1'
    CMAKE_CMD+=$' -DMAKE_DOCS='${MAKE_DOCS}
    CMAKE_CMD+=$' -DUSE_CPPUNIT='${USE_CPPUNIT}
    CMAKE_CMD+=$' -DWSSQL_SERVICE='${MAKE_WSSQL}
    #CMAKE_CMD+=$' -DUSE_LIBMEMECACHED='${USE_LIBMEMCACHED}
    #CMAKE_CMD+=$' -DECLWATCH_BUILD_STRATEGY='${ECLWATCH_BUILD_STRATEGY}
    #CMAKE_CMD+=$' -DINCLUDE_SPARK='${ENABLE_SPARK}' -DSUPPRESS_SPARK='${SUPPRESS_SPARK}' -DSPARK='${ENABLE_SPARK}
    CMAKE_CMD+=$' '${PYTHON_PLUGIN}
    CMAKE_CMD+=$' -DCONTAINERIZED='${BUILD_FOR_CLOUD}
    #CMAKE_CMD+=$' -DMAKE_REMBED=1 -D SUPPRESS_REMBED=0'
    CMAKE_CMD+=$' -DUSE_ADDRESS_SANITIZER='${LEAK_CHECK}
    CMAKE_CMD+=$' -DSUPPRESS_MONGODBEMBED='${SUPPRESS_MONGODB}' -DSUPPRESS_NLP='${SUPPRESS_NLP}
    CMAKE_CMD+=$' -DSUPPRESS_WASMEMBED='${SUPPRESS_WASMEMBED}
    CMAKE_CMD+=$' -DGENERATE_COVERAGE_INFO='$COVERAGE_BUILD
    CMAKE_CMD+=$' -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DUSE_LIBXSLT=ON -DXALAN_LIBRARIES= '
    CMAKE_CMD+=$' -DCUSTOM_PACKAGE_SUFFIX='$PKG_SUFFIX
#    CMAKE_CMD+=$' -DUSE_MYSQL=OFF -DUSE_MYSQLEMBED=OFF -DSUPPRESS_MYSQLEMBED=ON'
#    CMAKE_CMD+=$' -DPHONENUMBER=OFF -DSUPPRESS_PHONENUMBER=ON'
#    CMAKE_CMD+=$' -DUSE_OPENTEL_GRPC=OFF'
    CMAKE_CMD+=$' -D CMAKE_ECLIPSE_MAKE_ARGUMENTS=-30'
    CMAKE_CMD+=$' '$COVERAGE_SOURCE_HOME

    WriteLog "CMake cmd:${CMAKE_CMD}" "${COVERAGE_LOG_FILE}"

    TIME_STAMP=$(date +%s)
    ${CMAKE_CMD} >> ${COVERAGE_LOG_FILE} 2>&1

    #make -j 8 package >> ${COVERAGE_LOG_FILE} 2>&1
    # Won't work with 
    CMD="make -j ${NUMBER_OF_BUILD_THREADS} package"
        
    ${CMD} >> ${COVERAGE_LOG_FILE} 2>&1

    if [ $? -ne 0 ] 
    then
       WriteLog "Build failed: no $PKG_EXT package found" "${COVERAGE_LOG_FILE}"
       echo "Build failed: build has errors " >> ${BUILD_LOG}
       buildResult=FAILED
    else
       ls -l hpcc*${PKG_EXT} >/dev/null 2>&1
       if [ $? -ne 0 ] 
       then
          WriteLog "Build failed: no $PKG_EXT  package found" "${COVERAGE_LOG_FILE}"
          echo "Build failed: no $PKG_EXT  package found " >> ${BUILD_LOG}
          buildResult=FAILED
       else
          WriteLog "Build succeed" "${COVERAGE_LOG_FILE}"
          echo "Build succeed" >> ${BUILD_LOG}
          buildResult=SUCCEED
          HPCC_PACKAGE=$( find . -maxdepth 1 -name 'hpccsystems-platform-community*' -type f )    
       fi
    fi

    CURRENT_DATE=$( date "+%Y-%m-%d %H:%M:%S")
    WriteLog "Build ${buildResult} at ${CURRENT_DATE}" "${COVERAGE_LOG_FILE}"

    if [ "$buildResult" = "FAILED" ]
    then

        echo "No Coverage result." >> ./coverage.summary

        cp ./coverage.summary $COVERAGE_ROOT/

        # send email to Agyi
            echo "Coverage build Failed! Check the logs!" | mailx -s "Problem with Coverage" -u $USER  ${ADMIN_EMAIL_ADDRESS}
        
        exit
    fi

    #----------------------------------------------------
    #
    # Install HPCC
    #

    WriteLog "Install HPCC-Platform" "${COVERAGE_LOG_FILE}"
    echo "Install HPCC-Platform"  >> ${BUILD_LOG} 2>&1

    #${SUDO} rpm -i --nodeps ${BUILD_HOME}/hpccsystems-platform?community*.rpm
    res=$( ${SUDO} ${PKG_INST_CMD} ${BUILD_HOME}/${HPCC_PACKAGE} 2>&1)

    if [ $? -ne 0 ]
    then
       echo "TestResult:FAILED" >> $TEST_ROOT/install.summary
       WriteLog "Install HPCC-Platform FAILED" "${COVERAGE_LOG_FILE}"

       exit
    else
       echo "TestResult:PASSED" >> $TEST_ROOT/install.summary
       WriteLog "Install HPCC-Platform PASSED" "${COVERAGE_LOG_FILE}"
    fi
fi


# --------------------------------------------------------------
#
# Set up coverage environment
#

WriteLog "Set up coverage environment" "${COVERAGE_LOG_FILE}"

WriteLog "Set environment to coverage" "${COVERAGE_LOG_FILE}"

WriteLog "  sudo chmod -R 0777 /opt/HPCCSystems /var/lib/HPCCSystems " "${COVERAGE_LOG_FILE}"
sudo chmod -R 0777 /opt/HPCCSystems /var/lib/HPCCSystems

cnt=$(grep -c "^umask" /etc/HPCCSystems/environment.conf)
if [[ $cnt -eq 0 ]]
then
    sudo chmod -R 0777 /etc/HPCCSystems/environment.conf
    echo "umask=0" >> /etc/HPCCSystems/environment.conf
    WriteLog "/etc/HPCCSystems/environment.conf patched." "${COVERAGE_LOG_FILE}"
fi
WriteLog "$(grep "^umask" /etc/HPCCSystems/environment.conf)" "${COVERAGE_LOG_FILE}"

WriteLog "sudo usermod -a -G $USER hpcc" "${COVERAGE_LOG_FILE}"
sudo usermod -a -G $USER hpcc

WriteLog "sudo find . -name "*.dir" -type d -exec chmod -R 777 {} \;" "${COVERAGE_LOG_FILE}"
sudo find . -name "*.dir" -type d -exec chmod -R 777 {} \;

WriteLog "Patch environment.xml for Roxie doesn't use local Slave (to utilise udplib)." "${COVERAGE_LOG_FILE}"
sudo cp -v /etc/HPCCSystems/environment.xml /etc/HPCCSystems/environment.xml-bak1
WriteLog "  before: '"$(egrep -o 'localSlave=\"[a-z]*\"' /etc/HPCCSystems/environment.xml)"'." "${COVERAGE_LOG_FILE}"
sudo sed -i -e 's/localSlave="true"/localSlave="false"/g' /etc/HPCCSystems/environment.xml
WriteLog "  after : '"$(egrep -o 'localSlave=\"[a-z]*\"' /etc/HPCCSystems/environment.xml)"'." "${COVERAGE_LOG_FILE}"



# --------------------------------------------------------------
#
# Start HPCC Systems
#
NUMBER_OF_HPCC_COMPONENTS=$( /opt/HPCCSystems/sbin/configgen -env /etc/HPCCSystems/environment.xml -list | egrep -i -v 'eclagent' | wc -l ) 
WriteLog "Start HPCC system with $NUMBER_OF_HPCC_COMPONENTS components" "${COVERAGE_LOG_FILE}"
#sudo /etc/init.d/hpcc-init start >> $logFile 2>&1
res=$(sudo /etc/init.d/hpcc-init start 2>&1 )
WriteLog "Res:${res}" "${COVERAGE_LOG_FILE}"

stat=$(sudo /etc/init.d/hpcc-init status 2>&1 )
WriteLog "Stat:\n${stat}" "${COVERAGE_LOG_FILE}"

# Test whether here (after the Platform started) is the better place for this
# or it is necessary again
WriteLog "sudo find . -name "*.dir" -type d -exec chmod -R 6777 {} \;" "${COVERAGE_LOG_FILE}"
sudo find . -name "*.dir" -type d -exec chmod -R 6777 {} \;
WriteLog "  done." "${COVERAGE_LOG_FILE}"


if [[ $BUILD_ONLY -eq 1 ]]
then
    WriteLog "That was a build only run. Exit." "${COVERAGE_LOG_FILE}"
    exit
fi


# --------------------------------------------------------------
#
# Prepare regression test in coverage enviromnment
#

WriteLog "Prepare regression test in coverage enviromnment" "${COVERAGE_LOG_FILE}"

echo "Prepare reqgression test" >> ${BUILD_LOG} 2>&1

logDir=${TEST_LOG_DIR}
[ ! -d $logDir ] && mkdir -p $logDir
rm -rf ${logDir}/*

libDir=/var/lib/HPCCSystems/regression
[ ! -d $libDir ] && mkdir  -p  $libDir
rm -rf ${libDir}/*

#
# --------------------------------------------------------------
#
# Run test
#

WriteLog "Run regression test" "${COVERAGE_LOG_FILE}"
echo "Run reqgression test" >> ${BUILD_LOG} 2>&1

cd  $TEST_HOME


WriteLog "Set and export coverage variable for create coverage build" "${COVERAGE_LOG_FILE}"
echo "Set and export coverage variable for create coverage build" >> ${BUILD_LOG} 2>&1

coverage=1
export coverage

# ----------------------------------------------------
#
#From ecl-test v0.15 the 'setup' removed from clusters and it becomes separated sub command (See: HPCC-11071)
#
# Setup should run on all clusters

WriteLog "Setup phase" "${COVERAGE_LOG_FILE}"

./ecl-test list | grep -v "Cluster" |
while read cluster
do

  echo ""

  CMD="./ecl-test setup --target $cluster"
 
  echo "${CMD}" >> ${BUILD_LOG} 2>&1
  WriteLog "${CMD}" "${COVERAGE_LOG_FILE}"

  ${CMD} >> ${COVERAGE_LOG_FILE} 2>&1

  # --------------------------------------------------
  # temporarly fix for wrongly generated setup logfile

  for f in $(ls -1 ${logDir}/${cluster}.*.log)
     do mv $f ${logDir}/setup_${cluster}.${f#*.}
  done

  for f in $(ls -1 ${logDir}/${cluster}-exclusion.*.log)
     do mv $f ${logDir}/setup_${cluster}-exclusion.${f#*.}
  done

  # -------------------------------------------------

  #cp ${logDir}/thor.*.log ${COVERAGE_ROOT}/
  cp ${logDir}/setup_${cluster}*.log ${COVERAGE_ROOT}/

  total=$(cat ${logDir}/setup_${cluster}*.log | sed -n "s/^[[:space:]]*Queries:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p")
  passed=$(cat ${logDir}/setup_${cluster}*.log | sed -n "s/^[[:space:]]*Passing:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p")
  failed=$(cat ${logDir}/setup_${cluster}*.log | sed -n "s/^[[:space:]]*Failure:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p")

  #[ $passed -gt 0 ] && passed="<span style=\"color:#298A08\">$passed</span>"
  #[ $failed -gt 0 ] && failed="<span style=\"color:#FF0000\">$passed</span>"

  echo ${cluster}" Setup Result:Total:${total} passed:$passed failed:$failed" >> ${COVERAGE_ROOT}/setup.summary 
  echo ${cluster}" Setup Result:Total:${total} passed:$passed failed:$failed" >> ${BUILD_LOG} 2>&1
  echo ${cluster}" Setup Result:Total:${total} passed:$passed failed:$failed"
  WriteLog "${cluster} Setup Result:Total:${total} passed:$passed failed:$failed" "${COVERAGE_LOG_FILE}"

done

# -----------------------------------------------------
#
# Run tests
#

WriteLog "Regression Suite phase" "${COVERAGE_LOG_FILE}"

./ecl-test list | grep -v "Cluster" |
while read cluster
do

  CMD="./ecl-test run --target $cluster"
  echo "${CMD}" >> ${BUILD_LOG} 2>&1
  WriteLog "./ecl-test run --target $cluster" "${COVERAGE_LOG_FILE}"

  ${CMD} >> ${COVERAGE_LOG_FILE} 2>&1

  cp ${logDir}/${cluster}*.log ${COVERAGE_ROOT}/

  total=$(cat ${logDir}/${cluster}*.log | sed -n "s/^[[:space:]]*Queries:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p")
  passed=$(cat ${logDir}/${cluster}*.log | sed -n "s/^[[:space:]]*Passing:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p")
  failed=$(cat ${logDir}/${cluster}*.log | sed -n "s/^[[:space:]]*Failure:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p")

  #[ $passed -gt 0 ] && passed="<span style=\"color:#298A08\">$passed</span>"
  #[ $failed -gt 0 ] && failed="<span style=\"color:#FF0000\">$passed</span>"

  echo "TestResult:Total:${total} passed:$passed failed:$failed" > ${COVERAGE_ROOT}/${cluster}.summary
  echo "TestResult:Total:${total} passed:$passed failed:$failed" >> ${BUILD_LOG} 2>&1
  echo ${cluster}" testResult:Total:${total} passed:$passed failed:$failed"
  WriteLog "TestResult:Total:${total} passed:$passed failed:$failed" "${COVERAGE_LOG_FILE}"

done

#service hpcc-init stop
res=$(sudo service hpcc-init stop |grep 'still')
# If the result is "Service dafilesrv, mydafilesrv is still running."
if [[ -n $res ]]
then
   echo $res
   sudo service dafilesrv stop
fi

#
# --------------------------------------------------------------
#
# Generate coverage report
#

WriteLog "Generate coverage report" "${COVERAGE_LOG_FILE}"

echo "Generate coverage report"  >> ${BUILD_LOG} 2>&1

cd $BUILD_HOME
${SUDO} lcov --capture --directory . --output-file $COVERAGE_ROOT/hpcc_coverage.lcov > $COVERAGE_ROOT/lcov.log 2>&1

${SUDO} genhtml --highlight --legend --ignore-errors source --output-directory $COVERAGE_ROOT/hpcc_coverage $COVERAGE_ROOT/hpcc_coverage.lcov > $COVERAGE_ROOT/genhtml.log 2>&1

cd $COVERAGE_ROOT

WriteLog "Generate coverage report summary" "${COVERAGE_LOG_FILE}"

echo "Generate coverage summary" >> ${BUILD_LOG} 2>&1

grep -i "coverage rate" -A3 ./genhtml.log > coverage.summary
echo "(This is an experimental result, yet. Use it carefully.)" >> coverage.summary

cp coverage.summary ~/test/


umask $DEFAULT_UMASK

WriteLog "Uninstall HPCC-Platform" "${COVERAGE_LOG_FILE}"

UninstallHPCC "${COVERAGE_LOG_FILE}"


#-----------------------------------------------------------------------------
#
# End of Coverage process
#
#

WriteLog "End of Coverage process" "${COVERAGE_LOG_FILE}"

echo ""
echo "End."
echo "End." >> ${BUILD_LOG} 2>&1


