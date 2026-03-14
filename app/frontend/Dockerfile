FROM nginx:1.27-alpine

ARG APP_NAME=ecs-bg-deployment
ARG APP_VERSION=v1

ENV APP_NAME=${APP_NAME}
ENV APP_VERSION=${APP_VERSION}

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
