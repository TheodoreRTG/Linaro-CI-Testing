#!/bin/bash -ex

echo "For Test purpose check 1: LKFT_WORK_DIR=${LKFT_WORK_DIR}"
export LKFT_WORK_DIR=/home/buildslave/srv/${BUILD_DIR}/workspace
echo "For Test purpose check 2: LKFT_WORK_DIR=${LKFT_WORK_DIR}"
cd ${LKFT_WORK_DIR}

F_ABS_PATH=$(readlink -e $0)
OPT_DRY_RUN=""
if [ -n "${ENV_DRY_RUN}" ]; then
    OPT_DRY_RUN="--dry-run"
fi

function exit_with_msg(){
    echo "$@"
    exit
}

function check_environments(){
    # environments must be defined in build config
    # following environments no need to be exported as they only used for here.
    [ -z "${TEST_DEVICE_TYPE}" ] && exit_with_msg "TEST_DEVICE_TYPE is required to be defined."
    [ -z "${TEST_LAVA_SERVER}" ] && exit_with_msg "TEST_LAVA_SERVER is required to be defined."
    [ -z "${TEST_QA_SERVER}" ] && exit_with_msg "TEST_QA_SERVER is required to be defined."
    [ -z "${TEST_QA_SERVER_PROJECT}" ] && exit_with_msg "TEST_QA_SERVER_PROJECT is required to be defined."

    # following environments must be exported as they will be used in the job templates.
    [ -z "${ANDROID_VERSION}" ] && exit_with_msg "ANDROID_VERSION is required to be defined."
    [ -z "${KERNEL_BRANCH}" ] && exit_with_msg "KERNEL_BRANCH is required to be defined."
    [ -z "${KERNEL_REPO}" ] && exit_with_msg "KERNEL_REPO is required to be defined."
    [ -z "${TEST_METADATA_TOOLCHAIN}" ] && exit_with_msg "TEST_METADATA_TOOLCHAIN is required to be defined."
    [ -z "${TEST_VTS_URL}" ] && exit_with_msg "TEST_VTS_URL is required to be defined."
    [ -z "${TEST_CTS_URL}" ] && exit_with_msg "TEST_CTS_URL is required to be defined."
    [ -z "${REFERENCE_BUILD_URL}" ] && exit_with_msg "REFERENCE_BUILD_URL is required to be defined."

    [ -z "${PUBLISH_FILES}" ] && exit_with_msg "PUBLISH_FILES is required to be defined."

    return 0
}

function get_value_from_config_file(){
    local key=$1 && shift
    local f_config=$1 && shift

    local key_line=$(grep "${key}=" "${f_config}"|tail -n1|tr -d '"')
    if [ -z "key_line" ]; then
        return
    fi
    local value=$(echo "${key_line}"|cut -d= -f2-)
    if [ -z "${value}" ]; then
        return
    else
        echo "${value}"
    fi
}

