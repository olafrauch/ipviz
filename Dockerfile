FROM ubuntu:18.04

ENV \
	TZ=Europe/Berlin \
	WORKDIR="/work"

COPY ["ipviz.sh", "/usr/local/bin/ipviz.sh"]

RUN \
    log() { echo "\e[96m### $1 ###\e[0m"; } && \
    log "Print base image version" && \
	    cat /etc/*release* && \
    log "Installing dependencies" && \
      apt-get update && \
      apt-get install -y apt-utils && \
    log "Setting locale" && \
      echo $TZ > /etc/timezone && \
      export DEBIAN_FRONTEND=noninteractive && apt-get install -y tzdata && \
      rm /etc/localtime && \
      ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
      dpkg-reconfigure -f noninteractive tzdata && \
    log "Preparing ipv4 build dependencies" && \
  		apt-get install -y git make gcc libgd-dev locales && \
    log "Installing ipviz dependencies" && \
      apt-get install -y ipcalc imagemagick jq grepcidr prips && \
      apt-get autoclean && \
    log "Build ipv4-heatmap" && \
      BUILD_DIR="/usr/share/ipv4-heatmap" && \
      git clone https://github.com/measurement-factory/ipv4-heatmap ${BUILD_DIR} && \
      cd ${BUILD_DIR} && \
      make install  && \
      cd ~ && \
      rm -rf ${BUILD_DIR} && \
    log "Cleanup" && \
      apt-get -y remove gcc git && \
      apt -y autoremove && \
  		rm -rf /var/lib/apt/lists/* && \
    log "Prepare workdir ${WORKDIR}" && \
  		mkdir -p "${WORKDIR}" && \
    log "Validating tools" && \
      convert -version && \
      ipcalc -v && \
      command -v jq && \
      nmap -V && \
      ipviz.sh -h && \
      date && \
    log "Done"

VOLUME ["${WORKDIR}"]
WORKDIR "${WORKDIR}"

ENTRYPOINT ["/usr/local/bin/ipviz.sh"]
 