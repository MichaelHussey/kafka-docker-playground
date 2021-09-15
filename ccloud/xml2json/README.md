# Converting XML to JSON using Replicator (with Confluent Cloud)

## This is based on the Cloud to Cloud Replicator examples with JSONSchemaConverter

This example produces an XML message to the topic `topic-xml` and uses the schema `schema/note.xsd` in an SMT to convert it to JSON. It registers the JSON schema to Schema Registry.

### How to run


```
$ ./xml2json.sh
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
