BRANCHES_TO_TEST=( 'master' 'candidate-9.14.x' 'candidate-9.12.x' 'candidate-9.10.x' 'candidate-9.8.x' )
 
# For versioning
RUN_1=("BRANCH_ID=master")
RUN_2=("BRANCH_ID=candidate-9.14.x")
RUN_3=("BRANCH_ID=candidate-9.12.x")
RUN_4=("BRANCH_ID=candidate-9.10.x")
RUN_5=("BRANCH_ID=candidate-9.8.x")  # Causes too long run on Coverity buid days.
RUN_6=("BRANCH_ID=candidate-9.6.x")  # Causes too long run on Coverity buid days.
 
if [[ "$BUILD_TYPE" == "RelWithDebInfo" ]]
then
  RUN_ARRAY=(
    RUN_1[@]    # master (1 ch/th sl)
    RUN_2[@]    # candidate-9.14.x (1 ch/th sl)
    RUN_3[@]    # candidate-9.12.x (1 ch/th sl)
    RUN_4[@]    # candidate-9.10.x (1 ch/th sl)
  )
else
  # The debug testing is slow, use less branches and versions
  RUN_ARRAY=(
    RUN_1[@]    # master (1 ch/th sl)
    RUN_2[@]    # candidate-9.14.x (1 ch/th sl)
    RUN_3[@]    # candidate-9.12.x (1 ch/th sl)
  )
fi
