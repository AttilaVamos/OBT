echo "Start $0"

echo "Start hthor log collection..."
exec find /common/nightly_builds/HPCC/ -iname 'hthor.*.log' -type f -print | sort | zip -u HthorLogCollection -@ > HthorLogCollection.log &

echo "Start thor log collection..."
exec find /common/nightly_builds/HPCC/ -iname 'thor.*.log' -type f -print | sort | zip -u ThorLogCollection -@ > ThorLogCollection.log &

echo "Start roxie log collection..."
exec find /common/nightly_builds/HPCC/ -iname 'roxie.*.log' -type f -print | sort | zip -u RoxieLogCollection -@  > RoxieLogCollection.log &

echo "Start unit test log collection..."
exec find /common/nightly_builds/HPCC/ -iname 'unittest*.log' -type f -print | sort | zip -u UnittestsLogCollection -@  > UnittestsLogCollection.log &

echo "Start ML test log collection..."
exec find /common/nightly_builds/HPCC/ -iname 'mltest*.log' -type f -print | sort | zip -u MlLogCollection -@  > MlLogCollection.log &

echo "Start unit WUTool test log collection..."
exec find /common/nightly_builds/HPCC/ -iname 'wutooltest*.log' -type f -print | sort | zip -u WutooltestLogCollection -@  > WutooltestLogCollection.log &

echo "Start build log collection..."
exec find /common/nightly_builds/HPCC/ -iname 'build*.log' -type f -print | sort | zip -u BuildLogCollection -@  > BuildLogCollection.log &


echo "Wait for processes finished."

wait 

echo "All processes are finished, upload results.."

rsync -va -e "ssh -i ~/AWSSmoketest.pem"  ~/*Collection*.zip ec2-user@ec2-3-133-112-185.us-east-2.compute.amazonaws.com:/home/ec2-user/OBT-010/LogCollections/.

echo "Upload done."

echo "Clean-up /common (delete all results older than 90 days)"
find /common/nightly_builds/HPCC/ -maxdepth 2 -mtime +90 -type d -print -exec rm -rf '{}' \;

echo "Clen-up done."

echo "End."