function submit_jobs_for_config(){
    local build_config=$1 && shift
    # clean environments
    unset TEST_DEVICE_TYPE TEST_LAVA_SERVER TEST_QA_SERVER TEST_QA_SERVER_TEAM TEST_QA_SERVER_PROJECT TEST_QA_SERVER_ENVIRONMENT
    unset ANDROID_VERSION KERNEL_BRANCH KERNEL_REPO TEST_METADATA_TOOLCHAIN TEST_VTS_URL TEST_CTS_URL REFERENCE_BUILD_URL
    unset PUBLISH_FILES TEST_OTHER_PLANS

    config_url="https://android-git.linaro.org/android-build-configs.git/plain/lkft/${build_config}?h=lkft"
    wget ${config_url} -O ${build_config}
    source ${build_config}

    check_environments
    export ANDROID_VERSION KERNEL_BRANCH KERNEL_REPO TEST_METADATA_TOOLCHAIN TEST_VTS_URL TEST_CTS_URL REFERENCE_BUILD_URL
    export TEST_VTS_VERSION=$(echo ${TEST_VTS_URL} | awk -F"/" '{print$(NF-1)}')
    export TEST_CTS_VERSION=$(echo ${TEST_CTS_URL} | awk -F"/" '{print$(NF-1)}')

    ## clean up the old changes for last build
    ## so that the url could be updated as expected
    cd  ${DIR_CONFIGS_ROOT}/ && \
        git reset --hard && \
        cd -

    for f in ${PUBLISH_FILES}; do
        # DOWNLOAD_URL is where the generated files stored
        # replace REFERENCE_BUILD_URL with DOWNLOAD_URL
        sed -i "s|{{REFERENCE_BUILD_URL}}/${f}|{{DOWNLOAD_URL}}/$f|" ${DIR_CONFIGS_ROOT}/lkft/lava-job-definitions/common/devices/${TEST_DEVICE_TYPE}
        # replace file name in job template with new file name generated
        sed -i "s|{{DOWNLOAD_URL}}/${f}|{{DOWNLOAD_URL}}/${build_config}-$f|" ${DIR_CONFIGS_ROOT}/lkft/lava-job-definitions/common/devices/${TEST_DEVICE_TYPE}
    done

    # special case for android 8.1 version, which does not support vendor partition yet
    if ! echo "${PUBLISH_FILES}" | grep vendor; then
        # only need to check for the case that when no vendor.img generated
        # and not vendor.img with the REFERENCE_BUILD
        if curl --output /dev/null --silent --head --fail "${REFERENCE_BUILD_URL}/vendor.img.xz"; then
            echo "This reference build comes with a vendor partition"
        else
            echo "No vendor partition for the reference build, so flashing cache partition from the job instead"
            sed -i "s|vendor.img.xz|cache.img.xz|g" ${DIR_CONFIGS_ROOT}/lkft/lava-job-definitions/common/devices/${TEST_DEVICE_TYPE}
        fi
    fi

    # set OPT_ENVIRONMENT to empty by default, to make openembedded-lkft/submit_for_testing.py
    # use the device type as the qa-report server environment
    # and use the value of TEST_QA_SERVER_ENVIRONMENT as the qa-report server environment
    # if it is sepecified explicitly
    OPT_ENVIRONMENT=""
    if [ -n "${TEST_QA_SERVER_ENVIRONMENT}" ] && echo "X${TEST_QA_SERVER_ENVIRONMENT_ENABLED}" | grep -i "Xtrue"; then
        OPT_ENVIRONMENT="--environment ${TEST_QA_SERVER_ENVIRONMENT}"
    fi
    if [ -z "${TEST_QA_SERVER_TEAM}" ]; then
        TEST_QA_SERVER_TEAM="android-lkft"
    fi
    python ${DIR_CONFIGS_ROOT}/openembedded-lkft/submit_for_testing.py \
        --device-type ${TEST_DEVICE_TYPE} \
        --build-number ${BUILD_NUMBER} \
        --lava-server ${TEST_LAVA_SERVER} \
        --qa-server ${TEST_QA_SERVER} \
        --qa-server-team ${TEST_QA_SERVER_TEAM} \
        ${OPT_ENVIRONMENT} \
        --qa-server-project ${TEST_QA_SERVER_PROJECT} \
        --git-commit ${QA_BUILD_VERSION} \
        --testplan-path ${DIR_CONFIGS_ROOT}/lkft/lava-job-definitions/common \
        --test-plan template-boot.yaml template-vts-kernel.yaml template-cts.yaml \
        ${OPT_DRY_RUN} \
        --quiet

    curl --header "Auth-Token: ${QA_REPORTS_TOKEN}" --form tests='{"build_process/build": "pass"}'  ${TEST_QA_SERVER}/api/submit/${TEST_QA_SERVER_TEAM}/${TEST_QA_SERVER_PROJECT}/${QA_BUILD_VERSION}/${TEST_DEVICE_TYPE}

    if [ -n "${TEST_OTHER_PLANS}" ]; then
        for plan in ${TEST_OTHER_PLANS}; do
            templates=$(get_value_from_config_file "TEST_TEMPLATES_${plan}" "${build_config}")
            if [ -z "${templates}" ]; then
                echo "No templates specified for plan ${plan} with variable of TEST_TEMPLATES_${plan}"
                continue
            fi

            lava_server=$(get_value_from_config_file "TEST_LAVA_SERVER_${plan}" "${build_config}")
            if [ -z "${lava_server}" ]; then
                lava_server="${TEST_LAVA_SERVER}"
            fi
            qa_server=$(get_value_from_config_file "TEST_QA_SERVER_${plan}" "${build_config}")
            if [ -z "${qa_server}" ]; then
                qa_server="${TEST_QA_SERVER}"
            fi
            qa_server_team=$(get_value_from_config_file "TEST_QA_SERVER_TEAM_${plan}" "${build_config}")
            if [ -z "${qa_server_team}" ]; then
                qa_server_team="${TEST_QA_SERVER_TEAM}"
            fi
            qa_server_project=$(get_value_from_config_file "TEST_QA_SERVER_PROJECT_${plan}" "${build_config}")
            if [ -z "${qa_server_project}" ]; then
                qa_server_project="${TEST_QA_SERVER_PROJECT}"
            fi

            python ${DIR_CONFIGS_ROOT}/openembedded-lkft/submit_for_testing.py \
                --device-type ${TEST_DEVICE_TYPE} \
                --build-number ${BUILD_NUMBER} \
                --lava-server ${lava_server} \
                --qa-server ${qa_server} \
                --qa-server-team ${qa_server_team} \
                ${OPT_ENVIRONMENT} \
                --qa-server-project ${qa_server_project} \
                --git-commit ${QA_BUILD_VERSION} \
                --testplan-path ${DIR_CONFIGS_ROOT}/lkft/lava-job-definitions/common \
                --test-plan ${templates} \
                ${OPT_DRY_RUN} \
                --quiet
        done
    fi
}

