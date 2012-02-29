#!/bin/bash

####################################################
# Script for rolling up a daily tarball from nightly
####################################################

####################################################
# Start of variables to set
####################################################

# Enable for verbose output - uncomment only while debugging!
set -x verbose

# Requires that the $CATALINA_HOME environment variable be set
# to identify the path to the Tomcat directory
ARCHIVE_DIR_NAME=`basename "$CATALINA_HOME"`

TARBALL_NAME=$ARCHIVE_DIR_NAME-`date +%Y-%m-%d`.tar.gz
DESTINATION_DIR=/var/www/html/builds

# The following paths are all relative to the Tomcat directory
NUXEO_CONF_FILE=bin/nuxeo.conf
NUXEO_SERVER_DIR=nuxeo-server
NUXEO_SERVER_PLUGINS_DIR=$NUXEO_SERVER_DIR/plugins
NUXEO_REPO_CONF_FILE=$NUXEO_SERVER_DIR/repos/default/default.xml
NUXEO_DEFAULT_REPO_CONF_FILE=$NUXEO_SERVER_DIR/config/default-repo-config.xml
NUXEO_DATASOURCES_CONF_FILE=$NUXEO_SERVER_DIR/config/datasources-config.xml
WEBAPPS_DIR=webapps
CSPACE_DS_FILE=$WEBAPPS_DIR/cspace-ds.xml
CSPACE_SERVICES_DIR=$WEBAPPS_DIR/cspace-services
WEB_INF_DIR=$CSPACE_SERVICES_DIR/WEB-INF
WEB_INF_CONTEXT_FILE=$WEB_INF_DIR/classes/context.xml
WEB_INF_PERSISTENCE_FILE=$WEB_INF_DIR/classes/META-INF/persistence.xml
META_INF_CONTEXT_FILE=$CSPACE_SERVICES_DIR/META-INF/context.xml
CATALINA_CONF_FILE=conf/Catalina/localhost/cspace-services.xml
TOMCAT_USERS_FILE=conf/tomcat-users.xml
CATALINA_LIB_DIR=lib
APP_LAYER_CONFIG_DIR=$CATALINA_LIB_DIR
CATALINA_LOG_DIR=logs
CATALINA_LOG_FILE=$CATALINA_LOG_DIR/catalina.out

####################################################
# End of variables to set
####################################################

DEFAULT_TMP_DIR=/tmp
TMP_DIR=

if [ -d $DEFAULT_TMP_DIR ] && [ -w $DEFAULT_TMP_DIR ]
  then
    TMP_DIR=$DEFAULT_TMP_DIR
elif [ "x$TMPDIR" != "x" ] && [ -d $TMPDIR ] && [ -w $TMPDIR ]
  then
    TMP_DIR=$TMPDIR
else
    echo "Could not find a suitable temporary directory"
    exit 1
fi

if [ "x$CATALINA_HOME" == "x" ]
  then
    echo "Environment variable CATALINA_HOME was empty; it must be set"
    exit 1
fi

echo "Making temporary copy of the Tomcat directory excluding selected items ..."

rsync -avz \
--exclude 'bin/tomcat.pid' --exclude 'conf/Catalina' --exclude 'cspace' --exclude 'data' \
--exclude 'logs/*' --exclude 'nuxeo-server/*' --exclude 'temp/*' --exclude 'templates' \
--exclude 'webapps/collectionspace' --exclude 'webapps/cspace-ui' --exclude 'webapps/cspace-services' \
--exclude 'webapps/cspace-services.war' --exclude 'work' \
$CATALINA_HOME $TMP_DIR

cd $TMP_DIR/$ARCHIVE_DIR_NAME || \
  { echo "Changing directories to $TMP_DIR/$ARCHIVE_DIR_NAME failed"; exit 1; }

echo "Cleaning up temporary copy of the Tomcat directory ..."

