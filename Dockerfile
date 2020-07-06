# chasoman: This file is an edited version of the Dockerfile.aceonly
# chasoman: I have made the edits to create an s2i builder image for ACE 11
# chasoman: All edits have been tagged with 'chasoman:' comments

FROM golang:1.14.2 as builder

WORKDIR /go/src/github.com/ot4i/ace-docker/
ARG IMAGE_REVISION="Not specified"
ARG IMAGE_SOURCE="Not specified"

COPY go.mod .
COPY go.sum .
RUN go mod download

COPY cmd/ ./cmd
COPY internal/ ./internal
RUN go build -ldflags "-X \"main.ImageCreated=$(date --iso-8601=seconds)\" -X \"main.ImageRevision=$IMAGE_REVISION\" -X \"main.ImageSource=$IMAGE_SOURCE\"" ./cmd/runaceserver/
RUN go build ./cmd/chkaceready/
RUN go build ./cmd/chkacehealthy/
# Run all unit tests
RUN go test -v ./cmd/runaceserver/
RUN go test -v ./internal/...
RUN go vet ./cmd/... ./internal/...

# chasoman: hard coded the ACE 11.0.0.7 Developers edition tar name
ARG ACE_INSTALL=11.0.0.7-ACE-LINUX64-DEVELOP.tar.gz
WORKDIR /opt/ibm
COPY deps/$ACE_INSTALL .
RUN mkdir ace-11
# chasoman: Removed the '--exclude ace-11.\*/tools' option because we need mqsicreatebar from tools directory to be able to compile source into bars.
RUN tar -xzf $ACE_INSTALL --absolute-names --strip-components 1 --directory /opt/ibm/ace-11

# chasoman: changed from redhat ubi 8 to centos 7
FROM centos:7 

ENV SUMMARY="Integration Server for App Connect Enterprise" \
    DESCRIPTION="Integration Server for App Connect Enterprise" \
    PRODNAME="AppConnectEnterprise" \
    COMPNAME="IntegrationServer"

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.description="$DESCRIPTION" \
      io.k8s.display-name="Integration Server for App Connect Enterprise" \
      io.openshift.tags="$PRODNAME,$COMPNAME" \
      com.redhat.component="$PRODNAME-$COMPNAME" \
      name="$PRODNAME/$COMPNAME" \
      vendor="IBM" \
      version="11.0.0.7" \
      release="1" \
      license="IBM" \
      maintainer="Hybrid Integration Platform Cloud" \
      io.openshift.expose-services="" \
      usage=""

# Add required license as text file in Liceses directory (GPL, MIT, APACHE, Partner End User Agreement, etc)
COPY /licenses/ /licenses/

# Create OpenTracing directories, update permissions and copy in any library or configuration files needed
RUN mkdir /etc/ACEOpenTracing /opt/ACEOpenTracing /var/log/ACEOpenTracing && chmod 777 /var/log/ACEOpenTracing /etc/ACEOpenTracing
COPY deps/OpenTracing/library/* ./opt/ACEOpenTracing/
COPY deps/OpenTracing/config/* ./etc/ACEOpenTracing/

WORKDIR /opt/ibm

# chasoman: changed the microdnf install commands to yum install commands
RUN  yum install -y findutils && yum install -y OpenIPMI-python 
COPY --from=builder /opt/ibm/ace-11 /opt/ibm/ace-11

# Copy in PID1 process
COPY --from=builder /go/src/github.com/ot4i/ace-docker/runaceserver /usr/local/bin/
COPY --from=builder /go/src/github.com/ot4i/ace-docker/chkace* /usr/local/bin/

# Copy in script files
COPY *.sh /usr/local/bin/

# Install kubernetes cli
COPY ubi/install-kubectl.sh /usr/local/bin/
RUN chmod u+x /usr/local/bin/install-kubectl.sh \
  && install-kubectl.sh \
  && yum update -y

# Create a user to run as, create the ace workdir, and chmod script files
RUN mkdir -p /var/mqsi \
    && /opt/ibm/ace-11/ace make registry global accept license silently \
    && mkdir -p /home/aceuser/initial-config
RUN su - -c '. /opt/ibm/ace-11/server/bin/mqsiprofile \
    && mqsicreateworkdir /home/aceuser/ace-server' \
    && chmod -R 777 /home/aceuser \
    && chmod -R 777 /var/mqsi

# Set BASH_ENV to source mqsiprofile when using docker exec bash -c
ENV BASH_ENV=/usr/local/bin/ace_env.sh

# Expose ports.  7600, 7800, 7843 for ACE; 9483 for ACE metrics
EXPOSE 7600 7800 7843 9483

WORKDIR /home/aceuser

ENV LOG_FORMAT=basic

# Set entrypoint to run management script

# chasoman: commented the entrypoint script because this will be run from the s2i/run script
# ENTRYPOINT ["runaceserver"]
