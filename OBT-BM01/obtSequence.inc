BRANCHES_TO_TEST=( 'candidate-8.8.x' 'candidate-8.10.x' )

# For versioning
RUN_1=("BRANCH_ID=candidate-8.10.x" "REGRESSION_NUMBER_OF_THOR_CHANNELS=4") 
RUN_2=("BRANCH_ID=candidate-8.10.x" "KEEP_VCPKG_CACHE=1")
RUN_3=("BRANCH_ID=candidate-8.8.x" "REGRESSION_NUMBER_OF_THOR_CHANNELS=4")
RUN_4=("BRANCH_ID=candidate-8.8.x" "KEEP_VCPKG_CACHE=1")

RUN_ARRAY=(
    RUN_1[@]
    RUN_2[@]
    RUN_3[@]
    RUN_4[@]
)
