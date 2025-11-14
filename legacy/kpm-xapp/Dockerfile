# Build 
FROM golang:1.18 as kpm-build

RUN apt update && apt install -y iputils-ping net-tools curl sudo 

ARG RMRVERSION=4.8.3
RUN wget --content-disposition https://packagecloud.io/o-ran-sc/release/packages/debian/stretch/rmr_${RMRVERSION}_amd64.deb/download.deb && dpkg -i rmr_${RMRVERSION}_amd64.deb && rm -rf rmr_${RMRVERSION}_amd64.deb
RUN wget --content-disposition https://packagecloud.io/o-ran-sc/release/packages/debian/stretch/rmr-dev_${RMRVERSION}_amd64.deb/download.deb && dpkg -i rmr-dev_${RMRVERSION}_amd64.deb && rm -rf rmr-dev_${RMRVERSION}_amd64.deb

WORKDIR /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm


COPY e2ap /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm/e2ap
COPY e2sm /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm/e2sm
COPY cmd /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm/cmd
# COPY config /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm/config
COPY go.mod /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm/
COPY go.sum /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm/


# Compile E2AP
RUN cd e2ap && \
    gcc -c -fPIC -I header/ lib/*.c  wrapper.c  && \ 
    gcc *.o -shared -o libe2apwrapper.so && \
    cp libe2apwrapper.so /usr/local/lib/ && \
    mkdir /usr/local/include/e2ap && \
    cp wrapper.h header/*.h /usr/local/include/e2ap && \
    ldconfig && \
    rm *.o

# Compile E2SM
RUN cd e2sm && \
    gcc -c -fPIC -I header/ lib/*.c  wrapper.c -lm  && \
    gcc *.o -shared -o libe2smwrapper.so && \
    cp libe2smwrapper.so /usr/local/lib/ && \
    mkdir /usr/local/include/e2sm && \
    cp wrapper.h header/*.h /usr/local/include/e2sm && \
    ldconfig && \ 
    rm *.o

WORKDIR /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm

RUN go version
ENV GO111MODULE=on GO_ENABLED=0 GOOS=linux

COPY control /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm/control

RUN go mod tidy

RUN go build -a -installsuffix cgo -o kpm-app ./cmd/kpm.go

# Deploy
FROM ubuntu:20.04

ENV CFG_FILE=/opt/ric/config/config-file.json 
ENV RMR_SEED_RT=config/uta_rtg.rt

RUN mkdir /config

COPY --from=kpm-build /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm/kpm-app /
# COPY --from=kpm-build /go/src/gerrit.o-ran-sc.org/r/scp/ric-app/kpm/config/* /config/
COPY --from=kpm-build /usr/local/lib /usr/local/lib
COPY --from=kpm-build /usr/local/include/e2ap/*.h /usr/local/include/e2ap/
COPY --from=kpm-build /usr/local/include/e2sm/*.h /usr/local/include/e2sm/

RUN ldconfig

RUN chmod 755 /kpm-app
CMD /kpm-app