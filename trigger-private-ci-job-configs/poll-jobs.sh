#!/bin/bash

set -ex

echo ""
echo "########################################################################"
echo "    Gerrit Environment"
env |grep '^GERRIT'
echo "########################################################################"

git config --global user.name "Linaro CI"
git config --global user.email "ci_notify@linaro.org"

# Add SSH server signatures to known_hosts list.
bash -c "ssh-keyscan dev-private-git.linaro.org >  ${HOME}/.ssh/known_hosts"
bash -c "ssh-keyscan dev-private-review.linaro.org >>  ${HOME}/.ssh/known_hosts"
bash -c "ssh-keyscan  -t rsa -p 29418 dev-private-review.linaro.org >> \
	${HOME}/.ssh/known_hosts"

rm -rf ${WORKSPACE}/*

git clone -b ${GERRIT_BRANCH} --depth 2 ssh://git@dev-private-review.linaro.org/${GERRIT_PROJECT}
cd *
git fetch ssh://git@dev-private-review.linaro.org/${GERRIT_PROJECT} ${GERRIT_REFSPEC}
git checkout -q FETCH_HEAD

export GIT_PREVIOUS_COMMIT=$(git rev-parse HEAD~1)
export GIT_COMMIT=${GERRIT_PATCHSET_REVISION}
jenkins-jobs --version
wget -q https://git.linaro.org/ci/job/configs.git/plain/run-jjb.py -O run-jjb.py
python run-jjb.py
