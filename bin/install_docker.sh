# Install Docker on Linux.
# The Docker available from the default repos is not up to date.
# The main point of this script is to install an up-to-date version.
#
# Usage:
#
# > sudo bash install_docker.sh

apt-get remove -y docker docker-engine docker.io
apt-get update
apt-get install -y --no-install-recommends apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
apt-key fingerprint 0EBFCD88
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y --no-install-recommends docker-ce
