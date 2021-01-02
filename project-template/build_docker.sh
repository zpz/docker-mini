#!/bin/bash

set -e

MINI=$(bash -c "$(docker run --rm zppz/tiny:21.01.01 cat /find-image)" -- zppz/mini)
cmd="$(docker run --rm ${MINI} cat /tools/build-docker)"
bash -c "${cmd}" -- $@
