import boto3
import json
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

lattice = boto3.client('vpc-lattice')
secrets = boto3.client('secretsmanager')

def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event))
    
    # 1. Configuration
    network_id = os.environ['SERVICE_NETWORK_ID']
    secret_arn = os.environ['REGISTRY_SECRET_ARN']
    
    try:
        # 2. Read the Registry Secret (The "Phone Book")
        response = secrets.get_secret_value(SecretId=secret_arn)
        secret_string = response.get('SecretString')
        
        if not secret_string:
            logger.warning("Secret is empty.")
            return
            
        registry_data = json.loads(secret_string)
        service_id = registry_data.get('service_id')
        
        if not service_id:
            logger.error("No service_id found in secret payload.")
            return

        logger.info(f"Attempting to associate Service {service_id} with Network {network_id}")

        # 3. Check if already associated
        associations = lattice.list_service_network_service_associations(
            serviceNetworkIdentifier=network_id,
            serviceIdentifier=service_id
        )
        
        if associations['items']:
            logger.info(f"Service {service_id} is already associated.")
            return {
                'statusCode': 200,
                'body': 'Already associated'
            }

        # 4. Create Association
        lattice.create_service_network_service_association(
            serviceNetworkIdentifier=network_id,
            serviceIdentifier=service_id
        )
        
        logger.info(f"Successfully associated Service {service_id}")
        return {
            'statusCode': 200,
            'body': 'Association Created'
        }
        
    except Exception as e:
        logger.error(f"Error associating service: {str(e)}")
        raise e