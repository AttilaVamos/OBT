#!/bin/bash

echo "Publishing latest coverage result start..."

latest=$( find $HOME -iname 'hpcc_cover*.zip' -type f | sort -r | head -n 1 )
echo "Latest: $latest"
latestDir=${latest%.zip}
latestDir=${latestDir##*/}
echo "Latest dir: $latestDir"

pushd /var/www/html/coverage/ > /dev/null

if [[ ! -d $latestDir ]]
then
    echo "Unzip latest result..."
    res=$( sudo unzip $latest 2>&1 )
    retCode=$?
    [[ $retCode -ne 0 ]] && echo "retCode: $retCode"
    echo "  Done."

    res=$( sudo rm -v *.l[oc]* 2>&1)
    retCode=$?
    [[ $retCode -ne 0 ]] && echo "retCode: $retCode"

    tags=( 'latest' 'previous' 'old' )
    results=( $( find . -iname '*-filt*' -type d | sort -r | head -n 3) )

    echo "Remove current links..."
    sudo rm -v hpcc_coverage-[lop]*
    echo "  Done."

    echo "Create new links:"
    i=0
    for res in ${results[@]}
    do
        tag=${tags[i]};
        printf "\t%d: %s -> %s\n" "$i" "$tag" "$res"

        sudo ln -sf $res hpcc_coverage-$tag
        i=$(( $i + 1 ))
    done
    echo "  Done."
else
    echo "$latestDir already published."
fi

ls -l

popd > /dev/null
echo "  End."
