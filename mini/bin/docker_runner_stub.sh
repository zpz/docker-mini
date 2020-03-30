#set -o errexit
set -o nounset
set -o pipefail

# For all the directory and file names touched by this script,
# space in the name is not supported.
# Do not use space in directory and file names in ${HOME}/work and under it.


function run_docker {
    local imagename=""
    local name=""
    local command=''
    local args=""
    local opts=""
    local with_pythonpath=yes
    local daemon_mode=no
    local as_root=no
    local use_local=no
    local nb_port=8888
    local memory_limit=12g
    local shm_size=4g
    local restart=
    local z

    local hostdatadir=''
    local hostlogdir=''
    local hosttmpdir=''
    local hostsrcdir=''
    local hostcfgdir=''

    # Parse arguments.
    # Before the argument for image name,
    # some arguments are consumed by this script;
    # the rest are stored to be passed on to the command `docker run`.
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
            elif [[ "$1" == --network=* ]]; then
                z="$1"
                z="${z#*=}"
                opts="${opts} --network $z"
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
            elif [[ "$1" == --no-pythonpath ]]; then
                # Do not put `~/src/src` on `$PYTHONPATH`.
                # This has an effect only in the 'development' mode, i.e.
                # when launching an image whose name does not end with '-[branchname]'.
                with_pythonpath=no
            elif [[ "$1" == --root ]]; then
                as_root=yes
            elif [[ "$1" == --local ]]; then
                use_local=yes
            elif [[ "$1" == --name ]]; then
                shift
                name="$1"
            elif [[ "$1" == --name=* ]]; then
                name="$1"
                name="${name#*=}"
            elif [[ "$1" == --restart ]]; then
                shift
                restart="$1"
            elif [[ "$1" == --restart=* ]]; then
                restart="$1"
                restart="${restart#*=}"
            elif [[ "$1" == "-d" ]] || [[ "$1" == "--detach" ]]; then
                daemon_mode=yes

            elif [[ "$1" == --hostdatadir ]]; then
                shift
                hostdatadir="$1"
            elif [[ "$1" == --hostdatadir=* ]]; then
                hostdatadir="$1"
                hostdatadir="${hostdatadir#*=}"
            elif [[ "$1" == --hostlogdir ]]; then
                shift
                hostlogdir="$1"
            elif [[ "$1" == --hostlogdir=* ]]; then
                hostlogdir="$1"
                hostlogdir="${hostlogdir#*=}"
            elif [[ "$1" == --hosttmpdir ]]; then
                shift
                hosttmpdir="$1"
            elif [[ "$1" == --hosttmpdir=* ]]; then
                hosttmpdir="$1"
                hosttmpdir="${hosttmpdir#*=}"
            elif [[ "$1" == --hostsrcdir ]]; then
                shift
                hostsrcdir="$1"
            elif [[ "$1" == --hostsrcdir=* ]]; then
                hostsrcdir="$1"
                hostsrcdir="${hostsrcdir#*=}"
            elif [[ "$1" == --hostcfgdir ]]; then
                shift
                hostcfgdir="$1"
            elif [[ "$1" == --hostcfgdir=* ]]; then
                hostcfgdir="$1"
                hostcfgdir="${hostcfgdir#*=}"

            elif [[ "$1" == -* ]]; then
                # Every other argument is captured and passed on to `docker run`.
                # For example, if there is an option called `--volume` which sets
                # something called 'volume', you may specify it like this
                #
                #   --volume=30
                #
                # You can not do
                #
                #   --volume 30
                #
                # because `run-docker` does not explicitly capture this option,
                # hence it does not know this option has two parts.
                # The same idea applies to other options.
                opts="${opts} $1"
            else
                imagename="$1"
            fi
            shift
        else
            # After `imagename`.
            command="$1"
            shift
            if [[ $# > 0 ]]; then
                args="$@"
            fi
            break
        fi
    done

    if [[ "${imagename}" == "" ]]; then
        echo "${USAGE}"
        exit 1
    fi

    if [[ ${restart} != '' ]]; then
        opts="${opts} --restart=${restart}"
    fi
    if [[ "${daemon_mode}" == yes ]]; then
        opts="${opts} -d"
    fi

    local is_ext_image=no
    local is_dev_image=no
    local is_base_image=no
    local is_interactive=no

    if [[ ${imagename} != zppz/* ]]; then
        is_ext_image=yes
        if [[ ${imagename} != *:* ]]; then
            >&2 echo "external image '${imagename}' must have tag specified"
            exit 1
        fi
    fi

    if [[ ${use_local} == no ]]; then
        pull-latest-image ${imagename}
    else
        opts="${opts} -e DOCKER_LOCAL_MODE=1"
    fi

    if [[ ${imagename} != *:* ]]; then
        imagename=$(find-latest-image-local ${imagename}) || exit 1
    fi

    local imageversion=${imagename##*:}
    local imagenamespace
    imagename=${imagename%:*}
    local imagefullname="${imagename}"
    if [[ "${imagename}" == */* ]]; then
        imagenamespace=${imagename%%/*}
        imagename=${imagename#*/}
        # Now `imagename` contains neither namespace nor tag.
    else
        imagenamespace=''
    fi

    if [[ ${command} == '' ]]; then
        if [[ ${imagename} == mini ]]; then
            command=/bin/sh
        else
            command=/bin/bash
        fi
    fi

    if [[ "${args}" == '' ]] \
          && [[ " /bin/bash /bin/sh bash sh python ptpython ptipython ipython " == *" ${command} "* ]]; then
        is_interactive=yes
        opts="${opts} -it"
    fi

    local dockerhomedir

    if [[ "${as_root}" == yes ]] \
            || [[ "${is_ext_image}" == yes ]] \
            || [[ "${imagename}" == mini ]] \
            || [[ "$(id -un)" == root ]]; then
        dockerhomedir=/root
        opts="${opts} -e USER=root -u root"
    elif [[ $(uname) == Linux ]]; then
        dockerhomedir="/home/$(id -un)"
        opts="${opts} -e USER=$(id -un) -u $(id -u):$(id -g) -v /etc/passwd:/etc/passwd:ro"
    elif [[ $(uname) == Darwin ]]; then
        dockerhomedir=/home/docker-user
        opts="${opts} -e USER=docker-user -u docker-user"
    else
        >&2 echo "Platform $(uname) is not supported"
        exit 1
    fi

    local BASE_IMAGES="dl jekyll mini py3r latex ml py3"

    local hostworkdir="${HOME}/work"
    mkdir -p ${hostworkdir}

    if [[ " ${BASE_IMAGES} " == *" ${imagename} "* ]]; then
        is_base_image=yes
    elif [[ "${is_ext_image}" == no ]]; then
        if [ -d "${hostworkdir}/src/${imagename}" ]; then
            is_dev_image=yes
        fi
    fi

    if [[ ${name} == '' ]]; then
        name="$(whoami)-$(TZ=America/Los_Angeles date +%Y%m%d-%H%M%S)"
    fi

    opts="${opts}
    -e HOME=${dockerhomedir}
    -e IMAGE_NAME=${imagename}
    -e IMAGE_VERSION=${imageversion}
    -e TZ=America/Los_Angeles
    --memory ${memory_limit}
    --shm-size ${shm_size}
    --name ${name}
    --init"

    if [ -z "${restart}" ] || [[ ${daemon_mode} == no ]]; then
        opts="${opts} --rm"
    fi

    opts="${opts} -e HOST_UNAME=$(uname) -e HOST_WHOAMI=$(whoami)"
    if [[ "$(uname)" == Linux ]]; then
        opts="${opts} -e HOST_IP=$(hostname -i)"
    fi

    if [[ "${is_ext_image}" == no ]] && [[ "${is_base_image}" == no ]]; then
        if [[ "${hostdatadir}" == '' ]]; then
            hostdatadir=${hostworkdir}/data
        fi
        mkdir -p ${hostdatadir}
        opts="${opts} -v ${hostdatadir}:${dockerhomedir}/data"
        opts="${opts} -e DATADIR=${dockerhomedir}/data"

        if [[ "${hostlogdir}" == '' ]]; then
            hostlogdir=${hostworkdir}/log
        fi
        mkdir -p ${hostlogdir}
        opts="${opts} -v ${hostlogdir}:${dockerhomedir}/log"
        opts="${opts} -e LOGDIR=${dockerhomedir}/log"

        if [[ "${hostcfgdir}" == '' ]]; then
            hostcfgdir=${hostworkdir}/cfg
        fi
        mkdir -p ${hostcfgdir}
        opts="${opts} -v ${hostcfgdir}:${dockerhomedir}/cfg"
        opts="${opts} -e CFGDIR=${dockerhomedir}/cfg"
    fi

    if [[ "${hosttmpdir}" == '' ]]; then
        hosttmpdir=${hostworkdir}/tmp
    fi
    mkdir -p ${hosttmpdir}
    opts="${opts} -v ${hosttmpdir}:${dockerhomedir}/tmp"
    opts="${opts} -e TMPDIR=${dockerhomedir}/tmp"

    if [[ "${is_dev_image}" == yes ]]; then
        if [[ "${hostsrcdir}" == '' ]]; then
            hostsrcdir="${hostworkdir}/src/${imagename}"
        fi
        opts="${opts} -v ${hostsrcdir}:${dockerhomedir}/src"
        if [[ "${with_pythonpath}" == yes ]]; then
            opts="${opts} -e PYTHONPATH=${dockerhomedir}/src/src"
        fi
    fi

    if [[ "${command}" == "notebook" ]]; then
        opts="${opts} --expose=${nb_port} -p ${nb_port}:${nb_port}"
        opts="${opts} -e JUPYTER_DATA_DIR=/tmp/.jupyter/data"
        opts="${opts} -e JUPYTER_RUNTIME_DIR=/tmp/.jupyter/runtime"
        command="jupyter notebook --port=${nb_port} --no-browser --ip=0.0.0.0 --NotebookApp.notebook_dir='${dockerhomedir}' --NotebookApp.token=''"
    elif [[ "${command}" == "py.test" ]]; then
        args="-p no:cacheprovider ${args}"
    fi

    if [[ "${command}" == notebook ]] || [[ "${is_dev_image}" == no ]]; then
        opts="${opts} --workdir ${dockerhomedir}"
    else
        opts="${opts} --workdir ${dockerhomedir}/src"
    fi

    docker run ${opts} ${imagefullname}:${imageversion} ${command} ${args}
}



USAGE=$(cat <<'EOF'
Usage:
   run-docker [options] image-name[:tag] [command [...]]
where 

`image-name` is like 'zppz/py3', etc.

`command` is command to be run within the container, followed by arguments to the command.
(Default: /bin/bash)

If image tag is not specified, the most up-to-date tag is used.
EOF
)


if [[ $# < 1 ]]; then
    echo "${USAGE}"
    exit 0
fi

run_docker $@
