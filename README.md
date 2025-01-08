# docker-mini

This repo defines a small Docker image that contains tools for my Docker workflow.

Original design
---------------

This image is the next step after [`zppz/tiny`](https://github.com/zpz/docker-tiny).
While `zppz/tiny` is quite stable, `zppz/mini` may evolve relatively fast. The stable image `zppz/tiny` contains commands, among other tools, that find the latest version of the image `zppz/mini`.

This image contains scripts relevant to *pip-based* repos and *docker-based* repos.
The first type of repos develops a Python package with dependencies specified by a `pyproject.toml` file.
The second type of repos develops "applications" as a Python package; the repo has its own Dockerfile,
which handles all installation of dependencies. On the other hand, its `pyproject.toml` file does not specify dependencies at all.
In addition, the command [`run-docker`](./bin/run-docker) is a versatile tool for running Docker containers during development.

The usage of this repo is best illustrated by example repos. Currently I have active projects that are "pip-based".
A good example is [biglist](https://github.com/zpz/biglist).

Please see [docker](https://github.com/zpz/docker) for more info.

Design evolves
--------------

Since January 2025, the design of this tool is evolving in this direction: the utility scripts are typically standing-alone so that each can be used directly. For example, to use the script `run` in `tools/pip-based/` you can use this your your script:

    bash <(curl -s https://raw.githubusercontent.com/zpz/docker-mini/main/tools/pip-based/run) $@

In the original Docker-based design, in contrast, the script `run` would be obtained from the Docker image `mini`, (the latest version of) which is in turn found using the Docker image `tiny`. In development contexts that allows direct download from ``github``, this new way is simpler.

In the meantime, the original Docker-based design is still kept in mind.