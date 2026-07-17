#bin/bash.sh

sudo apt update
sudo apt install -y \
    openjdk-21-jdk \
    maven \
    curl \
    wget \
    leiningen \
    pkg-config
sudo apt upgrade