FROM node:22

WORKDIR /app
COPY ./app .
RUN npm install
RUN npm install -g @angular/cli
RUN ng build
RUN npm install -g serve
RUN chmod +x /app/docker-entrypoint.sh

EXPOSE 4200
ENTRYPOINT ["/app/docker-entrypoint.sh"]