thisdir="$( pwd )"


function build-dev {
    local name="${NAMESPACE}/${REPO}"
    local builddir="${thisdir}/docker"
    local parent=$(cat "${builddir}/parent") || return 1
    build-image ${builddir} ${name} ${parent} || return 1
    if [[ ${PUSH} == yes ]]; then
        push-image ${name}
    fi
}


function build-branch {
    local build_dir="/tmp/${REPO}"
    rm -rf ${build_dir}
    mkdir -p ${build_dir}
    [ -d ${thisdir}/src ] && cp -R ${thisdir}/src ${build_dir}/src/src
    [ -d ${thisdir}/bin ] && cp -R ${thisdir}/src ${build_dir}/src/bin
    [ -d ${thisdir}/sysbin ] && cp -R ${thisdir}/src ${build_dir}/src/sysbin
    [ -d ${thisdir}/tests ] && cp -R ${thisdir}/src ${build_dir}/src/tests
    [ -d ${thisdir}/setup.py ] && cp -R ${thisdir}/src ${build_dir}/src/
    [ -d ${thisdir}/setup.cfg ] && cp -R ${thisdir}/src ${build_dir}/src/
    [ -d ${thisdir}/MANIFEST.in ] && cp -R ${thisdir}/src ${build_dir}/src/
    [ -d ${thisdir}/install.sh ] && cp -R ${thisdir}/src ${build_dir}/src/

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
    && ( if [ -d sysbin ]; then mkdir -p /opt/bin && mv -f sysbin/* "/opt/bin/"; fi ) \\
    && cd / \\
    && rm -rf /tmp/build
EOF

    local name="${NAMESPACE}/${REPO}-${BRANCH}"

    # A project image's branched version is built on top of its
    # 'dev' version. The only addition to the parent image is to
    # install the repo's code (typically a Python package) in
    # the image.
    local parent="${NAMESPACE}/${REPO}"

    build-image "${build_dir}" ${name} ${parent} || return 1
    rm -rf "${build_dir}"

    if [[ "${PUSH}" == yes ]];
        push-image ${name}
    fi
}


REPO=$(basename "${thisdir}")
NAMESPACE=$(cat "${thisdir}/docker/namespace") || exit 


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
    PUSH=yes
fi


start_time=$(date)

echo "start building dev image"
echo
build-dev || exit 1
echo

echo "start building branch image"
echo
build-branch || exit 1

end_time=$(date)
echo
echo "Started at ${start_time}"
echo "Finished at ${end_time}"
