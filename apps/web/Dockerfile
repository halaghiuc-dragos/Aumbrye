# syntax=docker/dockerfile:1
FROM node:24-alpine AS build
WORKDIR /app
COPY apps/web/package.json apps/web/package-lock.json ./apps/web/
RUN npm ci --prefix apps/web
COPY apps/web/ apps/web/
COPY packages/shared/openapi/ packages/shared/openapi/
ARG VITE_API_URL
ENV VITE_API_URL=${VITE_API_URL}
RUN npm run build --prefix apps/web

FROM nginx:1.27-alpine AS runtime
COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/apps/web/dist /usr/share/nginx/html
EXPOSE 80
