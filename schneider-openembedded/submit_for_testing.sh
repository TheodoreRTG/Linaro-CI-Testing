#!/bin/bash

rm -rf configs
git clone --depth 1 http://git.linaro.org/ci/job/configs.git
pushd configs
git log -1
popd

# Used by DB410C's template:
export RESIZE_ROOTFS=${RESIZE_ROOTFS:-}

templates_common_minimal=( dip-image.yaml     )
templates_common_normal=(  ${templates_common_minimal[@]} dip-image-dev.yaml )
templates_common_full=(    ${templates_common_normal[@]}  ltp-ptest.yaml     )

templates_soca9_minimal=
templates_soca9_normal=( ${templates_soca9_minimal[@]})
templates_soca9_full=(   ${templates_soca9_normal[@]} )

templates_rzn1d_minimal=
templates_rzn1d_normal=( ${templates_rzn1d_minimal[@]} dip-image-edge.yaml )
templates_rzn1d_full=(   ${templates_rzn1d_normal[@]} )

if [ "${DEVICE_TYPE}" == "rzn1d" ]; then
	templates_minimal=( ${templates_common_minimal[@]} ${templates_rzn1d_minimal[@]} )
	templates_normal=(  ${templates_common_normal[@]}  ${templates_rzn1d_normal[@]} )
	templates_full=(    ${templates_common_full[@]}    ${templates_rzn1d_full[@]} )
else
	templates_minimal=( ${templates_common_minimal[@]} ${templates_soca9_minimal[@]} )
	templates_normal=(  ${templates_common_normal[@]}  ${templates_soca9_normal[@]} )
	templates_full=(    ${templates_common_full[@]}    ${templates_soca9_full[@]} )
fi

case $TEST_LEVEL in
	"minimal" | "minimum" | "min" | "3")
		templates=( ${templates_minimal[@]} )
		;;
	"normal" | "2")
		templates=( ${templates_normal[@]} )
		;;
	*)
		templates=( ${templates_full[@]} )
		;;
esac

for template in ${templates[@]};
do
	python configs/openembedded-lkft/submit_for_testing.py \
	  --device-type ${DEVICE_TYPE} \
	  --build-number ${BUILD_NUMBER} \
	  --lava-server ${LAVA_SERVER} \
	  --qa-server ${QA_SERVER} \
	  --qa-server-team ${QA_SERVER_TEAM} \
	  --qa-server-project ${QA_SERVER_PROJECT} \
	  --git-commit ${MANIFEST_COMMIT} \
	  --template-path configs/schneider-openembedded/lava-job-definitions/ \
	  --template-names ${template}
done
