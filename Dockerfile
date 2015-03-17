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

# docker run -d --name cloud-worker -e REDIS_HOST=docker1.rni.org -e WORKER_API=$(ifconfig | grep -A 1 'eno1' | tail -1 | cut -d ' ' -f 10):80 -e "EXEC_RUNNER=ssh core@172.17.42.1" -p 80:80 -v /root/.ssh:/root/.ssh -v /usr/bin/ssh:/usr/bin//ssh docker-registry.isd.ictu:5000/cloud-worker
