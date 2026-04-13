BRANCHES_TO_TEST=( 'master' 'candidate-10.4.x' 'candidate-10.2.x' 'candidate-10.0.x' 'candidate-9.14.x' 'candidate-9.12.x' )

# For versioning
0: RUN_1=("BRANCH_ID=master")
1: RUN_2=("BRANCH_ID=candidate-10.4.x")
2: RUN_3=("BRANCH_ID=candidate-10.2.x")
3: RUN_4=("BRANCH_ID=candidate-10.0.x")
4: RUN_5=("BRANCH_ID=candidate-9.14.x")
5: RUN_6=("BRANCH_ID=candidate-9.12.x")
 
if [[ "$BUILD_TYPE" == "RelWithDebInfo" ]]
then
  RUN_ARRAY=(
    RUN_1[@]    # master (1 ch/th sl)
    RUN_2[@]    # candidate-10.4.x (1 ch/th sl)
    RUN_3[@]    # candidate-10.2.x (1 ch/th sl)
    RUN_4[@]    # candidate-10.0.x (1 ch/th sl)
    RUN_5[@]    # candidate-9.14.x (1 ch/th sl)
    RUN_6[@]    # candidate-9.12.x (1 ch/th sl)
  )
else
  # The debug testing is slow, use less branches and versions
  RUN_ARRAY=(
    RUN_1[@]    # master (1 ch/th sl)
    RUN_2[@]    # candidate-10.4.x (1 ch/th sl)
    RUN_3[@]    # candidate-10.2.x (1 ch/th sl)
    RUN_4[@]    # candidate-10.0.x (1 ch/th sl)
  )
fi
