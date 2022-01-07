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
#   lstag path-and-filename
#
# Purpose:
#   display size, migration state, tag value and path and file names
#
# Todo:
# - allow multiple path and filenames as input
# - error messages
#
#=====================================================================

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


# syntax function
syntax ()
{
  echo
  echo "Syntax:     lstag.sh path-and-filename"
  echo "  Parameter: "
  echo "    path-and-filename: name of the file or set of files to display the status and tag for. "
  echo "                       Currently, it only supports a single path name or single path-and-file name. "
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

# assign and adjust path and filename
fName=""
pName=""
if [[ -f "$1" ]]; then
#  echo "DEBUG: $1 is a file."
  fName=$(basename $1)
  pName=${1%/*}
fi

if [[ -d "$1" ]]; then
#  echo "DEBUG: $1 is a directory."
  fName="%"
  # remove trailing / when required
  pName=${1%/}
fi

# Adjust print file name and path name, must have trailing /
fName="'"$fName"'"
pName="'"$pName"/'"
# echo "DEBUG: path=$pName, file=$fName"

# check collection name, if empty embed all collections
if [[ -z "$collName" ]]; then
  collName="select collection from $sdDb"
fi

# start the query
# echo "Info: obtaining token for $sdUser@$sdServer"
token=""
token=$(echo `curl -k -u $sdUser:$sdPasswd https://$sdServer/auth/v1/token -I 2>/dev/null | grep X-Auth-Token |cut -f 2 -d":"`) 

if [[ -z $token ]]; then
  echo "Error: unable to obtain token, check the connection and username and password. "
  exit 1
fi


# perform query
# print the header
printf "%-10s %-12s %-12s %-20s %s\n" "State" "Size" "$tagName" "Collection" "Path-and-Filename"
printf "%-10s %-12s %-12s %-20s %s\n" "--------" "--------" "--------" "----------" "-------------------------------------------------------------"
# run query and display results
# echo "DEBUG: select statement: select path, filename, size, state, collection, $tagName from $sdDb where path like $pName and filename like $fName and collection in ($collName)"
# curl -k -H "Authorization: Bearer ${token}" https://$sdServer/db2whrest/v1/sql_query -X POST -d"select path, filename, size, state, collection, $tagName from $sdDb where path like $pName and filename like $fName and collection in ($collName)" 2>/dev/null 

curl -k -H "Authorization: Bearer ${token}" https://$sdServer/db2whrest/v1/sql_query -X POST -d"select path, filename, size, state, collection, $tagName from $sdDb where path like $pName and filename like $fName and collection in ($collName)" 2>/dev/null | while read line; 
do 
  pn=$(echo $line | cut -d'"' -f 2) 
  fn=$(echo $line | cut -d'"' -f 4)
  st=$(echo $line | cut -d',' -f 4)
  sz=$(echo $line | cut -d'"' -f 6)
  col=$(echo $line | cut -d'"' -f 8)
  tv=$(echo $line | cut -d'"' -f 10)
  if [[ -z $tv ]]; then
    tv=null
  fi
  # echo "DEBUG: $sz, $st, $col, $tv $pn, $fn"
  printf "%-10s %-12s %-12s %-20s %s\n" $sz $st $tv $col $pn$fn
done

exit 0