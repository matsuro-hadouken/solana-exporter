### An Another Solana Exporter And Only

This repository hosts a solana-exporter, engineered to integrate seamlessly with Prometheus's `node-exporter` tool by leveraging its text file scraping capabilities for effective monitoring and alerting.

#### Installation Instructions

_While the default installation path is set to `/opt/solana-exporter`, it can be customized in `credentials.conf`._
_Ensure that whatever path you choose is owned by the `node-exporter` user for seamless operation._

```sh
# Requirements
apt install jq bc -y
```

Clone the Repository

```sh
# /opt/solana-exporter is recommended, however can be adjusted to anything
sudo git clone https://github.com/matsuro-hadouken/solana-exporter.git /opt/solana-exporter
```
Edit Configuration File
```sh
# This should not require any guidance
nano credentials.conf
```

Set Permissions

Determine the user account under which `node-exporter.service` is running:
```sh
# Ensure the process name is correct
ps -o user= -C node-exporter
```
Assign read/write permissins on `/opt/solana-exporter` directory:
```sh
# Replace <node-exporter-user> with the user found above
sudo chown -R <node-exporter-user>:<node-exporter-user> /opt/solana-exporter
```
Set Up Cron Job
  
Edit the cron jobs for the user that will run the exporter script:
```sh
# Replace <node_exporter_user> with the user running node-exporter
sudo -u <node_exporter_user> crontab -e
```
Add the following cron job _(execute the script every minute adjust the timeout as necessary)_:

```sh
# Runs the exporter script every minute with a 60 second timeout
* * * * * /usr/bin/timeout 60 /bin/bash -c 'cd /opt/solana-exporter && ./exporter.sh'
```

Save and exit

##### node-exporter.service example

Feature used: `--collector.textfile.directory`

```sh
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple

ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory=/opt/solana-exporter/files

[Install]
WantedBy=multi-user.target
```

#### FAQ

* Why create this exporter?
~ All existing Solana exporters were found to be outdated and no longer maintained, necessitating the development of a new solution.

* Why use Bash for the exporter script?
 ~ Bash was chosen for the exporter script to minimize dependencies; the only requirements are `jq` and `bc`, which are commonly available tools in UNIX-like environments. Everyone can easily review, edit and customize.

* Why utilize `node-exporter`?
 ~ `node-exporter` is widely used in many systems for monitoring metrics, making it a familiar tool for system administrators, thus it was the logical choice to ensure broad compatibility and ease of integration.

* What is special about this exporter?
 ~ This exporter is designed with modularity at its core. Each RPC call and function is encapsulated within its own separate file, allowing for straightforward modifications, deletions, or additions. This architecture facilitates easy contribution to the project, as well as simplifies maintenance, debugging, and code review. Additionally, the scraper is executed via a cron job with an adjustable interval, minimizing load on the validator RPC and allowing customization according to operator requirements.
