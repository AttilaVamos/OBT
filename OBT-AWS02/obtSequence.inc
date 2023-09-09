BRANCHES_TO_TEST=( 'master' 'candidate-9.4.x' 'candidate-9.2.x' 'candidate-9.0.x' 'candidate-8.12.x' )
 
# For versioning
RUN_1=("BRANCH_ID=master")
RUN_2=("BRANCH_ID=candidate-9.4.x" "REGRESSION_NUMBER_OF_THOR_CHANNELS=4")
RUN_3=("BRANCH_ID=candidate-9.4.x" "KEEP_VCPKG_CACHE=1")
RUN_4=("BRANCH_ID=candidate-9.2.x" "REGRESSION_NUMBER_OF_THOR_CHANNELS=4")
RUN_5=("BRANCH_ID=candidate-9.2.x" "KEEP_VCPKG_CACHE=1")
RUN_6=("BRANCH_ID=candidate-9.0.x" "REGRESSION_NUMBER_OF_THOR_CHANNELS=4")
RUN_7=("BRANCH_ID=candidate-9.0.x" "KEEP_VCPKG_CACHE=1")
RUN_8=("BRANCH_ID=candidate-8.12.x" "REGRESSION_NUMBER_OF_THOR_CHANNELS=4")
 
if [[ "$BUILD_TYPE" == "RelWithDebInfo" ]]
then
  RUN_ARRAY=(
    RUN_1[@]    # master (1 ch/th sl)
    RUN_2[@]    # candidate-9.4.x (4 ch/th sl)
    RUN_3[@]    # candidate-9.4.x (1 ch/th sl)
    RUN_4[@]    # candidate-9.2.x (4 ch/th sl)
    RUN_5[@]    # candidate-9.2.x (1 ch/th sl)
    RUN_6[@]    # candidate-9.0.x (4 ch/th sl)
    RUN_7[@]    # candidate-9.0.x (1 ch/th sl)
    RUN_8[@]    # candidate-8.12.x (4 ch/th sl)
  )
else
  # The debug testing is slow, use less branches and versions
  RUN_ARRAY=(
    RUN_1[@]    # master (1 ch/th sl)
    RUN_2[@]    # candidate-9.4.x (4 ch/th sl)
    RUN_3[@]    # candidate-9.4.x (1 ch/th sl)
    RUN_4[@]    # candidate-9.2.x (4 ch/th sl)
    RUN_5[@]    # candidate-9.2.x (1 ch/th sl)
  )
fi
