FROM node:22-alpine

RUN npm install -g serve && npm cache clean --force

WORKDIR /app
RUN chown node:node /app
USER node

COPY --chown=node:node ./app .
RUN npm ci && npm cache clean --force
RUN npx ng build && rm -rf .angular
RUN chmod +x /app/docker-entrypoint.sh

ENV BACKEND_URL=http://localhost:8080
EXPOSE 4200
ENTRYPOINT ["/app/docker-entrypoint.sh"]