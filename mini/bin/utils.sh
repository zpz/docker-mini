# There are two ways to specify an image name (except for tag):
#   python
#   zppz/xyz
#
# The first one means the "official image" 'python'.
# The second one includes namespace such as 'zppz'.
# The name may be followed by ':tag', such as
#
#   zppz/xyz:20200318

set -Eeuo pipefail


function get-image-tags-local {
    # Input is image name w/o tag.
    # Returns space separated list of tags;
    # '-' if not found.
    local name="$1"
    if [[ "${name}" == *:* ]]; then
        >&2 echo "image name '${name}' already contains tag"
        return 1
    fi
    local tags=$(docker images "${name}" --format "{{.Tag}}" ) || return 1
    if [[ "${tags}" == '' ]]; then
        echo -
    else
        echo $(echo "${tags}")
    fi
}


function get-image-tags-remote {
    # Analogous `get-image-tags-local`.
    #
    # For an "official" image, the image name should be 'library/xyz'.
    # However, the API response is not complete.
    # For now, just work on 'zppz/' images only.
    local name="$1"
    if [[ "${name}" == *:* ]]; then
        >&2 echo "image name '${name}' already contains tag"
        return 1
    fi
    if [[ "${name}" != zppz/* ]]; then
        >&2 echo "image name '${name}' is not in the 'zppz' namespace; not supported at present"
        return 1
    fi
    local url=https://hub.docker.com/v2/repositories/${name}/tags
    local tags="$(curl -L -s ${url} | tr -d '{}[]"' | tr ',' '\n' | grep name)" || return 1
    if [[ "$tags" == "" ]]; then
        echo -
    else
        tags="$(echo $tags | sed 's/name: //g' | sed 's/results: //g')" || return 1
        echo "${tags}"
    fi
}


function has-image-local {
    # Input is image name with tag.
    # Returns whether this image exists locally.

    local name="$1"
    if [[ "${name}" != *:* ]]; then
        >&2 echo "input image '${name}' does not contain tag"
        return 1
    fi
    local tag=$(docker images "${name}" --format "{{.Tag}}" ) || return 1
    if [[ "${tag}" != '' ]]; then
        echo yes
    else
        echo no
    fi
}


function has-image-remote {
    local name="$1"
    if [[ "${name}" != *:* ]]; then
        >&2 echo "input image '${name}' does not contain tag"
        return 1
    fi
    if [[ "${name}" != zppz/* ]]; then
        # In this case, the function `get-image-tags-remote`
        # is not reliable, so just return 'yes'.
        echo yes
    else
        local tag="${name##*:}"
        name="${name%:*}"
        local tags=$(get-image-tags-remote "${name}") || return 1
        if [[ "${tags}" == *" ${tag} "* ]]; then
            echo yes
        else
            echo no
        fi
    fi
}


function find-latest-image-local {
    # Find Docker image of specified name with the latest tag on local machine.
    #
    # For a non-zppz image, must specify exact tag.
    # In this case, this function checks whether that image exists.
    #
    # Returns full image name with tag.
    # Returns '-' if not found

    local name="$1"
    if [[ "${name}" == zppz/* ]]; then
        if [[ "${name}" == *:* ]]; then
            local z=$(has-image-local "${name}") || return 1
            if [[ "${z}" == yes ]]; then
                echo "${name}"
            else
                echo -
            fi
        else
            local tag=$(docker images "${name}" --format "{{.Tag}}" | sort | tail -n 1) || return 1
            if [[ "${tag}" == '' ]]; then
                echo -
            else
                echo "${name}:${tag}"
            fi
        fi
    else
        if [[ "${name}" != *:* ]]; then
            >&2 echo "image '${name}' must have its exact tag specified"
            return 1
        fi

        local z=$(has-image-local "${name}") || return 1
        if [[ "${z}" == yes ]]; then
            echo "${name#library/}"
        else
            echo -
        fi
    fi
}


function find-latest-image-remote {
    local name="$1"
    if [[ "${name}" == *:* ]]; then
        local z=$(has-image-remote "${name}") || return 1
        if [[ "${z}" == yes ]]; then
            echo "${name}"
        else
            echo -
        fi
    else
        if [[ "${name}" != zppz/* ]]; then
            >&2 echo "image '${name}' must have its exact tag specified"
            return 1
        fi
        local tags="$(get-image-tags-remote ${name})" || return 1
        if [[ "${tags}" != '-' ]]; then
            local tag=$(echo "${tags}" | tr ' ' '\n' | sort -r | head -n 1) || return 1
            echo "${name}:${tag}"
        else
            echo -
        fi
    fi
}


function find-latest-image {
    local name="$1"
    local localimg=$(find-latest-image-local "${name}") || return 1
    local remoteimg=$(find-latest-image-remote "${name}") || return 1
    if [[ "${localimg}" == - ]]; then
        echo "${remoteimg}"
    elif [[ "${remoteimg}" == - ]]; then
        echo "${localimg}"
    elif [[ "${localimg}" < "${remoteimg}" ]]; then
        echo "${remoteimg}"
    else
        echo "${localimg}"
    fi
}


function find-image-id-local {
    # Input is a full image name including namespace and tag.
    local name="$1"
    docker images "${name}" --format "{{.ID}}"
}


function find-image-id-remote {
    # Input is a full image name including namespace and tag.
    local name="$1"
    local tag="${name##*:}"
    >&2 echo "getting manifest of remote image ${name}"
    curl -v --silent -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' ${name}/manifest/${tag} 2>&1 \
        | awk '/config/,/}/' | grep digest | grep -o 'sha256:[0-9a-z]*'
}


function get-image-layers-local {
    local name="$1"
    if [[ ${name} != *:* ]]; then
        >&2 echo "input image '${name}' does not contain tag"
        return 1
    fi
    >&2 echo "getting manifest of local image '${name}'"
    DOCKER_CLI_EXPERIMENTAL=enabled docker manifest inspect ${name} \
        | awk '/layers/,/]/' | grep digest | grep -o 'sha256:[0-9a-z]*' | tr '\n' ' '
}


function get-image-layers-remote {
    local name="$1"
    if [[ ${name} != *:* ]]; then
        >&2 echo "input image '${name}' does not contain tag"
        return 1
    fi
    local tag="${name##*:}"
    curl --silent -H 'Accept application/vnd.docker.distribution.manifest.v2+json' ${name}/manifests/${tag} 2>&1 \
        | awk '/layers/,/]/' | grep digest | grep -o 'sha256:[0-9a-z]*' | tr '\n' ' '
}


function build-image {
    local BUILDDIR="$1"
    local NAME="$2"
    local parent="$3"

    local PARENT=$(find-latest-image ${parent}) || return 1
    if [[ "${PARENT}" == - ]]; then
        >&2 echo "Unable to find parent image '${parent}'"
        return 1
    fi

    local old_img=$(find-latest-image ${NAME}) || return 1
    if [[ "${old_img}" != - ]] && [[ $(has-image-local "${old_img}") == no ]]; then
        echo
        docker pull ${old_img} || return 1
    fi

    local VERSION="$(date -u +%Y%m%dT%H%M%SZ)"
    # UTC datetime. This works the same on Mac and Linux.
    # Version format is like this:
    #    20180913T081243Z
    local FULLNAME="${NAME}:${VERSION}"

    echo
    echo
    echo "=== build image ${FULLNAME}"
    echo "       based on ${PARENT} ==="
    echo "=== $(date) ==="
    echo

    cp -f ${BUILDDIR}/Dockerfile ${BUILDDIR}/_Dockerfile
    echo >> ${BUILDDIR}/_Dockerfile
    echo "ENV IMAGE_PARENT=${PARENT}" >> ${BUILDDIR}/_Dockerfile
    docker build --build-arg PARENT="${PARENT}" -t "${FULLNAME}" "${BUILDDIR}" -f ${BUILDDIR}/_Dockerfile >&2 || return 1
    rm -r ${BUILDDIR}/_Dockerfile

    local new_img="${FULLNAME}"
    if [[ "${old_img}" != - ]]; then
        local old_id=$(find-image-id-local "${old_img}") || return 1
        local new_id=$(find-image-id-local "${new_img}") || return 1
        echo
        echo "old_img: ${old_img}"
        echo "new_img: ${new_img}"
        echo "old_id: ${old_id}"
        echo "new_id: ${new_id}"
        if [[ "${old_id}" == "${new_id}" ]]; then
            echo
            echo "Newly built image is identical to an older build; discarding the new tag..."
            docker rmi "${new_img}"
        else
            echo "Deleting the old image..."
            docker rmi "${old_img}"
        fi
    fi
}


function pull-latest-image {
    local imagename="$1"

    if [[ "${imagename}" == *:* ]]; then
        if [[ $(has-image-local ${imagename}) == no ]]; then
            docker pull ${imagename}
        fi
        return 0
    fi

    local image_remote=$(find-latest-image-remote ${imagename}) || exit 1
    if [[ "${image_remote}" == - ]]; then
        return 0
    fi

    local image_local=$(find-latest-image-local ${imagename}) || exit 1
    if [[ ${image_local} == - ]]; then
        docker pull ${imagename}
    fi

    if [[ "${image_remote}" < "${image_local}" || "${image_remote}" == "${image_local}" ]]; then
        return 0
    fi
    
    local id_local=$(get-image-layers-local ${image_local})
    local id_remote=$(get-image-layers-remote ${image_remote})
    if [[ "${id_local}" == "${id_remote}" ]]; then
        echo "Local image ${image_local} is identical to remote image ${image_remote}; adding remote tag to local image"
        docker tag ${image_local} ${image_remote}
        return 0
    fi

    local imgids_local=$(docker images -aq ${imagename})
    docker pull ${image_remote}
    echo
    echo "Deleting the older images:"
    echo "${imgids_local}"
    docker rmi ${imgids_local} || true
}


function push-image {
    local name="$1"

    local img_remote=$(find-latest-image-remote ${name}) || return 1
    local img_local=$(find-latest-image-local ${name}) || return 1
    if [[ "${img_remote}" != - ]]; then
        local id_remote=$(get-image-layers-remote ${img_remote}) || return 1
        local id_local=$(get-image-layers-local ${img_local}) || return 1

        echo
        echo "remote image: ${img_remote}"
        echo "remote id: ${id_remote}"
        echo "local image: ${img_local}"
        echo "local id: ${id_local}"
        echo

        if [[ "${id_remote}" == "${id_local}" ]]; then
            echo "local version and remote version are identical; no need to push"
            return 0
        fi
    fi

    echo
    echo "pushing ${img_local} to dockerhub"
    docker push ${img_local}

    # docker login --username ${DOCKERHUBUSERNAME} --password ${DOCKERHUBPASSWORD} || return 1

    local id_remote_new=$(get-image-layers-remote ${img_local}) || return 1
    echo
    echo "new remote image: ${img_local}"
    echo "new remote id: ${id_remote_new}"
}
