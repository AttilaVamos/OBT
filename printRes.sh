#!/bin/bash

PrintRes()
{
    prefix=$1
    retCode=$2
    msg=$3

    printf "%sReturn code: %s\n" "$prefix" "$retCode"
    
    while read line
    do
        printf "%s%s\n" "$prefix" "$line"
    done < <(echo "$msg" )
    
    echo " "
}

