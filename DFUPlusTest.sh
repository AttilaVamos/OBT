#!/bin/bash

DEBUG=1

DROPZONE="/var/lib/HPCCSystems/mydropzone"

# Get some logical file names from the platform
files=( $(dfuplus action=list server=. name='*::book' | egrep -v 'List ') )
for file in ${files[@]}
do
    echo "$file"
done

echo "--------------------------------------------------------"

# Despray them
for file in ${files[@]}
do
    echo "File to despray: $file"
    res=$( dfuplus action=despray server=. srcdali=. srcname=${file} dstip=. dstfile=${file}-despray overwrite=1 2>&1)
    retCode=$?
    [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && printf "  Return code: %s\n  Result: %s\n\n" $retCode "$res"
done

echo "--------------------------------------------------------"

# Spray them back
for destCluster in {"mythor","myroxie"}
do
    echo "Target: ${destCluster}"
    for file in ${files[@]}
    do
        echo "  File to copy: $file"
        res=$( dfuplus action=spray server=. srcdali=. srcip=. srcfile=${DROPZONE}/${file}-despray dstip=. dstname=${file}-$destCluster-spray dstcluster=$destCluster format=csv overwrite=1 2>&1)
        retCode=$?
        [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && printf "  Return code: %s\n    Result: %s\n\n" $retCode "$res"
    done
done

echo "--------------------------------------------------------"

# Copy original files
for destCluster in {"mythor","myroxie"}
do
    echo "Target: ${destCluster}"
    for file in ${files[@]}
    do
        echo "  File to copy: $file"
        res=$( dfuplus action=copy server=. srcdali=. srcname=${files[0]} dstip=. dstcluster=$destCluster dstname=${files[0]}-$destCluster-copy overwrite=1 2>&1)
        retCode=$?
        [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && printf "  Return code: %s\n    Result: %s\n\n" $retCode "$res"
    done
done

echo "--------------------------------------------------------"

# Rename copied files
for destCluster in {"mythor","myroxie"}
do
    echo "Target: ${destCluster}"
    for file in ${files[@]}
    do
        echo "  File to rename: $file"
        res=$( dfuplus action=rename server=. srcdali=. srcname=${files[0]}-$destCluster-copy dstip=. dstcluster=myroxie dstname=${files[0]}-$destCluster-copy-renamed overwrite=1 2>&1)
        retCode=$?
        [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && printf "  Return code: %s\n    Result: %s\n\n" $retCode "$res"
    done
done

echo "--------------------------------------------------------"

# Delete all newly created files
files=( $(dfuplus action=list server=. name='*::book-*' | egrep -v 'List ') )

for file in ${files[@]}
do
    echo "Delete file: $file"
    res=$( dfuplus action=remove server=. srcdali=. name=${file} 2>&1)
    retCode=$?
    [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && printf "  Return code: %s\n    Result: %s\n\n" $retCode "$res"
done




