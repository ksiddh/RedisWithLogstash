
#!/bin/bash
# RUN THIS SCRIPT ON EACH SERVERS:
# THIS SCRIPT WILL INSTALL REDIS AND MAKE IT "CLUSTER READY"

if [ "${#}" -ne "2" ]; then
  echo "usage: ${0} version port ip[,ip...]"
  exit 1
fi

#script parameters and defaults
VERSION="3.2.8"
REDIS_PORT=6379

VERSION=${1:-$VERSION}   # Defaults to VERSION 3.2.8
REDIS_PORT=${2:-$REDIS_PORT}   # Defaults to REDIS_PORT 6379

#############################################################################
log()
{
    echo "$1"
}
#############################################################################
install_redis()
{
	log "Installing Redis v${VERSION}"

	# Installing ruby gem for running ruby scripts
	gem install redis

	# Installing make, gcc and wget
	yum install -y make gcc wget

	wget http://download.redis.io/releases/redis-$VERSION.tar.gz
	tar xzf redis-$VERSION.tar.gz
	cd redis-$VERSION/

	cd deps/
	make hiredis lua jemalloc linenoise geohash

	cd ..
	make
	make install

	cd utils/
	echo | ./install_server.sh

	log "Redis v${VERSION} was downloaded, built and installed successfully"
}
#############################################################################
configure_redis()
{
	log "Configuration Redis..."

	cd /etc/redis/
	
	echo /etc/redis/${REDIS_PORT}.conf

	# Configure the general settings
	sed -i "s/^port.*$/port ${REDIS_PORT}/g" /etc/redis/${REDIS_PORT}.conf
	sed -i "s/^daemonize no$/daemonize yes/g" /etc/redis/${REDIS_PORT}.conf
	sed -i 's/^logfile ""/logfile \/var\/log\/redis.log/g' /etc/redis/${REDIS_PORT}.conf
	sed -i "s/^loglevel verbose$/loglevel notice/g" /etc/redis/${REDIS_PORT}.conf
	sed -i "s/^timeout 0$/timeout 30/g" /etc/redis/${REDIS_PORT}.conf

	log "Redis configuration was applied successfully"
	
	#System configuration
	# Set the vm.overcommit_memory to 1, this will avoid data to be truncated and fork will be successful
	sysctl vm.overcommit_memory=1
	echo "vm.overcommit_memory=1" >> /etc/sysctl.conf 
	
	# Change the maximum of backlog connections (defaults is 511)
	sysctl -w net.core.somaxconn=512
	# Make the change persistent (after restart of server)
	echo "net.core.somaxconn=512" >> /etc/sysctl.conf 

	# Disable transparent huge pages support (known to cause latency and memory access issues)
	echo never > /sys/kernel/mm/transparent_hugepage/enabled
	echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local
	chmod u+x /etc/rc.d/rc.local

	sysctl -w fs.file-max=100000
	
	# Restart sysctl:
	sudo sysctl -p /etc/sysctl.conf
}
#############################################################################
configure_redis_cluster()
{
	log "Configurating Redis for cluster mode ..."
	var=$(pwd)
	echo
	echo "Current Dir" $var

	cd /etc/redis/

	# Enable the AOF persistence
	sed -i "s/^appendonly no$/appendonly yes/g" /etc/redis/${REDIS_PORT}.conf
	# Set protected mode to no
	sed -i "s/^protected-mode yes$/protected-mode no/g" /etc/redis/${REDIS_PORT}.conf
	
	sed -i "s/^bind 127.0.0.1$/bind 0.0.0.0/g" /etc/redis/${REDIS_PORT}.conf
	
	# bind 0.0.0.0 instead of bind 127.0.0.1 IMPORTANT
	# Add cluster configuration
	echo "cluster-enabled yes" >> /etc/redis/${REDIS_PORT}.conf
	echo "cluster-node-timeout 5000" >> /etc/redis/${REDIS_PORT}.conf
	echo "cluster-config-file node.conf" >> /etc/redis/${REDIS_PORT}.conf
	
	# Add expiration policy
	#echo "maxmemory-policy allkeys-lru" >> /etc/redis/${REDIS_PORT}.conf
	log "Redis cluster configuration was applied successfully"	
}
##############################################################################
start_redis()
{
	# Start the Redis daemon
	if [ "`systemctl is-active redis_${REDIS_PORT}`" == "inactive" ] 
	then
		echo "redis_${REDIS_PORT} wasn't running so attempting restart"
		systemctl start redis_${REDIS_PORT}
		sleep 5
	else
		echo redis_${REDIS_PORT}" is currently running"
	fi
	
	if [ "`systemctl is-active redis_${REDIS_PORT}`" == "active" ] 
	then
		log "Redis daemon was started successfully"
	fi
}
##############################################################################
stop_redis()
{
	# Stop the Redis daemon
	systemctl stop redis_${REDIS_PORT}
	if [ "`systemctl is-active redis_${REDIS_PORT}`"!="active" ] 
	then
		echo redis_${REDIS_PORT}" is stopped"
	else
		log "Redis was not stopped successfully"
	fi
	
	# Start at boot
	log "Configuring Redis to start at boot ..."
	systemctl enable redis_6379.service
	chkconfig --level 345 redis_${REDIS_PORT} on
	
	log "Redis configured to start at boot"
}
##############################################################################
validate_redis_started()
{
	# Validate the Redis daemon
	systemctl status redis_${REDIS_PORT}
	if [ "`systemctl is-active redis_${REDIS_PORT}`"=="active" ] 
	then
		echo redis_${REDIS_PORT}" has successfully started"
	else
		log "Attempting to start the redis ..."
		systemctl start redis_${REDIS_PORT}
	fi
}
##############################################################################
##############################################################################
installJava()
{
	cd /opt/
	wget --no-cookies --no-check-certificate --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.tar.gz"
	  tar xzf jdk-8u131-linux-x64.tar.gz
	cd /opt/jdk1.8.0_131/
	alternatives --install /usr/bin/java java /opt/jdk1.8.0_131/bin/java 2
	echo 1 | alternatives --config java
	alternatives --install /usr/bin/jar jar /opt/jdk1.8.0_131/bin/jar 2
	alternatives --install /usr/bin/javac javac /opt/jdk1.8.0_131/bin/javac 2
	 alternatives --set jar /opt/jdk1.8.0_131/bin/jar
	 alternatives --set javac /opt/jdk1.8.0_131/bin/javac
	 cd ~
	java -version
	export JAVA_HOME=/opt/jdk1.8.0_131
	export JRE_HOME=/opt/jdk1.8.0_131/jre
	export PATH=$PATH:/opt/jdk1.8.0_131/bin:/opt/jdk1.8.0_131/jre/bin
}
######################################################################################
installLogstash()
{
rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch
cat << EOF > /etc/yum.repos.d/logstash.repo
[logstash-2.3]
name=Logstash repository for 2.3.x packages
baseurl=https://packages.elastic.co/logstash/2.3/centos
gpgcheck=1
gpgkey=https://packages.elastic.co/GPG-KEY-elasticsearch
enabled=1
EOF

yum -y install logstash
cat << EOD >  /etc/logstash/conf.d/logstash.conf
input {
      exec {
          command => "redis-cli client list | awk -F'[ =:]' '{print $4, $9}' | sort | uniq -c"
          interval => 300
          type => "clients-list"
        }
      exec {
          command => "redis-cli info server"
          interval => 300
          type => "server"
        }
      exec {
          command => "redis-cli cluster info"
          interval => 10
          type => "cluster"
        }
      exec {
        command => "redis-cli info clients"
        interval => 30
        type => "clients"
       }
      exec {
        command => "redis-cli info memory"
        interval => 10
        type => "memory"
       }
      exec {
        command => "redis-cli info cpu"
        interval => 10
        type => "cpu"
       }
      exec {
        command => "redis-cli info stats"
        interval => 300
        type => "stats"
       }
     exec {
        command => "redis-cli info commandstats"
        interval => 300
        type => "commandstats"
       }
     exec {
        command => "redis-cli info keyspace"
        interval => 10
        type => "keyspace"
       }
    exec {
        command => "redis-cli info replication"
        interval => 10
        type => "replication"
       }
    file {
      path => "/var/log/redis_6379.log"
      start_position => "beginning"
      type => "redis"
      add_field => { "role" => "redis" }
      }
    }
filter
    {
     split {

    }
    if [type] == "clients-list" {
           grok {
                match => [ "message", "%{NUMBER:Connections} %{IP:ClientIP} %{WORD:ClientName}"]
                }
                mutate {
                 remove_field => "message"
              }
          }
          if [type] == "redis" {
                grok {
                pattern =>  [ "%{POSINT:redis_pid}:[A-Z] %{MONTHDAY} %{MONTH} %{HOUR}:%{MINUTE}:%{SECOND} \* %{GREEDYDATA:redis_message}" ]
                }
                mutate {
                  remove_field => "message"
                }
                  mutate {
                        rename => [ "redis_message", "message" ]
                  }
          }
          if [type] == "keyspace" {
           ruby {
            code => "fields = event['message'].split(',')
            keys = fields[0].split(':')
            results = keys[1].split('=')
            event[results[0]] = results[1].to_f"
          }
        }
          else {
           ruby {
                 code => "fields = event['message'].split(':')
                 event[fields[0]] = fields[1].to_f"
                }
           }
    }
    output {
        if "_grokparsefailure" not in [tags] {
         stdout { codec => rubydebug }
         elasticsearch {
          hosts => ""
          index => "rp-redis-%{type}-%{+YYYY.MM.dd}"
        }
      }
    }
EOD

chmod +x /etc/init.d/logstash
systemctl enable logstash
systemctl start logstash
cd /opt/logstash/
ls -al
/opt/logstash/bin/logstash -f /etc/logstash/conf.d/logstash.conf &
}
######################################################################################
install_redis

configure_redis

configure_redis_cluster

sleep 5
stop_redis
sleep 5
start_redis
sleep 10
validate_redis_started
systemctl stop redis_${REDIS_PORT}
sleep 10
systemctl start redis_${REDIS_PORT}
sleep 10
systemctl status redis_${REDIS_PORT}
installJava
java -version
echo "Installing logstash..."
installLogstash 
