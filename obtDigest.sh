TODAY="$(date +%Y.%m.%d)"

find ~/OBT-*/ -name 'OBT-*' -type f -exec bash -c "echo '{}' ;tail -n 10 '{}'" \; | egrep '^'"${TODAY}"'|OBT'
