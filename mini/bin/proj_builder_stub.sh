thisdir="$( pwd )"

REPO=$(basename "${thisdir}")

PUSH=no
if [ -z ${TRAVIS_BRANCH+x} ]; then
    if [ -d "${thisdir}/.git" ]; then
        BRANCH=$(cat "${thisdir}/.git/HEAD")
        BRANCH="${BRANCH##*/}"
    else
        BRANCH=branch
    fi
else
    # `TRAVIS_BRANCH` is defined; this is happening on Github.
    BRANCH=${TRAVIS_BRANCH}
    if [[ "${BRANCH}" == release ]] || [[ "${BRANCH}" == master ]]; then
        PUSH=yes
    fi
fi


NAMESPACE=$(cat "${thisdir}/docker/namespace") || exit 

function build-dev {
    local name="${NAMESPACE}/${REPO}"
    local builddir="${thisdir}/docker"
    local parent=$(cat "${thisdir}/docker/parent") || return 1
    build-image ${builddir} ${name} ${parent}
}


function build-branch {
    local build_dir="/tmp/${REPO}"
    rm -rf ${build_dir}
    mkdir -p ${build_dir}
    cp -rf "${thisdir}" "${build_dir}/src"

    cat > "${build_dir}/Dockerfile" << EOF
ARG PARENT
FROM \${PARENT}
USER root

RUN mkdir -p /tmp/build
COPY src/ /tmp/build

RUN cd /tmp/build \\
    && ( if [ -f setup_py ]; then pip-install . ; fi) \\
    && rm -rf /opt/${REPO} && mkdir -p /opt/${REPO} \\
    && ( if [ -d bin ]; then mv -f bin "/opt/${REPO}/"; fi ) \\
    && ( if [ -d tests ]; then mv -f tests "/opt/${REPO}/"; fi ) \\
    && ( if [ -d test ]; then mv -f test "/opt/${REPO}/"; fi ) \\
    && ( if [ -d sysbin ]; then mv -f sysbin/* "/usr/local/bin/"; fi ) \\
    && cd / \\
    && rm -rf /tmp/build
EOF

    local name="${NAMESPACE}/${REPO}-${BRANCH}"
    local parent="${NAMESPACE}/${REPO}"

    build-image "${build_dir}" ${name} ${parent} || return 1
    rm -rf "${build_dir}"
}


if [[ "${BRANCH}" == release ]]; then
    old_branch_img=$(find-latest-image zppz/${REPO}-${BRANCH})
    build-branch || exit 1
    new_branch_img=$(find-latest-image zppz/${REPO}-${BRANCH})
    if [[ "${new_branch_img}" == "${old_branch_img}" ]]; then
        new_branch_img=-
    fi

    if [[ "${new_branch_img}" != - ]] && [[ "${PUSH}" == yes ]]; then
        echo
        echo
        echo "=== pushing image to dockerhub ==="
        docker login --username ${DOCKERHUBUSERNAME} --password ${DOCKERHUBPASSWORD}
        echo
        echo "Pushing '${new_branch_img}'"
        docker push "${new_branch_img}"
    fi

else
    old_dev_img=$(find-latest-image zppz/${REPO})
    build-dev || exit 1
    new_dev_img=$(find-latest-image-local zppz/${REPO})
    if [[ "${new_dev_img}" == "${old_dev_img}" ]]; then
        new_dev_img=-
    fi

    old_branch_img=$(find-latest-image zppz/${REPO}-${BRANCH})
    build-branch || exit 1
    new_branch_img=$(find-latest-image zppz/${REPO}-${BRANCH})
    if [[ "${new_branch_img}" == "${old_branch_img}" ]]; then
        new_branch_img=-
    fi

    if [[ "${new_dev_img}" != - ]] || [[ "${new_branch_img}" != - ]] && [[ "${PUSH}" == yes ]]; then
        echo
        echo
        echo "=== pushing images to dockerhub ==="
        docker login --username ${DOCKERHUBUSERNAME} --password ${DOCKERHUBPASSWORD}
        echo
        if [[ "${new_dev_img}" != - ]]; then
            echo "pushing '${new_dev_img}'..."
            docker push "${new_dev_img}"
        fi
        if [[ "${new_branch_img}" != - ]]; then
            echo "pushing '${new_branch_img}'..."
            docker push "${new_branch_img}"
        fi
    fi
fi
