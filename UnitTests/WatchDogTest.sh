if [ -f WatchDogResults.txt ] 
then
    rm WatchDogResults.txt
fi

watchDogStartCmd="python3 WatchDog.py -p 'git-*' -t 900 -r 3600 -v"
$watchDogStartCmd >> WatchDogResults.txt

if [ -f WatchDogResults.txt ] 
then
    echo "WatchDog Results File Created"
fi

