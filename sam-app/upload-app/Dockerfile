# Use the official Python image as a base image
FROM public.ecr.aws/lambda/python:3.12

# Install Lambda Web Adapter
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 /lambda-adapter /opt/extensions/lambda-adapter

# Set the working directory in the container
WORKDIR /var/task

# Copy the requirements file and install dependencies
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copy the application code
COPY ./app .

# Set the command to run the application
ENV PORT=8080
CMD ["sh", "-c", "exec uvicorn --port=$PORT main:app"]