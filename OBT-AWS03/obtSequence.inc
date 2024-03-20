BRANCHES_TO_TEST=( 'master' 'candidate-9.6.x' 'candidate-9.4.x' 'candidate-9.2.x' 'candidate-9.0.x' 'candidate-8.12.x' )
 
# For versioning
RUN_1=("BRANCH_ID=master")
RUN_2=("BRANCH_ID=candidate-9.6.x")
RUN_3=("BRANCH_ID=candidate-9.4.x")
 
if [[ "$BUILD_TYPE" == "RelWithDebInfo" ]]
then
  RUN_ARRAY=(
    RUN_1[@]    # master (1 ch/th sl)
    RUN_2[@]    # candidate-9.6.x (1 ch/th sl)
    RUN_3[@]    # candidate-9.4.x (1 ch/th sl)
  )
else
  # The debug testing is slow, use less branches and versions
  RUN_ARRAY=(
    RUN_1[@]    # master (1 ch/th sl)
    RUN_2[@]    # candidate-9.6.x (1 ch/th sl)
    RUN_3[@]    # candidate-9.4.x (1 ch/th sl)
  )
fi
