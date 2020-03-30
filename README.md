# docker-tools

Tools for a Docker stack for Python code development.

Check out related repo [docker](https://github.com/zpz/docker).

<!-- toc -->

* [Directory structure for code development](#directory-structure)
* [Using `Jupyter Notebook`](#jupyter-notebook)

<!-- end of toc -->


<a name="directory-structure"></a>
## Directory structure for code development

Suppose the home directory is `/Users/username` (on Mac) or `/home/username` (on Ubuntu Linux), represented by the environment variable `HOME`, my Docker stack recommends the following directory structure for code development:

```
$HOME/work/
        |-- bin/
        |-- config/
        |-- data/
        |-- log/
        |-- src/
        |     |-- repo1/
        |     |-- repo2/
        |     |-- and so on
        |-- tmp/
```

The directories in `$HOME/work/src/` are `git` repos and are source-controlled. 
Other subdirectories of `work` are *not* in source control and *not* stored in the cloud.

Space and non-ascii characters are better avoided in directory and file names.

The script `install.sh` installs commands into `$HOME/work/bin`, where `$HOME` is the user's home directory.
Make sure this directory is on the system `PATH`.

The main command installed is `run-docker`.
When using `run-docker` to launch a Docker container based on an image defined in this stack,
the directory `~/work` is mapped into the container with the same name.


<a name="jupyter-notebook"></a>
## Using `Jupyter Notebook`

When using `run-docker` to launch a container based on an image defined in this stack,
say the image `ml`, if you type

```
$ run-docker zppz/ml notebook
```

will start a `Jupyter Notebook` server in the container.

Once the server is running, access it at `http://localhost:8888` using your favorite browser.

The execution environment for this notebook is identical to that within the container launched by

```
$ run-docker zppz/ml
```

The server stays in the front of the terminal. You may kill it by `Control-C`.

You can have only one such `notebook` container running at any time, because it occupies the port `8888`, which can not be used by another `Jupyter Notebook` server.