# Some of the files below are now excluded from being copied via rsync, so the
# attempted 'sed' replacement(s) targeting those files will harmlessly fail.
echo "Removing passwords from various config files ..."
sed -ri "s/nuxeo\.db\.(user|password)=.*/nuxeo.db.\\1=/" $NUXEO_CONF_FILE
# Note: using sed to edit XML is potentially brittle - ADR
sed -i 's#\(<password>\)[^<].*\(</password>\)#\1\2#g' $CSPACE_DS_FILE
# FIXME: We might look into acting on an array of file paths when
# performing identical replacements, with these three below ...
sed -i 's#\(<property name\=\"[Pp]assword\">\)[^<].*\(</property>\)#\1\2#g' $NUXEO_REPO_CONF_FILE
sed -i 's#\(<property name\=\"[Pp]assword\">\)[^<].*\(</property>\)#\1\2#g' $NUXEO_DEFAULT_REPO_CONF_FILE
sed -i 's#\(<property name\=\"[Pp]assword\">\)[^<].*\(</property>\)#\1\2#g' $NUXEO_DATASOURCES_CONF_FILE
# ... and with the identical replacements within this group as well:
sed -i 's#\(password\=\"\)[^\"]*\(\".*\)#\1\2#g' $WEB_INF_CONTEXT_FILE
sed -i 's#\(password\=\"\)[^\"]*\(\".*\)#\1\2#g' $WEB_INF_PERSISTENCE_FILE
sed -i 's#\(<property name\=\"hibernate.connection.password" value\=\"\)[^"].*\(\"/>\)#\1\2#g' \
  $WEB_INF_PERSISTENCE_FILE
sed -i 's#\(password\=\"\)[^\"]*\(\".*\)#\1\2#g' $META_INF_CONTEXT_FILE
sed -i 's#\(password\=\"\)[^\"]*\(\".*\)#\1\2#g' $CATALINA_CONF_FILE
sed -i 's#\(password\=\"\)[^\"]*\(\".*\)#\1\2#g' $TOMCAT_USERS_FILE
sed -i 's#\(roles\=\"\)[^\"]*\(\".*\)#\1\2#g' $TOMCAT_USERS_FILE
# Note that the above may fail if a double-quote char is part of the password

echo "Removing temporary directories ..."
rm -Rv temp[0-9a-f]*

echo "Creating Nuxeo server plugins directory ..."
if [ ! -e $NUXEO_SERVER_PLUGINS_DIR ]
  then
    mkdir $NUXEO_SERVER_PLUGINS_DIR  || \
      { echo "Creating $NUXEO_SERVER_PLUGINS_DIR directory failed"; exit 1; }
fi

if [ ! -e $CATALINA_LOG_FILE ]
  then
    echo "Creating empty Tomcat log file, required by catalina.sh ..."
    touch $CATALINA_LOG_FILE  || \
      { echo "Creating $CATALINA_LOG_FILE failed"; exit 1; }
fi

echo "Removing nightly-specific and other host-specific config files ..."
find $APP_LAYER_CONFIG_DIR -name nightly-settings.xml -delete
find $APP_LAYER_CONFIG_DIR -name local-settings.xml -delete

# The following command was tested with Fedora 10 and Ubuntu 11; other Linux distros and other
# Unix-like operating systems may have slight variations on 'execdir', etc.
echo "Copying settings.xml files to local-settings.xml for each tenant ..."
find $APP_LAYER_CONFIG_DIR/tenants -mindepth 1 -maxdepth 1 -type d \
  -execdir /bin/cp -p '{}'/settings.xml '{}'/local-settings.xml \;

echo "Removing services JAR files ..."
rm -Rv $CATALINA_LIB_DIR/cspace-services-authz.jar
rm -Rv $CATALINA_LIB_DIR/cspace-services-authn.jar

echo "Rolling up tarball ..."
cd $TMP_DIR
tar -zcf $TARBALL_NAME $ARCHIVE_DIR_NAME || \
  { echo "Creating tarball $ARCHIVE_DIR_NAME/$TARBALL_NAME failed"; exit 1; }

if [ -d $TMP_DIR/$ARCHIVE_DIR_NAME ] && [ -w $TMP_DIR/$ARCHIVE_DIR_NAME ]
  then
    echo "Removing temporary copy of the Tomcat directory ..."
    rm -R $TMP_DIR/$ARCHIVE_DIR_NAME || \
      { echo "Removing $TMP_DIR/$ARCHIVE_DIR_NAME failed"; } 
fi

if [ -d $DESTINATION_DIR ] && [ -w $DESTINATION_DIR ]
  then
    echo "Moving tarball to destination directory ..."
    mv $TARBALL_NAME $DESTINATION_DIR || \
      { echo "Moving tarball to $DESTINATION_DIR failed"; }
fi

if [ -e $DESTINATION_DIR/$TARBALL_NAME ]
  then
    echo "Deleting all similar tarballs in destination directory older than 7 days ..."
    find $DESTINATION_DIR -name "$ARCHIVE_DIR_NAME-*tar.gz" -mtime +7 -delete
fi



