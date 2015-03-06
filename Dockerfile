FROM centos:centos6

RUN rpm -Uvh http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm
RUN yum install -y npm

COPY . /src

RUN rm -rf /src/node_modules
RUN cd /src; npm install

ENV REDIS_HOST 127.0.0.1
ENV REDIS_PORT 6379
ENV EXEC_RUNNER core@172.17.42.1
ENV WORKER_HOST _

EXPOSE 80

CMD ["/src/node_modules/.bin/coffee", "/src/node.coffee", "--nodejs"]
