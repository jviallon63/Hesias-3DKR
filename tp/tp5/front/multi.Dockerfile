FROM node:22-alpine AS build
WORKDIR /app
COPY --chown=node:node . .
RUN npm ci && npm cache clean --force
RUN npx ng build

FROM nginxinc/nginx-unprivileged:stable-alpine

COPY ./default.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 ./40-backend-url.sh /docker-entrypoint.d/40-backend-url.sh
COPY --from=build --chown=101:101 /app/dist/browser /usr/share/nginx/html

ENV BACKEND_URL=http://localhost:8080
EXPOSE 4200