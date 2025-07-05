#!/bin/sh

HOME=${ROBOT_WORK_DIR}

if [ "${ROBOT_TEST_RUN_ID}" = "" ]
then
    ROBOT_REPORTS_FINAL_DIR="${ROBOT_REPORTS_DIR}"
else
    REPORTS_DIR_HAS_TRAILING_SLASH=`echo ${ROBOT_REPORTS_DIR} | grep -c '/$'`

    if [ ${REPORTS_DIR_HAS_TRAILING_SLASH} -eq 0 ]
    then
        ROBOT_REPORTS_FINAL_DIR="${ROBOT_REPORTS_DIR}${ROBOT_TEST_RUN_ID}"
    else
        ROBOT_REPORTS_FINAL_DIR="${ROBOT_REPORTS_DIR}/${ROBOT_TEST_RUN_ID}"
    fi
fi

# Ensure the output folder exists
mkdir -p ${ROBOT_REPORTS_FINAL_DIR}

# Check if additional dependencies should be installed via pip
if [ -e "/opt/robotframework/pip-requirements.txt" ]
then
    echo "Installing pip dependencies..."

    mkdir -p ${ROBOT_DEPENDENCY_DIR}
    pip install -r /opt/robotframework/pip-requirements.txt -t ${ROBOT_DEPENDENCY_DIR}

    export PYTHONPATH=${ROBOT_DEPENDENCY_DIR}:${PYTHONPATH}
fi

# No need for the overhead of Pabot if no parallelisation is required
if [ $ROBOT_THREADS -eq 1 ]
then
    xvfb-run \
        --server-args="-screen 0 ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_COLOUR_DEPTH} -ac" \
        robot \
        --outputDir $ROBOT_REPORTS_FINAL_DIR \
        ${ROBOT_OPTIONS} \
        $ROBOT_TESTS_DIR
else
    xvfb-run \
        --server-args="-screen 0 ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_COLOUR_DEPTH} -ac" \
        pabot \
        --verbose \
        --processes $ROBOT_THREADS \
        ${PABOT_OPTIONS} \
        --outputDir $ROBOT_REPORTS_FINAL_DIR \
        ${ROBOT_OPTIONS} \
        $ROBOT_TESTS_DIR
fi

ROBOT_EXIT_CODE=$?

if [[ ${ROBOT_EXIT_CODE} -gt 0 ]]
then
    for ((i = 0 ; i < ${ROBOT_RERUN_TIMES} ; i++ ))
    do
        xvfb-run \
            --server-args="-screen 0 ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_COLOUR_DEPTH} -ac" \
            robot \
            --rerunfailed $ROBOT_REPORTS_FINAL_DIR/output.xml \
            --output $ROBOT_REPORTS_FINAL_DIR/output_rerun.xml \
            --outputDir $ROBOT_REPORTS_FINAL_DIR \
            ${ROBOT_OPTIONS} \
            $ROBOT_TESTS_DIR

        ROBOT_EXIT_CODE=$?

        rebot --outputDir $ROBOT_REPORTS_FINAL_DIR --merge $ROBOT_REPORTS_FINAL_DIR/output_rerun.xml $ROBOT_REPORTS_FINAL_DIR/output.xml

        if [ ${ROBOT_EXIT_CODE} -eq 0 ]
        then
            break
        fi

    done
fi

if [ ${AWS_UPLOAD_TO_S3} = true ]
then
    echo "Uploading report to AWS S3..."
    aws s3 sync $ROBOT_REPORTS_FINAL_DIR/ s3://${AWS_BUCKET_NAME}/robot-reports/
    echo "Reports have been successfully uploaded to AWS S3!"
fi

exit $ROBOT_EXIT_CODE
