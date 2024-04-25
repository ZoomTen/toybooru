FROM akito13/nim:2.0.0
RUN apt-get update && apt-get install -y libpq-dev libsodium23

COPY . /app
WORKDIR /app

RUN nimble -y -d:chronicles_disabled_topics:\"stdlib\" -d:chronicles_line_numbers -d:usePostgres build booru

VOLUME /app/public/images
VOLUME /app/public/thumbs

#RUN mkdir _temp_
ENTRYPOINT ["/app/booru"]
