# There are two ways to specify an image name (except for tag):
#   python
#   somerepo/xyz
#
# The first one means the "official image" 'python'.
# The second one includes namespace such as 'zppz'.

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
    # Input is a full image name including tag.
    local name="$1"
    docker images "${name}" --format "{{.ID}}"
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

    docker build --build-arg PARENT="${PARENT}" -t "${FULLNAME}" "${BUILDDIR}" >&2 || return 1

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