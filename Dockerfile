# syntax=docker/dockerfile:1

FROM python:3.8-slim-buster

WORKDIR /app

RUN apt update
RUN apt install -y wget
RUN wget "https://storage.yandexcloud.net/cloud-certs/CA.pem" -O ./CA.pem

COPY requirements.txt requirements.txt
RUN pip3 install -r requirements.txt

COPY populate_kafka.py .

ENV BOOTSTRAP_SERVERS ""
ENV ADMIN_PASSWORD ""

CMD [ "python3", "populate_kafka.py"]
