FROM ubuntu

RUN apt-get update
RUN apt-get install -y nodejs npm
RUN ln -s /usr/bin/nodejs /usr/bin/node

COPY . /src

RUN rm -rf /src/node_modules
RUN cd /src; npm install

ENV REDIS_HOST 127.0.0.1
ENV REDIS_PORT 6379
ENV EXEC_RUNNER core@172.17.42.1
ENV WORKER_HOST _

EXPOSE 80

CMD ["/src/node_modules/.bin/coffee", "/src/node.coffee", "--nodejs"]
