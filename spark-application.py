import sys

from pyspark.sql import SparkSession
from pyspark.sql.functions import col


bootstrap_servers = sys.argv[1]
admin_password = sys.argv[2]
jaas_config = f"org.apache.kafka.common.security.scram.ScramLoginModule required username=\"admin\" password=\"{admin_password}\";"
spark = SparkSession.builder.getOrCreate()

df = spark.read.format("kafka") \
    .option("kafka.bootstrap.servers", bootstrap_servers) \
    .option("kafka.security.protocol", "SASL_SSL") \
    .option("kafka.sasl.mechanism", "SCRAM-SHA-512") \
    .option("kafka.sasl.jaas.config", jaas_config) \
    .option("subscribe", "topic1") \
    .option("startingOffsets", """{"topic1":{"0":50,"1":50,"2":50}}""") \
    .load() \
    .selectExpr("CAST(value AS STRING)")\
    .where(col("value").isNotNull())

print(f"Number of messages: {df.count()}")
