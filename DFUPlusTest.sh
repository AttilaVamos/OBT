#!/bin/bash

. ./printRes.sh

DEBUG=1

DROPZONE="/var/lib/HPCCSystems/mydropzone"

# Get some logical file names from the platform

echo "Get logical file namse with filter '*::book'"
files=( $(dfuplus action=list server=. name='*::book' | egrep -v 'List ') )
for file in ${files[@]}
do
    echo "  $file"
done

echo "Done"
echo "--------------------------------------------------------"

# Despray them

echo "Despray files"

prefix="    "

for file in ${files[@]}
do
    srcFile="$file"
    dstFile="${file}-despray"
    echo "  Despray '$srcFile' to '$dstFile'"
    res=$( dfuplus action=despray server=. srcdali=. srcname=${srcFile} dstip=. dstfile=${dstFile} overwrite=1 2>&1)
    retCode=$?
    [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"
done

echo "Done"
echo "--------------------------------------------------------"


# Spray them back

echo "Spray files"
prefix="      "

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

echo "Done."

echo "--------------------------------------------------------"

# Copy original files

echo "Copy files"
prefix="      "

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

echo "Done."
echo "--------------------------------------------------------"

# Rename copied files

prefix="      "
echo "Rename files"

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
WUID=$(echo "$res" | egrep -o 'D[0-9\-].*' | head -n 1)

echo "Done."

echo "--------------------------------------------------------"

#Get WU status
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
dstFile=${files[0]}

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


dstFile=${files[1]}

echo "Erase history of $dstFile with backup:"
res=$( dfuplus action=erasehistory server=. srcdali=. lfn=$dstFile dstxml="${dstFile}.history" 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

[[ -f ${dstFile}.history ]] && echo "${prefix}Backup file: '${dstFile}.history' exists."

echo " "

echo "History of $dstFile (xml):"
res=$( dfuplus action=listhistory server=. srcdali=. lfn=$dstFile 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

rm -v "${dstFile}.history"

echo "Done."
echo "--------------------------------------------------------"

# Superfile related actions

SUPERFILE_NAME="DFUPlus-superfile-test"
subfiles=( $(dfuplus action=list server=. name='*::book-*-renamed' | egrep -v 'List ' | head -n 2) )

echo "Create superfile: '$SUPERFILE_NAME' with subfiles: '${subfiles[0]},${subfiles[1]}'"
res=$( dfuplus action=addsuper server=. srcdali=. superfile=$SUPERFILE_NAME subfiles=${subfiles[0]},${subfiles[1]} 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "List superfile: '$SUPERFILE_NAME'"
res=$( dfuplus action=listsuper server=. srcdali=. superfile='.::'$SUPERFILE_NAME 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "Remove superfile: '$SUPERFILE_NAME' with subfiles: '${subfiles[0]},${subfiles[1]}' with 'delete=0' (keep sub-files)."
res=$( dfuplus action=removesuper server=. srcdali=. superfile="$SUPERFILE_NAME" subfiles="${subfiles[0]},${subfiles[1]}" delete=0 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "Check the superfile: '$SUPERFILE_NAME'"
res=$( dfuplus action=listsuper server=. srcdali=. superfile='.::'$SUPERFILE_NAME 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "Check the sub-files"
res=( $(dfuplus action=list server=. name='*::book-*-renamed' | egrep -v 'List ' | head -n 2) )
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$( for f in ${res[@]}; do echo "'$f'"; done)"



# Same as above, but now delete sub-files as well

echo "Create superfile: '$SUPERFILE_NAME' with subfiles: '${subfiles[0]},${subfiles[1]}'"
res=$( dfuplus action=addsuper server=. srcdali=. superfile=$SUPERFILE_NAME subfiles=${subfiles[0]},${subfiles[1]} 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "List superfile: '$SUPERFILE_NAME'"
res=$( dfuplus action=listsuper server=. srcdali=. superfile='.::'$SUPERFILE_NAME 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "Remove superfile: '$SUPERFILE_NAME' with subfiles: '${subfiles[0]},${subfiles[1]}' with 'delete=1' (delete sub-files)."
res=$( dfuplus action=removesuper server=. srcdali=. superfile="$SUPERFILE_NAME" subfiles="${subfiles[0]},${subfiles[1]}" delete=1 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "Check the superfile: '$SUPERFILE_NAME'"
res=$( dfuplus action=listsuper server=. srcdali=. superfile='.::'$SUPERFILE_NAME 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"


echo "Check the sub-files"
res=( $(dfuplus action=list server=. name='regress::multi::book-*-renamed' | egrep -v 'List ' | head -n 2) )
retCode=$?
if [[ ${#res[@]} -eq 0 ]] 
then
    echo "All sub-files removed"
else
    [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$( for f in ${res[@]}; do echo "'$f'"; done)"
fi


echo "Done."
echo "--------------------------------------------------------"

# Savexml and add actions

srcName=$(dfuplus action=list server=. name='*::book' | egrep -v 'List ' | head -n 1)
dstXml=${srcName##*::}-save.xml
echo "Save logical file '$srcName' into '$dstXml' file."

res=$(dfuplus action=savexml server=. srcdali=. srcname=$srcName dstxml=$dstXml 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

[[ -f ${dstXml} ]] && echo "${prefix}XML file: '${dstXml}' exists."


dstName=${srcName}-added
echo "Add logical file '$dstName' from '$dstXml'."

res=$(dfuplus action=add server=. srcdali=. srcxml=$dstXml dstname=$dstName 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

echo "Check the added-file"
res=$(dfuplus action=list server=. name=$dstName 2>&1)
retCode=$?
[[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"

rm -v ${dstXml}

echo "Done."
echo "--------------------------------------------------------"


# Delete all newly created files

echo "Delete newly created logical files"

files=( $(dfuplus action=list server=. name='*::book-*' | egrep -v 'List ') )
prefix="    "

for file in ${files[@]}
do
    echo "Delete file: $file"
    res=$( dfuplus action=remove server=. srcdali=. name=${file} 2>&1)
    retCode=$?
    [[ $retCode -ne 0 || $DEBUG -eq 1 ]] && PrintRes "$prefix" "$retCode" "$res"
done
echo ""

# Delete leftover files from DropZone
echo "Clean-up $DROPZONE"
find $DROPZONE/ -iname '*::book-*' -type f -print -delete

echo "Done."
echo "--------------------------------------------------------"

echo "Done."

echo "End of tests."
