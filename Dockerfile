FROM redis:8.8.0-alpine

COPY ./start_redis.sh /usr/local/bin/

EXPOSE 6379
CMD ["start_redis.sh"]
