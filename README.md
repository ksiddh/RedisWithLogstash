# RedisWithLogstash
This script will install Redis, Java and Logstash on Centos.
* Redis version: 3.2.8 running on port 6739 is the default but can be overwritten
* Java 1.8
* Logstash 2.3 -
* All important Redis performance counters are indexed uing the logstash filter script (included)

# Usage: bash rediswithlogstash.sh 3.2.8 6379

# Cavets :
  1. Installs Logstash 2.3. Please make the change in the script from Line 190 through 195 to install your version
  2. Logstash runs in the background and not as service (on my TODO list)
  3. Logstash filter runs redis-cli commands and indexes the data
  4. Please include your Kibana server to upload the output
   
   output {
      if "_grokparsefailure" not in [tags] {
       stdout { codec => rubydebug }
       elasticsearch {
        hosts => ""   // - HERE
        index => "rp-redis-%{type}-%{+YYYY.MM.dd}"
      }
    }

  5. Configures the Redis with cluster configurations so might be an overkill if you just want a single instance of Redis running
