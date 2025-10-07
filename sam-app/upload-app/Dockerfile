FROM python:3.12-slim

COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 /lambda-adapter /opt/extensions/lambda-adapter

WORKDIR /var/task

ENV PORT=8000

COPY requirements.txt ./
RUN python -m pip install -r requirements.txt

COPY ./app .

CMD ["sh", "-c", "exec uvicorn --port=$PORT main:app"]