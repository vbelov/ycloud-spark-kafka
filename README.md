# Example of consuming Kafka messages with Spark

Provision Kafka cluster, Data Proc cluster and some auxiliary resources with terraform:
```bash
terraform init
terraform apply -var-file path/to/your/var/file.tfvars
```

Depending on settings of your cloud last command may fail to create Data Proc cluster with error message
"NAT should be enabled on the subnet of the main subcluster". Regardless of whether this has happened or not, 
the next step is to enable egress NAT for subnet within AZ ru-central1-a via web console.
Next last command may be repeated.

Produce some messages to Kafka cluster:
```bash
./populate_kafka.sh
```

Run spark application:
```bash
export $(cat populate_kafka_env.list | xargs)
yc dataproc job create-pyspark \
  --cluster-name=spark-kafka \
  --name "calculate num messages" \
  --properties spark.submit.deployMode=client \
  --main-python-file-uri "s3a://$BUCKET_NAME/spark-application.py" \
  --args $BOOTSTRAP_SERVERS \
  --args $ADMIN_PASSWORD
```

Output of last command will contain number of messages within Kafka topic that satisfy condition within Spark application.
