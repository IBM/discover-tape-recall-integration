#!/bin/bash

################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2020 Nils Haustein                             				   #
#                                                                              #
# Permission is hereby granted, free of charge, to any person obtaining a copy #
# of this software and associated documentation files (the "Software"), to deal#
# in the Software without restriction, including without limitation the rights #
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell    #
# copies of the Software, and to permit persons to whom the Software is        #
# furnished to do so, subject to the following conditions:                     #
#                                                                              #
# The above copyright notice and this permission notice shall be included in   #
# all copies or substantial portions of the Software.                          #
#                                                                              #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR   #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,     #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE  #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER       #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,#
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE#
# SOFTWARE.                                                                    #
################################################################################

# Program:
#   recallTagged.sh 
#
# Purpose:
#   recall files that are migrated and tagged with a given tag in a given collection
#
# Todo:
# - curl error handling and messages
#
#=====================================================================


# source and check config parameters
configFile="configParms.rc"
if [[ ! -a $configFile ]]; then
  echo "ERROR: File $configFile does not exist."
  exit 1
else
  source ./$configFile
fi

if [[ -z $sdServer || -z $sdUser || -z $sdPasswd || -z $sdDB || -z $collName || -z $tagName || -z $tagValue ]]; then
  echo "Info: Checking configuration parameters."
else
  echo "ERROR: configuration paramters not set in file $configFile. Set config parameters and continue."
  echo "DEBUG: $sdServer, $sdUser, $sdPasswd, $sdDB, $collName, $tagName, $tagValue."
  exit 1
fi

# constants
# temp file including the path and file names of selected files
recFile=./reclist.tmp

# recall command
recCmd="/opt/ibm/ltfsee/bin/eeadm recall "

#=====================================================================

# syntax function
syntax ()
{
  echo
  echo "Syntax:     recall-tagged.sh collection-name"
  echo "  Parameter: "
  echo "    collection-name: Spectrum Discover collection name to search and recall tagged files for. "
  echo "                     all: recall tagged files for all collections."
  echo "                     collection: name of the collection to recall files for."
  echo
}

#=====================================================================
# Main
#=====================================================================

# check arguments
if (( $# != 1 )); then
  echo "Error: invalid number of arguments"
  syntax
  exit 1
fi

# assign collection name
collName=""
if [[ "$1" = "all" ]]; then
  echo "Info: setting collection name to all collections."
  collName="select collection from $sdDb"
else
  collName="'$1'"
fi

# obtain token
echo "Info: obtaining token for $sdUser@$sdServer"
token=""
token=$(echo `curl -k -u $sdUser:$sdPasswd https://$sdServer/auth/v1/token -I 2>/dev/null | grep X-Auth-Token |cut -f 2 -d":"`) 
if [[ -z $token ]]; then
  echo "Error: unable to obtain token, check the connection and username and password. "
  exit 1
fi

# perform query and store file list
echo "Info: obtaining file list from Spectrum Discover."
rm -f $recFile
# echo "DEBUG: select statement: select path, filename from $sdDb where collection in ($collName) and $tagName='$tagValue' and state='migrtd'"
curl -k -H "Authorization: Bearer ${token}" https://$sdServer/db2whrest/v1/sql_query -X POST -d"select path, filename from $sdDb where collection in ($collName) and $tagName='$tagValue' and state='migrtd'" 2>/dev/null | while read line; 
do 
  pn=$(echo $line | cut -d'"' -f 2) 
  fn=$(echo $line | cut -d'"' -f 4)
  echo "$pn$fn" >> $recFile
done

# run recall
if [[ -f $recFile ]]; then
  num=$(wc -l $recFile | cut -d' ' -f1)
  if (( num > 0 )); then
    echo "Info: recalling $num files."
#    echo "DEBUG: $recCmd $recFile"
    $recCmd $recFile
  else
    echo "Info: no files must be recalled."
  fi
else
  echo "Info: no files must be recalled."
fi

exit 0
