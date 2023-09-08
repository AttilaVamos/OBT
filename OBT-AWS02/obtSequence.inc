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
    RUN_1[@]
    RUN_2[@]
    RUN_3[@]
    RUN_4[@]
    RUN_5[@]
    RUN_6[@]
    RUN_7[@]
    RUN_8[@]
  )
else
  # The debug testing is slow, use less branches and versions
  RUN_ARRAY=(
    RUN_1[@]
    RUN_2[@]
    RUN_3[@]
    RUN_4[@]
    RUN_5[@]
  )
fi
