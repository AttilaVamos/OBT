#!/usr/bin/bash

FILES_CHECKED=0
FILES_FIXED=0

while read fn; 
do 
    FILES_CHECKED=$(( FILES_CHECKED + 1 ))
    res=$(cat $fn | python3 -m json.tool > /dev/null 2>&1)
    if [[ $? -ne 0 ]]
    then
        printf "%-70s -> Bad\n" "$fn" 
        res=$(mv -v $fn $fn-bkp;  )
        printf "%-70s -> Rename\n" "$fn" 
        cat $fn-bkp | python3 -c "import sys, json, yaml; print(json.dumps(yaml.safe_load(sys.stdin)))" | jq '.' > $fn ; 
        
        cat $fn | python3 -m json.tool > /dev/null
        if [[ $? -eq 0 ]] 
        then
            printf "%-70s    Fixed\n" " "
            printf "%-70s    \n" "$(rm -v $fn-bkp)"
            FILES_FIXED=$(( FILES_FIXED + 1 ))
        else
            printf "%-70s  Error, restore file\n" " "
            res=$(mv -v $fn-bkp $fn; )
        fi
    else
        printf "%-70s -> OK\n" "$fn" 
    fi
        
done< <(find ~/gists/ -iname '*2025-*.json' -type f)

printf "End.\n  %5d file(s) checked, %5d file(s) fixed.\n" "$FILES_CHECKED" "$FILES_FIXED"

