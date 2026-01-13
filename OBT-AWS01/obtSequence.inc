BRANCHES_TO_TEST=( 'master' 'candidate-10.2.x' 'candidate-10.0.x' 'candidate-9.14.x' 'candidate-9.12.x' 'candidate-9.10.x' )

# For versioning
RUN_1=("BRANCH_ID=master")
RUN_2=("BRANCH_ID=candidate-10.2.x")
RUN_3=("BRANCH_ID=candidate-10.0.x")
RUN_4=("BRANCH_ID=candidate-9.14.x")
RUN_5=("BRANCH_ID=candidate-9.12.x")
RUN_6=("BRANCH_ID=candidate-9.10.x")
 
if [[ "$BUILD_TYPE" == "RelWithDebInfo" ]]
then
  RUN_ARRAY=(
    RUN_1[@]    # master (1 ch/th sl)
    RUN_2[@]    # candidate-10.2.x (1 ch/th sl)
    RUN_3[@]    # candidate-10.0.x (1 ch/th sl)
    RUN_4[@]    # candidate-9.14.x (1 ch/th sl)
    RUN_5[@]    # candidate-9.12.x (1 ch/th sl)
    RUN_6[@]    # candidate-9.10.x (1 ch/th sl)
  )
else
  # The debug testing is slow, use less branches and versions
  RUN_ARRAY=(
    RUN_1[@]    # master (1 ch/th sl)
    RUN_2[@]    # candidate-10.2.x (1 ch/th sl)
    RUN_3[@]    # candidate-10.0.x (1 ch/th sl)
    RUN_4[@]    # candidate-9.14.x (1 ch/th sl)
  )
fi
