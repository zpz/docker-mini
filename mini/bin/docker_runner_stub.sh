#set -o errexit
set -o nounset
set -o pipefail

# For all the directory and file names touched by this script,
# space in the name is not supported.
# Do not use space in directory and file names in ${HOME}/work and under it.


USAGE=$(cat <<'EOF'
Usage:
   run-docker [options] image-name[:tag] [command [...] ]
where 

`image-name` is like 'zppz/py3', etc.

`command` is command to be run within the container, followed by arguments to the command.
(Default: /bin/bash)

If image tag is not specified, the most up-to-date tag is used.
EOF
)


if [[ $# < 1 ]]; then
    echo "${USAGE}"
    exit 1
fi


imagename=""
command=/bin/bash
args=""
opts=""
with_pythonpath=yes
daemon_mode=no
as_root=no
pull=no
nb_port=8888
memory_limit=12g
shm_size=4g
get_version=no


# Parse arguments.
# Before the argument for image name,
# some arguments are consumed by this script;
# the rest are stored to be passed on to the command.
# After the argument for image name,
# the first is the command to be executed in the container,
# others are arguments to the command.
while [[ $# > 0 ]]; do
    if [[ "${imagename}" == "" ]]; then
        if [[ "$1" == -v ]]; then
            shift
            opts="${opts} -v $1"
        elif [[ "$1" == -p ]]; then
            shift
            opts="${opts} -p $1"
        elif [[ "$1" == --network ]]; then
            shift
            opts="${opts} --network $1"
        elif [[ "$1" == -e ]]; then
            shift
            opts="${opts} -e $1"
        elif [[ "$1" == --memory=* ]]; then
            memory_limit="$1"
            memory_limit="${memory_limit#*=}"
        elif [[ "$1" == --memory ]]; then
            shift
            memory_limit="$1"
        elif [[ "$1" == --shm-size=* ]]; then
            shm_size="$1"
            shm_size="${shm_size#*=}"
        elif [[ "$1" == --shm-size ]]; then
            shift
            shm_size="$1"
        elif [[ "$1" == --nb_port ]]; then
            shift
            nb_port="$1"
        elif [[ "$1" == --nb_port=* ]]; then
            nb_port="$1"
            nb_port="${nb_port#*=}"
        elif [[ "$1" == "--no-pythonpath" ]]; then
            with_pythonpath=no
        elif [[ "$1" == "--root" ]]; then
            as_root=yes
        elif [[ "$1" == "--pull" ]]; then
            pull=yes
        elif [[ "$1" == --version ]]; then
            get_version=yes
        elif [[ "$1" == -* ]]; then
            opts="${opts} $1"
            if [[ "$1" == "-d" ]] || [[ "$1" == "--detach" ]]; then
                daemon_mode=yes
            fi
        else
            imagename="$1"
        fi
        shift
    else
        # After `image-name`.
        command="$1"
        shift
        args="$@"
        break
    fi
done


if [[ "${imagename}" == "" ]]; then
    echo "${USAGE}"
    exit 1
fi


function find-latest-image-local {
    local name="$1"
    if [[ "${name}" == zppz/* ]]; then
        if [[ "${name}" == *:* ]]; then
            local z=$(has-image-local "${name}") || return 1
            if [[ $z == yes ]]; then
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
        if [[ $z == yes ]]; then
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
        if [[ $z == yes ]]; then
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


hostworkdir="${HOME}/work"


if [[ "${imagename}" == zppz/* ]]; then
    is_ext_image=no
else
    is_ext_image=yes
fi
imagename_base="${imagename##*/}"

is_dev_image=no
if [[ " dl jekyll mini py3r latex ml py3 " == *" ${imagename_base} "* ]]; then
    is_base_image=yes
else
    is_base_image=no
    if [[ "${is_ext_image}" == no ]]; then
        if [[ "${imagename_base}" != *-* ]]; then
            if [ -d "${hostworkdir}/src/${imagename_base}/src" ]; then
                is_dev_image=yes
            fi
        fi
    fi
fi


if [[ "${imagename}" == *:* ]]; then
    if [[ "${pull}" == no ]]; then
        z=$(has-image-local ${imagename}) || exit 1
        if [[ ${z} == no ]]; then
            >&2 echo "Unable to find image '${imagename}' locally; consider using '--pull'"
            exit 1
        fi
    fi
    imageversion=${imagename##*:}
    imagename=${imagename%:*}
    if [[ "${imagename}" != zppz/* ]]; then
        is_ext_image=yes
    fi
else
    if [[ "${imagename}" != zppz/* ]]; then
        >&2 echo "For the external image '${imagename}', exact tag must be specified"
        exit 1
    fi
    if [[ "${pull}" == yes ]]; then
        imagefullname_lo=$(find-latest-image-local ${imagename}) || exit 1
        imagefullname_re=$(find-latest-image-remote ${imagename}) || exit 1
        if [[ "${imagefullname_lo}" == - ]]; then
            if [[ "${imagefullname_re}" == - ]]; then
                >&2 echo "Unable to find image ${imagename}"
                exit 1
            else
                imagefullname=${imagefullname_re}
                docker pull "${imagefullname}"
            fi
        elif [[ "${imagefullname_re}" == - ]]; then
            if [[ "${imagefullname_lo}" == - ]]; then
                >&2 echo "Unable to find image ${imagename}"
                exit 1
            else
                imagefullname=${imagefullname_lo}
            fi
        elif [[ "${imagefullname_lo}" < "${imagefullname_re}" ]]; then
            docker pull "${imagefullname_re}"
            docker rmi "${imagefullname_lo}"
        else
            imagefulename="${imagefullname_lo}"
        fi
    else
        imagefullname=$(find-latest-image-local ${imagename}) || exit 1
        if [[ "${imagefullname}" == - ]]; then
            >&2 echo "Unable to find image '${imagename}' locally; consider using '--pull'"
            exit 1
        fi
    fi
    imageversion=${imagefullname##*:}
fi


if [[ "${as_root}" == yes ]] || [[ "${is_ext_image}" == yes ]] || [[ "${imagename}" == zppz/mini ]] || [[ "$(id -un)" == root ]]; then
    dockerhomedir=/root
    opts="${opts} -e USER=root -u root"
elif [[ $(uname) == Linux ]]; then
    dockerhomedir="/home/$(id -un)"
    opts="${opts} -e USER=$(id -un) -u $(id -u):$(id -g) -v /etc/passwd:/etc/passwd:ro"
elif [[ $(uname) == Darwin ]]; then
    dockerhomedir=/home/docker-user
    opts="${opts} -e USER=docker-user -u docker-user"
else
    echo "Platform $(uname) is not supported"
    exit 1
fi


opts="${opts}
-e HOME=${dockerhomedir}
-e IMAGE_NAME=${imagename}
-e IMAGE_VERSION=${imageversion}
-e TZ=America/Los_Angeles
--memory ${memory_limit}
--shm-size ${shm_size}
--init"

if [[ "${is_ext_image}" == no ]] && [[ "${is_base_image}" == no ]]; then
    LOGDIR_h="${hostworkdir}/log/${imagename_base}"
    LOGDIR_d="${dockerhomedir}/log"
    mkdir -p "${LOGDIR_h}"
    opts="${opts} -v ${LOGDIR_h}:${LOGDIR_d}"
    opts="${opts} -e LOGDIR=${LOGDIR_d}"

    DATADIR_h="${hostworkdir}/data/${imagename_base}"
    DATADIR_d="${dockerhomedir}/data"
    mkdir -p "${DATADIR_h}"
    opts="${opts} -v ${DATADIR_h}:${DATADIR_d}"
    opts="${opts} -e DATADIR=${DATADIR_d}"

    CFGDIR_h="${hostworkdir}/config/${imagename_base}"
    CFGDIR_d="${dockerhomedir}/config"
    mkdir -p "${CFGDIR_h}"
    opts="${opts} -v ${CFGDIR_h}:${CFGDIR_d}"
    opts="${opts} -e CFGDIR=${CFGDIR_d}"
fi

TMPDIR_h="${hostworkdir}/tmp"
TMPDIR_d="${dockerhomedir}/tmp"
mkdir -p "${TMPDIR_h}"
opts="${opts} -v ${TMPDIR_h}:${TMPDIR_d}"
opts="${opts} -e TMPDIR=${TMPDIR_d}"


if [[ "${is_dev_image}" == yes ]]; then
    opts="${opts} -v ${hostworkdir}/src/${imagename_base}:${dockerhomedir}/src"
    if [[ "${with_pythonpath}" == yes ]]; then
        opts="${opts} -e PYTHONPATH=${dockerhomedir}/src/src"
    fi
fi

if [[ "${command}" == "notebook" ]]; then
    opts="${opts} --expose=${nb_port} -p ${nb_port}:${nb_port}"
    opts="${opts} -e JUPYTER_DATA_DIR=/tmp/.jupyter/data -e JUPYTER_RUNTIME_DIR=/tmp/.jupyter/runtime"
    command="jupyter notebook --port=${nb_port} --no-browser --ip=0.0.0.0 --NotebookApp.notebook_dir='${dockerhomedir}' --NotebookApp.token=''"
elif [[ "${command}" == "py.test" ]]; then
    args="-p no:cacheprovider ${args}"
fi

if [[ " /bin/bash /bin/sh bash sh " == *" ${command} "* ]]; then
    opts="${opts} -it"
fi

if [[ "${daemon_mode}" != yes ]]; then
    opts="${opts} --rm"
fi

if [[ "${command}" == notebook ]] || [[ "${is_dev_image}" != yes ]]; then
    opts="${opts} --workdir ${dockerhomedir}"
else
    opts="${opts} --workdir ${dockerhomedir}/src"
fi

if [[ "${imagename}" == alpine ]] && [[ "${command}" == /bin/bash ]]; then
    command=/bin/sh
fi


docker run ${opts} ${imagename}:${imageversion} ${command} ${args}
