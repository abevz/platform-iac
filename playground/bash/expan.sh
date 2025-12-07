# expan.sh
#!/bin/bash

export IFS='-'

cnt=1

# Printing the data available in $*
echo "Values of \"\$*\":"
for arg in "$*"; do
  echo "Arg #$cnt= $arg"
  let "cnt+=1"
done

cnt=1

# Printing the data available in $@
echo "Values of \"\$@\":"
for arg in "$@"; do
  echo "Arg #$cnt= $arg"
  let "cnt+=1"
done
