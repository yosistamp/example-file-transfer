import json
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """
    Processes DynamoDB Stream events passed from Step Functions.

    This function expects an event that is a list of records from an
    EventBridge Pipe, which originates from a DynamoDB Stream.
    """
    logger.info(f"Received event: {json.dumps(event)}")

    processed_records = []

    # The event from the Pipe is a list of records
    for record in event:
        # Ensure the record has the expected structure
        if 'dynamodb' not in record or 'NewImage' not in record['dynamodb']:
            logger.warning(f"Skipping malformed record: {json.dumps(record)}")
            continue

        # Process only INSERT events
        if record.get('eventName') == 'INSERT':
            try:
                new_image = record['dynamodb']['NewImage']

                # Extract data from the DynamoDB JSON format
                user_id = new_image.get('UserID', {}).get('S')
                file_path = new_image.get('FilePath', {}).get('S')

                if not user_id or not file_path:
                    logger.warning(
                        "Record is missing UserID or FilePath: "
                        f"{json.dumps(new_image)}"
                    )
                    continue

                # Prepare the data for the downstream system
                downstream_payload = {
                    'user_id': user_id,
                    'file_path': file_path
                }

                # In a real-world scenario, you would send this payload
                # to another service. For this example, we'll just log it.
                logger.info(
                    "Processed data for downstream system: "
                    f"{json.dumps(downstream_payload)}"
                )
                processed_records.append(downstream_payload)

            except Exception as e:
                logger.error(f"Error processing record: {json.dumps(record)}")
                logger.error(f"Exception: {e}")
                # Depending on requirements, you might want to raise an
                # exception to halt the Step Functions execution.
                continue

    logger.info(f"Successfully processed {len(processed_records)} records.")

    # Return a summary of processed data. This is useful for SFN output.
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': (
                f'Successfully processed {len(processed_records)} records.'
            ),
            'processed_data': processed_records
        })
    }