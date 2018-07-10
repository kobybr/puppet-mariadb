#!/bin/bash
#
# Author: Brad Koby

osfamily=$(facter -p osfamily)
exitcode=0

if ((${EUID:-0} || "$(id -u)")); then
  echo "Must run as root"
  exit 1
fi

# Save current puppet agent state
[ -f `$puppet_path/puppet agent --genconfig|grep agent_disabled_lockfile| cut -d "=" -f2` ] && puppet_currentState='disabled' || puppet_currentState='enabled'

while true
do

  if [ "$puppet_currentState" = "enabled" ]; then
    echo "Disabling puppet agent..."
    $puppet_path/puppet agent --disable "Disabled while updating mariadb."
    if [ "$?" -ne 0 ]; then
      echo "Unable to disable puppet agent, exiting."
      exitcode=1
      break
    fi
  fi

  # Save current mariadb service state
  serviceState=`$puppet_path/puppet resource service $service_name|grep ensure|awk -F"'" '{$0=$2}1'`

  echo "Stopping $service_name service..."
  $puppet_path/puppet resource service $service_name ensure=stopped

  # Check if puppet agent is currently executing
  if [ -f `$puppet_path/puppet agent --genconfig|grep agent_catalog_run.lockfile| cut -d "=" -f2` ]; then
    echo "Puppet agent currently running, exiting..."
    exitcode=1
    break
  fi

    case $osfamily in
      RedHat)

        mariadb_packages=`rpm -qa|grep -i '^MariaDB-'|cut -d'-' -f1-2|tr '\n' ' '`

        yum clean expire-cache

        if $removecurrent ; then
          echo "Removing ${mariadb_packages}and dependancies"
          yum remove -y $mariadb_packages

          echo "Installing packages $mariadb_packages"
          yum install -y $mariadb_packages
        else
          echo "Updating packages $mariadb_packages"
          yum upgrade -y $mariadb_packages
        fi

        if [ "$?" -ne 0 ]; then
           echo "Installation completed with errors"
           exitcode=1
           break
        fi

      ;;
      Debian)

        mariadb_packages=`rpm -qa|grep -i '^mariaDB-'|cut -d'-' -f1-2|tr '\n' ' '`

        if $removecurrent ; then
          echo "Removing ${mariadb_packages}and dependancies"
          apt-get remove $mariadb_packages

          echo "Installing packages $mariadb_packages"
          apt install $mariadb_packages
        else
          echo "Updating packages $mariadb_packages"
          apt upgrade $mariadb_packages
        fi
      ;;
    esac

  break

done

# Start new cluster
if $galera_new_cluster ; then
  galera_new_cluster
elif [ "$serviceState" = "running" ]; then       # Only enable if this was the previous state
  $puppet_path/puppet resource service $service_name ensure=running
fi

# Only enable if this was the previous state
if [ "$puppet_currentState" = "enabled" ]; then
  $puppet_path/puppet agent --enable
  if [ "$?" -ne 0 ]; then
    echo "Unable to enable puppet agent, exiting."
    exitcode=1
  fi
fi

#Run mysql_upgrade
mysql_upgrade
if [ "$?" -ne 0 ]; then
  exitcode=1
fi

exit $exitcode
