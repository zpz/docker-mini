# docker-mini

This repo defines a small Docker image that contains tools for my Docker workflow.

This image is the next step after [`zppz/tiny`](https://github.com/zpz/docker-tiny). While `zppz/tiny` is quite stable, `zppz/mini` may evolve relatively fast. The stable image `zppz/tiny` contains commands, among other tools, that find the latest image `zppz/mini`.

The image `zppz/mini` contains two stand-alone scripts for building image and running container, respectively. Both scripts evolve as needed.

A user does not use these scripts directly. Rather, they use "proxy" commands [run-docker](./sbin/run-docker)---defined in this repo---and [build-docker](https://github.com/zpz/docker-project-template-py/blob/master/build-docker)---defined in another repo that provides a user-repo template. The proxy commands are short and relatively stable. They use `zppz/tiny` to find the latest version of `zppz/mini` and then use the scripts therein.

Please see [docker](https://github.com/zpz/docker) for more info.

