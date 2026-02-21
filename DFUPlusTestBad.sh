#!/bin/bash

. ./printRes.sh

DEBUG=1

DROPZONE="/var/lib/HPCCSystems/mydropzone"

# Delete leftover files
echo "Clean-up"
find $DROPZONE/ -iname '*::book-*' -type f -print -delete

echo "Done."
echo "--------------------------------------------------------"

# Get some logical file names from the platform
echo "Get logical file namse with filter '*::book'"

files=( $(dfuplus action=list server=. name='*::book' | egrep -v 'List ') )
for file in ${files[@]}
do
    echo "$file"
done
echo "Done."

unset file

echo "--------------------------------------------------------"
echo "Wrong despray..."

prefix="    "

echo "  Despray with empty parameters"
res=$( dfuplus action=despray server=. srcdali=. srcname=${srcFile} dstip=. dstfile=${dstFile} overwrite=1 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"
echo "Done"

# Despray with wrong source file name
for file in ${files[@]}
do
    srcFile="$file-bad"
    dstFile="${file}-despray"
    echo "  Despray '$srcFile' to '$dstFile'"
    res=$( dfuplus action=despray server=. srcdali=. srcname=${srcFile} dstip=. dstfile=${dstFile} overwrite=1 2>&1)
    retCode=$?
    [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"
done
echo "Done"

unset file srcFile dstFile

echo "--------------------------------------------------------"
echo "Wrong spray..."

prefix="      "

echo "  Spray with empty parameters"
res=$( dfuplus action=spray server=. srcdali=. srcip=. srcfile=${DROPZONE}/${srcFile} dstip=. dstname=${dstFile} dstcluster=$destCluster format=csv overwrite=1 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "  Spray with wrong dropzone parameters"
srcFile="${files[0]}-despray"
destCluster=mythor
dstFile="${files[0]}-hthor-spray"
res=$( dfuplus action=spray server=. srcdali=. srcip=. srcfile=${DROPZONE}-a/${srcFile} dstip=. dstname=${dstFile} dstcluster=$destCluster format=csv overwrite=1 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "  Spray with wrong dstcluster naname parameters"
srcFile="${files[0]}-despray"
destCluster=hthor
dstFile="${files[0]}-${destCluster}-spray"
res=$( dfuplus action=spray server=. srcdali=. srcip=. srcfile=${DROPZONE}/${srcFile} dstip=. dstname=${dstFile} dstcluster=$destCluster format=csv overwrite=1 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"


# Spray not existing files back
for destCluster in {"mythor","myroxie"}
do
    echo "  Target: ${destCluster}"
    for file in ${files[@]}
    do
        srcFile="$file-despray"
        dstFile="${file}-$destCluster-spray"
        echo "    Spray '$srcFile' to '$dstFile'"
        res=$( dfuplus action=spray server=. srcdali=. srcip=. srcfile=${DROPZONE}/${srcFile} dstip=. dstname=${dstFile} dstcluster=$destCluster format=csv overwrite=1 2>&1)
        retCode=$?
        [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"
    done
done
echo "Done"

unset file srcFile dstFile

echo "--------------------------------------------------------"
echo "Wrong copy..."

prefix="      "

echo "  Copy with empty parametrers"
res=$( dfuplus action=copy server=. srcdali=. srcname=${srcFile} dstip=. dstcluster=$destCluster dstname=${dstFile} overwrite=1 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

# Copy not existing files
for destCluster in {"mythor","myroxie"}
do
    echo "  Target: ${destCluster}"
    for file in ${files[@]}
    do
        srcFile="${file}-$destCluster-spray"
        dstFile="${file}-$destCluster-copy"
        echo "    Copy '$srcFile' to '$dstFile'."
        res=$( dfuplus action=copy server=. srcdali=. srcname=${srcFile} dstip=. dstcluster=$destCluster dstname=${dstFile} overwrite=1 2>&1)
        retCode=$?
        [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"
    done
done
echo "Done"

unset file srcFile dstFile

echo "--------------------------------------------------------"
echo "Wrong rename..."

prefix="      "

echo "  Rename with empty parameters"
res=$( dfuplus action=rename server=. srcdali=. srcname=${srcFile} dstip=. dstcluster=myroxie dstname=${dstFile} overwrite=1 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

# Rename copied files
for destCluster in {"mythor","myroxie"}
do
    echo "  Target: ${destCluster}"
    for file in ${files[@]}
    do
        srcFile="${file}-$destCluster-copy"
        dstFile="${file}-$destCluster-renamed"
        echo "    Rename '$srcFile' to '$dstFile'"
        res=$( dfuplus action=rename server=. srcdali=. srcname=${srcFile} dstip=. dstcluster=myroxie dstname=${dstFile} overwrite=1 2>&1)
        retCode=$?
        [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"
    done
done
echo "Done"

unset file srcFile dstFile

echo "--------------------------------------------------------"

#Get WU status
WUID="$(echo "$res" | egrep -o 'D[0-9\-].*' | head -n 1)-1"

echo "Status of $WUID:"
prefix="  "

res=$( dfuplus action=status server=. srcdali=. wuid=$WUID 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "Done."
echo "--------------------------------------------------------"

#Get logical file history

prefix="  "

files=( $(dfuplus action=list server=. name='*::book-*' | egrep -v 'List ' | head -n 2) )
dstFile="${files[0]}-bad"

echo "History of $dstFile (xml):"
res=$( dfuplus action=listhistory server=. srcdali=. lfn=$dstFile 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "History of $dstFile (csv with heaer):"
res=$( dfuplus action=listhistory server=. srcdali=. lfn=$dstFile  outformat=csv 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "History of $dstFile (csv without heaer):"
res=$( dfuplus action=listhistory server=. srcdali=. lfn=$dstFile  outformat=csv csvheader=0 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "History of $dstFile (json):"
res=$( dfuplus action=listhistory server=. srcdali=. lfn=$dstFile  outformat=json 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "Erase history of $dstFile:"
res=$( dfuplus action=erasehistory server=. srcdali=. lfn=$dstFile backup=0 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "History of $dstFile (xml):"
res=$( dfuplus action=listhistory server=. srcdali=. lfn=$dstFile 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"


dstFile="${files[1]}-bad"

echo "Erase history of $dstFile with backup:"
res=$( dfuplus action=erasehistory server=. srcdali=. lfn=$dstFile dstxml="${dstFile}.history" 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"


echo "Erase history of $dstFile with backup and wrong target:"
res=$( dfuplus action=erasehistory server=. srcdali=. lfn=$dstFile dstxml="/${dstFile}.history"  2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "Erase history of $dstFile without backup and wrong target:"
res=$( dfuplus action=erasehistory server=. srcdali=. lfn=$dstFile dstxml="/${dstFile}.history backup=0"  2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"


[[ -f ${dstFile}.history ]] && echo "${prefix}Backup file: '${dstFile}.history' exists."

echo " "

echo "History of $dstFile (xml):"
res=$( dfuplus action=listhistory server=. srcdali=. lfn=$dstFile 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

find . -iname "${dstFile}.history" -type f -print -delete

echo "Done."
echo "--------------------------------------------------------"

echo "Clean-up..."

prefix="    "
# Delete all newly created files
files=( $(dfuplus action=list server=. name='*::book-*' | egrep -v 'List ') )

echo "  Delete with empty parameters"
res=$( dfuplus action=remove server=. srcdali=. name=${file} 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

for file in ${files[@]}
do
    echo "  Delete file: $file"
    res=$( dfuplus action=remove server=. srcdali=. name=${file} 2>&1)
    retCode=$?
    [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"
done

echo "Done"

echo "End."
