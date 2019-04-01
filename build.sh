set -Eeuo pipefail

thisfile="${BASH_SOURCE[0]}"
thisdir="$( cd $( dirname ${thisfile} ) && pwd )"

source "${thisdir}/mini/bin/utils.sh"

NAMESPACE=zppz


function main {
    local new_images=''
    local img
    local IMG
    local old_img
    local new_img
    local parent
    local builddir

    for img in "${IMAGES[@]}"; do
        IMG="${NAMESPACE}/${img}"
        old_img=$(find-latest-image ${IMG}) || return 1

        builddir="${thisdir}/${img}"
        parent=$(cat "${builddir}/parent")

        build-image $builddir ${IMG} ${parent} || return 1

        new_img=$(find-latest-image-local ${IMG}) || return 1
        if [[ "${new_img}" != "${old_img}" ]]; then
            new_images="${new_images} ${new_img}"
        fi
    done

    echo
    echo "Finished building new images: ${new_images[@]}"
    echo

    if [[ "${PUSH}" == yes ]] && [[ "${new_images}" != '' ]]; then
        echo
        echo
        echo '=== pushing images to Dockerhub ==='
        docker login --username ${DOCKERHUBUSERNAME} --password ${DOCKERHUBPASSWORD} || return 1
        echo
        new_images=( ${new_images} )
        for img in "${new_images[@]}"; do
            echo
            echo "pushing ${img}"
            docker push "${img}" || return 1
        done
    fi
}


if [[ $# > 0 ]]; then
    IMAGES=( $@ )
else
    IMAGES=( mini )
fi
echo "IMAGES: ${IMAGES[@]}"

# The images are pushed to Dockerhub only when built at github
# by the integrated Travis-CI in branch `master`.

if [ -z ${TRAVIS_BRANCH+x} ]; then
    BRANCH=''
else
    BRANCH=${TRAVIS_BRANCH}
fi

if [[ ${BRANCH} == master ]]; then
    PUSH=yes
else
    PUSH=no
fi
echo "PUSH: ${PUSH}"

main
