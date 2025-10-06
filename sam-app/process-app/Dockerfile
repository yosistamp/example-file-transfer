# Use the official AWS Lambda Python image as a base image
FROM public.ecr.aws/lambda/python:3.11

# Set the working directory in the container
WORKDIR /var/task

# Copy the application code into the container
COPY ./app .

# Set the command to specify the handler
CMD [ "main.lambda_handler" ]