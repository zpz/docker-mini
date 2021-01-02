FROM busybox:1

COPY tools/* /usr/tools/
CMD /bin/sh
