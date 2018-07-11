#!/bin/bash

set -ex

rm -rf configs
git clone --depth 1 http://git.linaro.org/ci/job/configs.git

# Install jinja2-cli and ruamel.yaml, required by submit_for_testing.py
pip install --user --force-reinstall jinja2-cli ruamel.yaml

export BOOT_URL=${PUBLISH_SERVER}${PUB_DEST}/${BOOT_FILE}
export BOOT_URL_COMP=
export LXC_BOOT_FILE=$(basename ${BOOT_URL})

case "${MACHINE}" in
  dragonboard410c|dragonboard820c|sdm845_mtp)
    if [ ${MACHINE} = "dragonboard410c" ]; then
      export LAVA_DEVICE_TYPE="dragonboard-410c"
      export INSTALL_FASTBOOT=True
    elif [ ${MACHINE} = "dragonboard820c" ]; then
      export LAVA_DEVICE_TYPE="dragonboard-820c"
      export INSTALL_FASTBOOT=True
    elif [ ${MACHINE} = "sdm845_mtp" ]; then
      export LAVA_DEVICE_TYPE="sdm845-mtp"
      export INSTALL_FASTBOOT=
      export LAVA_SERVER="${LKFT_STAGING_LAVA_SERVER}"
    fi

    python configs/openembedded-lkft/submit_for_testing.py \
        --device-type ${LAVA_DEVICE_TYPE} \
        --build-number ${BUILD_NUMBER} \
        --lava-server ${LAVA_SERVER} \
        --qa-server ${QA_SERVER} \
        --qa-server-team qcomlt \
        --qa-server-project linux-integration \
        --git-commit ${BUILD_NUMBER} \
        --template-path configs/lt-qcom-linux-integration/lava-job-definitions \
        --template-names template-bootrr.yaml
    ;;
  *)
    echo "Skip LAVA_DEVICE_TYPE for ${MACHINE}"
    ;;
esac
