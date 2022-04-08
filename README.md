# docspell-debian
How to install the [Personal Document Manager Docspell](https://github.com/eikek/docspell) on Debian without Docker. I decided to go this route because a docspell installation is potentially living for many years, so I would like to remove any additional layer of complexity.

# Prerequisites

For this howto, I assume you already have Debian 11 (Bullseye) installed either on Bare Metal or in a VM, for example in Proxmox. I didn't test the installation within a Linux Container, but I assume that should work as well. The installation was performed with [**Release 0.32**](https://github.com/eikek/docspell/releases/)

I have assigned 4 Cores and 4GB Ram to this VM which seems to be more than enough for a full-featured installation with a few thousand documents.

## Basic Installation

First, install the base packages.

```
apt update && apt full-upgrade
apt install curl htop zip gnupg2 ca-certificates sudo
apt install default-jdk apt-transport-https wget -y
apt install ghostscript tesseract-ocr tesseract-ocr-deu tesseract-ocr-eng unpaper unoconv wkhtmltopdf ocrmypdf
```

## SOLR Installation (Optional)

Docspell works fine without fulltext-search - however it's very helpful when your document storage grows.

You might want to look for a newer version of Apache SOLR at https://downloads.apache.org/lucene/solr/ - the currently latest version 8.11.1 works very well.

```
cd /root/
wget https://downloads.apache.org/lucene/solr/8.11.1/solr-8.11.1.tgz
tar xzf solr-8.11.1.tgz
bash solr-8.11.1/bin/install_solr_service.sh solr-8.11.1.tgz
```

This will install SOLR. Please check the installation success by monitoring the output of 

```systemctl start solr```

We'll leave SOLR alone for now and will return later to create the docspell core.

## Postgresql Installation

PostgreSQL is my preferred database for docspell because of the amount of documents I am storing in it. Other database types are also available, please have a look at the docspell Repo for more information.

```
curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ bullseye-pgdg main" > /etc/apt/sources.list.d/postgresql.list'
apt update && apt full-upgrade
apt install postgresql-14
```
### PostgreSQL Configuration

In the following section, you need to replace YOURPASSWORD with your own. I am using ```docspell``` as the database owner and ```docspelldb``` as the database name:

Loginto the Postgres user
```
$ sudo su -
root@debian-11:~# su - postgres
postgres@debian-11:~$ psql
psql (14.1 (Debian 14.1-1.pgdg110+1)) 
Type "help" for help.
```

Create the user docspell
```
postgres=# CREATE USER docspell
postgres-# WITH SUPERUSER CREATEDB CREATEROLE
postgres-# PASSWORD 'YOURPASSWORD';
exit
```

Create the database and connect to it
```
psql postgres
CREATE DATABASE docspelldb WITH OWNER docspell;
CREATE DATABASE
postgres=# \connect docspelldb;
You are now connected to database "docspelldb" as user "docspell".
docspelldb=#
\q
```

Dont forget to logout from the postgres user ("exit") until you are back to the root user and make sure the database is started with the system:

```
systemctl enable postgresql
```
### Set up a scheduled database setup

Because the database also holds the PDFs, I strongly recommend to create an automated backup. Copy the file postgres-backup.sh to /opt and edit it to your needs. As this stores the backup in a local folder, make sure to have a way to automatically transfer them to your backup storage.

Then create a cronjob. Mine for example runs every night at 1.11. 

``` 
crontab -u postgres -e
```

add the following line to the end:

```
11 1 * * * sh /opt/postgres-backup.sh
```

For the first time, i'd suggest to run the script manually to get an idea of the backup size (mine is several GB every night) so you can plan to avoid running out of disk space.

## Docspell installation

Make sure to use updated links below if there is a new release.

```
cd /tmp
wget https://github.com/eikek/docspell/releases/download/v0.32.0/docspell-joex_0.32.0_all.deb
wget https://github.com/eikek/docspell/releases/download/v0.32.0/docspell-restserver_0.32.0_all.deb
dpki -i docspell*
```
At this point, doscpell itself is installed, but we'll also need the commandline tool dsc:
```
wget https://github.com/docspell/dsc/releases/download/v0.7.0/dsc_amd64-musl-0.7.0
mv dsc_amd* dsc
chmod +x dsc
mv dsc /usr/bin
```
Now dsc is available from the command line.

## Docspell configuration

You'll find links to the configuration files for docspell-restserver (which includes the web interface) and docspell-joex (which handles the backend tasks like OCR and PDF creation) in ```/etc/docspell-restserver``` and ```/etc/docspell-joex```. The multiple configuration options are explained here: https://docspell.org/docs/configure/

You can use the files linked here, but don't forget to update the passwords in them.

Link to docspell-restserver example
Link to docsspell-joex example

After editing the configuration files to your needs, it's time to start the docspell services:

```
systemctl start docspell-resterver
systemctl enable docspell-restserver
systemctl start docspell-joex
systemctl enable docspell-joex
```

## Enable SOLR fulltext search

We need to create a SOLR core and make it available in Docspell:

```
su solr -c '/opt/solr-8.11.1/bin/solr create -c docspell'
curl -XPOST -H "Docspell-Admin-Secret: my secret" http://localhost:7880/api/v1/admin/fts/reIndexAll

```

## Nginx Reverse Proxy

apt install nginx

Link to nginx example config

