# ohifenv

A set of scripts for setting up the [OHIF Viewers](https://github.com/OHIF/Viewers "OHIF Viewers") development environment within Docker® containers.

#### Foreword

In order to use this utility you need to have Docker® installed on the host machine. It has been tested on Mac OS X® and Linux®. Although it has not been tested on Windows®, it should also run on that platform with minor or no modifications. For Windows® something like Git-Bash or MingGW is needed since the `env/up.sh` script has no `.bat` counterpart (sorry, no time left for that).

This tiny project was created to satisfy personal needs but I decided to make it public since someone might think it's useful.

#### Basic Instructions

1. Download the contents of this repository (or clone it, if you have git on the host machine);
1. Open a terminal and navigate to folder where the contents of the package were saved;
1. Run `env/up.sh`;
1. Attach to the application container `docker exec -i -t ohif_app /bin/bash`;
1. Run the provisioning script with `cd /home/ohif/; env/utils/setup.sh`;
1. Execute application with `job.sh start app/main.sh`;

After executing the last command you'll be prompted about which application you wish to run.

###### A summary of commands:

```
$ cd "path/to/ohifenv"
$ env/up.sh
$ docker exec -i -t ohif_app /bin/bash
$ cd "/home/ohif"
$ env/utils/setup.sh
$ job.sh start app/main.sh
```

###### Querying for application status
```
$ job.sh status app/main.sh
```

###### Stopping the application
```
$ job.sh stop app/main.sh
```

#### Folder Structure

The project folder has the following structure:

```
ohifenv/
|-- README.md
|-- app/
|   |-- hook_main.sh
|   `-- main.sh
|-- assets/
|   `-- examples.tar.gz
|-- env/
|   |-- lib/
|   |   `-- helpers.sh
|   |-- up.sh
|   `-- utils/
|       |-- job.sh
|       |-- jobtree.sh
|       |-- rkill.sh
|       |-- setup.sh
|       `-- sleepingtree.sh
|-- src/
```

#### File Description

I think it's important to draw attention to the following files:

* `env/up.sh`

  This file is responsible for properly creating and starting the containers. In a nutshell, it creates two containers (`ohif_app` and `ohif_db`) and links one to the other. Also, the root folder of the project is mounted at the `/home/ohif` directory of the `ohif_app` container efectively sharing their contents. It is the *only* script which is supposed to run on the host machine.

* `env/utils/setup.sh`

  After the application container (`ohif_app`) has been created, it must be provisioned. This script is responsible for that. Among other things it installs [tj/n](https://github.com/tj/n "tj/n - a Node.js version manager") (a simple Node.js version manager), Node.js, Meteor and Git. After all dependencies have been installed, the *OHIF Viewers* repository is cloned inside the `src/` folder. This folder is by default shared with the host machine such that its contents are preserved even after the container has been destroyed.

* `app/main.sh`

  This script, along with `hook_main.js`, is the actual responsible for running the applications (OHIFViewer and LeisonTracker). It is supposed to be run with the help of `job.sh` script which keeps track of applications running on background.

* `env/utils/job.sh`

  A simple utility to start and keep track of applications running on background. It protects the running application from SIGHUP signals and also keep their outputs in specific log files. When a `hook_{appname}` is found in the same directory of the target application, it gets executed in foreground before the target application is started on background.

* `assets/examples.tar.gz`

  Example DICOM images to be uploaded to *Orthanc®*
