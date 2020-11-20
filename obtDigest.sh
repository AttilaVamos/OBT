TODAY="$(date +%Y.%m.%d)"

find ~/OBT-*/ -name 'OBT-*' -type f -exec bash -c "echo '{}' ;tail -n 10 '{}'" \; | egrep '^'"${TODAY}"'|OBT'

IFS=$'\n'

fs=$( find ~/OBT-*/ -name 'OBT-*' -type f -print )
for f in ${fs[@]}
do
    echo "$f"
    ls=$( echo " $(tail -n 10 $f | egrep '^'${TODAY} )" )
    for l in ${ls[@]}
    do
        echo "line:$l"
        b=$( echo "$l" | cut  -f 1,3 )
        #echo "$b"
    done

done

unset IFS

