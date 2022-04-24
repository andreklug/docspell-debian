# docspell-debian
How to install the [Personal Document Manager Docspell](https://github.com/eikek/docspell) on Debian without Docker. I decided to go this route because a docspell installation is potentially living for many years, so I would like to remove any additional layer of complexity.

# Prerequisites

For this howto, I assume you already have Debian 11 (Bullseye) installed either on Bare Metal or in a VM, for example in Proxmox. I didn't test the installation within a Linux Container, but I assume that should work as well. The installation was performed with [**Release 0.32**](https://github.com/eikek/docspell/releases/)

I have assigned 4 Cores and 6GB Ram to this VM which seems to be more than enough for a full-featured installation with a few thousand documents.

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

```
systemctl start solr
```

We'll leave SOLR alone for now and will return later to create the docspell core.

*Note: From version 0.34.0 it is also possible to use PostgreSQL as fulltext search engine. This is not described here, the main documention has [some instructions](https://docspell.org/docs/configure/fulltext-search/)*

## Enable SOLR fulltext search

We need to create a SOLR core and make it available in Docspell:

```
su solr -c '/opt/solr-8.11.1/bin/solr create -c docspell'
```


## PostgreSQL Installation

PostgreSQL is my preferred database for docspell because of the amount of documents I am storing in it. Other database types are also available, please have a look at the docspell Repo for more information.

```
curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ bullseye-pgdg main" > /etc/apt/sources.list.d/postgresql.list'
apt update && apt full-upgrade
apt install postgresql-14
```

### PostgreSQL Configuration

In the following section, you need to replace YOURPASSWORD with your own. I am using `docspell` as the database owner and `docspelldb` as the database name:

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
```

Create the database and (as a test) connect to it
```
postgres=# CREATE DATABASE docspelldb WITH OWNER docspell;
postgres=# \connect docspelldb;
You are now connected to database "docspelldb" as user "docspell".
docspelldb=# \q
```

Dont forget to logout from the postgres user ("exit") until you are back to the root user and make sure the database is started with the system:

```
systemctl enable postgresql
```

### Set up a scheduled database backup

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

Make sure to use updated links below if there is a new release. The latest release is [here](https://github.com/eikek/docspell/releases/latest).

Docspell consists of two components, the restserver and the joex (job executor). Both are configured separately, but also share some configuration values (e.g. the database and full-text search). The restserver is providing the user interface and allows to query all data. The joex is running all the long running tasks in the background.

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
The latest release of dsc can be found [here](https://github.com/docspell/dsc/releases/latest). Now dsc is available from the command line.


## Docspell configuration

You'll find links to the configuration files for docspell-restserver (which includes the web interface) and docspell-joex (which handles the backend tasks like OCR and PDF creation) in ```/etc/docspell-restserver``` and ```/etc/docspell-joex```. The multiple configuration options are explained here: https://docspell.org/docs/configure/

You can use the files linked here, but don't forget to update the passwords in them.

*Note: You need to enable full-text search in both config files, as it is disabled by default. Also the database connection should be configured. The default values can be seen [here](https://docspell.org/docs/configure/main/#default-config).*


After editing the configuration files to your needs, it's time to start the docspell services:

```
systemctl start docspell-restserver
systemctl enable docspell-restserver
systemctl start docspell-joex
systemctl enable docspell-joex
```

You should be able to reach the web interface at <http://localhost:7880>.

When you create a new account, use the exact same name for "collective" and "username". For more information on this, please see [here](https://docspell.org/docs/#collective).

The logs can be inspected via `journalctl`, for example:
```
journalctl -efu docspell-restserver  #or
journalctl -efu docspell-joex
```

## Recreate fulltext index

In some situations it can be necessary to re-create the fulltext index, for example if you enable full-text search after running docspel without. It is therefore not necessary on new installations. 

The following command is requesting docspell to re-index all data. The `dsc` tool that has been installed above is used for this:

```
dsc -d http://localhost:7880 admin -a 'my admin secret' recreate-index
```

The admin secret must be set in the [configuration file](https://docspell.org/docs/configure/admin-endpoint/) (which requires a restart). 

## Nginx Reverse Proxy
```
apt install nginx
openssl dhparam -out /etc/nginx/dhparam.pem 2048
```
The second command creates the dhparam.pem file which is referenced in the config. It will run for several minutes, be patient ;) 

Replace the /etc/nginx/sites-available/default with the content of the attached nginx-default example file.  As I am using my own PKI infrastructure to create and manage certificates, you must edit lines 27 - 29 accoring to your setup.