function submit_jobs(){
    local f_temp_path=${F_ABS_PATH}
    local NEED_CLONE_CONFIGS=true
    DIR_CONFIGS_ROOT=""
    while true; do
        parent=$(dirname ${f_temp_path})
        if [ -d ${parent}/.git ]; then
            NEED_CLONE_CONFIGS=false
            DIR_CONFIGS_ROOT=${parent}
            break
        elif [ "X${parent}" = "X/" ]; then
            break
        fi
        f_temp_path=${parent}
    done

    if ${NEED_CLONE_CONFIGS}; then
        rm -rf configs && git clone --depth 1 http://git.linaro.org/ci/job/configs.git && DIR_CONFIGS_ROOT=configs
    fi

    #environments exported by jenkins
    #export BUILD_NUMBER JOB_NAME BUILD_URL

    PUB_DEST=android/lkft/${JOB_NAME}/${BUILD_NUMBER}/
    export DOWNLOAD_URL=http://snapshots.linaro.org/${PUB_DEST}

    # environments set by the upstream trigger job
    KERNEL_COMMIT=${SRCREV_kernel}
    if [ -n "${MAKE_KERNELVERSION}" ] && echo "X${USE_KERNELVERSION_FOR_QA_BUILD_VERSION}" | grep -i "Xtrue"; then
        QA_BUILD_VERSION=${MAKE_KERNELVERSION}-${KERNEL_COMMIT:0:12}
    elif [ ! -z "${KERNEL_DESCRIBE}" ]; then
        QA_BUILD_VERSION=${KERNEL_DESCRIBE}
    else
        QA_BUILD_VERSION=${KERNEL_COMMIT:0:12}
    fi
    export KERNEL_DESCRIBE KERNEL_COMMIT
    export QA_BUILD_VERSION DIR_CONFIGS_ROOT

    for build_config in ${ANDROID_BUILD_CONFIG}; do
        submit_jobs_for_config ${build_config}
    done
}

submit_jobs "$@"
