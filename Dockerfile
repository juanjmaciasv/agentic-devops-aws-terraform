# Build stage: Debian-based Node 15 (matches .nvmrc) so node-sass gets its prebuilt binary
FROM node:15.5.1-buster-slim AS build

WORKDIR /app

ARG REACT_APP_API_URL=http://localhost:8080
ENV REACT_APP_API_URL=$REACT_APP_API_URL

COPY package*.json .npmrc ./
RUN npm ci

COPY public ./public
COPY src ./src
RUN npm run build

FROM nginx:1.27-alpine

# FIX: nginx.conf only contains a `server {}` block. Copying it over
# /etc/nginx/nginx.conf (which needs events{}/http{}) made nginx exit on start.
# It belongs in conf.d as the default site.
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget -q -O /dev/null http://127.0.0.1/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
