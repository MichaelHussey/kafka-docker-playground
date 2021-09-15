#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose-cloud-to-cloud.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

#############
if [ -f ${DIR}/env.source ]
then
     source ${DIR}/env.source
else
     logerror "ERROR: ${DIR}/env.source does not exist, create it with following config parameters"

     logerror 'BOOTSTRAP_SERVERS_SRC="CLUSTER.REGION.CLOUD.confluent.cloud:9092"'
     logerror 'CLOUD_KEY_SRC="xxx"'
     logerror 'CLOUD_SECRET_SRC="xxx"'
     logerror 'SASL_JAAS_CONFIG_SRC="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$CLOUD_KEY_SRC\" password=\"$CLOUD_SECRET_SRC\";"'
     logerror 'SCHEMA_REGISTRY_URL_SRC="https://xxx.confluent.cloud"'
     logerror 'SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC="xxxx:xxxx"'

     exit 1
fi
#############

# log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
KAFKA_SRC_TOPIC=topic-xml
KAFKA_DST_TOPIC=topic-xml-json
set +e
create_topic $KAFKA_SRC_TOPIC --partitions 1
set -e


log "Creating MQTT Source connector"
generate_post_data()
{
  cat <<EOF
     {
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
          "value.converter.schema.registry.url":"$SCHEMA_REGISTRY_URL",
          "value.converter.basic.auth.credentials.source":"USER_INFO",
          "value.converter.basic.auth.user.info":"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-demo-to-travis",
          "src.kafka.ssl.endpoint.identification.algorithm":"https",
          "src.kafka.bootstrap.servers": "$BOOTSTRAP_SERVERS_SRC",
          "src.kafka.security.protocol" : "SASL_SSL",
          "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${CLOUD_KEY_SRC}\" password=\"${CLOUD_SECRET_SRC}\";",
          "src.kafka.sasl.mechanism":"PLAIN",
          "src.kafka.request.timeout.ms":"20000",
          "src.kafka.retry.backoff.ms":"500",
          "dest.kafka.ssl.endpoint.identification.algorithm":"https",
          "dest.kafka.bootstrap.servers": "$BOOTSTRAP_SERVERS",
          "dest.kafka.security.protocol" : "SASL_SSL",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${CLOUD_KEY}\" password=\"${CLOUD_SECRET}\";",
          "dest.kafka.sasl.mechanism":"PLAIN",
          "dest.kafka.request.timeout.ms":"20000",
          "dest.kafka.retry.backoff.ms":"500",
          "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
          "confluent.topic.sasl.mechanism" : "PLAIN",
          "confluent.topic.bootstrap.servers": "$BOOTSTRAP_SERVERS_SRC",
          "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${CLOUD_KEY_SRC}\" password=\"${CLOUD_SECRET_SRC}\";",
          "confluent.topic.security.protocol" : "SASL_SSL",
          "confluent.topic.replication.factor": "3",
          "provenance.header.enable": true,
          "topic.whitelist": "$KAFKA_SRC_TOPIC",
          "topic.rename.format": "\${topic}-json",
          "topic.auto.create": "true",
          "transforms": "xml",
          "transforms.xml.type": "com.github.jcustenborder.kafka.connect.transform.xml.FromXml\$Value",
          "transforms.xml.schema.path": "file:/schema/note.xsd"
     }
EOF
}
curl -X PUT \
     -H "Content-Type: application/json" \
     --data "$(generate_post_data)" \
     http://localhost:8083/connectors/replicate-xml2json/config | jq .

sleep 5

log "Send XML message to $KAFKA_SRC_TOPIC"

# Create a client property file
printf "bootstrap.servers=$BOOTSTRAP_SERVERS_SRC\n" > ${DIR}/client.properties
printf "ssl.endpoint.identification.algorithm=https\n" >> ${DIR}/client.properties
printf "security.protocol=SASL_SSL\n" >> ${DIR}/client.properties
printf "sasl.mechanism=PLAIN\n" >> ${DIR}/client.properties
printf "sasl.jaas.config=$SASL_JAAS_CONFIG\n" >> ${DIR}/client.properties 

docker exec -i -e BOOTSTRAP_SERVERS_SRC="$BOOTSTRAP_SERVERS_SRC" -e KAFKA_TOPIC="$KAFKA_SRC_TOPIC" connect bash -c 'kafka-console-producer --broker-list $BOOTSTRAP_SERVERS_SRC --producer.config /client.properties --topic $KAFKA_TOPIC' << EOF
<note> <to>Tove</to> <from>Jani</from> <heading>Reminder 01</heading> <body>Don't forget me this weekend!</body> </note>
EOF

log "Verify we have received the data in $KAFKA_SRC_TOPIC.replica topic"
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS"  -e KAFKA_TOPIC="$KAFKA_DST_TOPIC" connect bash -c 'kafka-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS --consumer.config /client.properties --topic $KAFKA_TOPIC --from-beginning --max-messages 1'