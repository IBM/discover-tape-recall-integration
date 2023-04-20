#!/bin/bash

################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2022 Nils Haustein                             				   #
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
#   ftag path-and-filename
#
# Purpose:
#   add a given tag to the specified file names
#
# Todo:
# - allow multiple path and filenames as input
# - curl error handling and messages
#
#=====================================================================

###
# source and check config parameters
configFile="configParms.rc"
if [[ ! -a $configFile ]]; then
  echo "ERROR: File $configFile does not exist."
  exit 1
else
  source ./$configFile
fi

if [[ -z $sdServer || -z $sdUser || -z $sdPasswd || -z $sdDb || -z $tagName || -z $tagValue ]]; then
  echo "ERROR: configuration paramters not set in file $configFile. Set config parameters and continue."
  echo -e "DEBUG: Current setting: \n\tsdServer=$sdServer, \n\tsdUser=$sdUser, \n\tsdPasswd=$sdPasswd, \n\tsdDb=$sdDb, \n\tcollection=$collName, \n\ttagName=$tagName, \n\ttagValue=$tagValue."
  exit 1
fi

# check collection name and compose the collection string for the query
if [[ -z "$collName" ]]; then
  collString=""
else
  collString="and collection in ($collName)"
fi

###
# constants
# policy name
polName=$tagName"-policy"
# policy state, can be Active or Inactive
polState=Active

# temp file name to be used for json request body constructs
tmpFile=./json.tmp

#=====================================================================

# syntax function
syntax ()
{
  echo
  echo "Syntax:     ftag.sh path-and-filename"
  echo "  Parameter: "
  echo "    path-and-filename: name of the file or set of files to set the tag for. "
  echo "                       Currently, it only supports a single path name or single path-and-file name. "
  echo
}

#=====================================================================
# Main
#=====================================================================

###
# check arguments
if (( $# != 1 )); then
  echo "Error: invalid number of arguments"
  syntax
  exit 1
fi

###
# assign and adjust path and filename
fName=""
pName=""
if [[ -f "$1" ]]; then
  # if this is a file, then assign the path and file name
  fName=$(basename "$1")
  pName="${1%/*}/"
  # echo "DEBUG: path=$pName, file=$fName"
else
  if [[ -d "$1" ]]; then
    # if this is a directory, then assign path name and set filename to %
    fName="%"
    # remove trailing / when required
    pName="${1%/}/%"
    # echo "DEBUG: path=$pName, file=$fName"
  else
    # if no file or directory check for wild cards
    endC=$(echo "${1: -1}")
    if [[ "$endC" = "%" || "$endC" = "*" ]]; then
      pName="${1::-1}%"
      fName="%"
      # echo "DEBUG: path=$pName, file=$fName"
    fi
  fi
fi

# Adjust print file name and path name, must have trailing /
fName="'"$fName"'"
pName="'"$pName"'"
# echo "DEBUG: path=$pName, file=$fName"


###
# obtain a token
# echo "Info: obtaining token for $sdUser@$sdServer"
token=""
####
# get the token looking for upper and lower case x-auth-token
####
token=$(curl -k -u $sdUser:$sdPasswd https://$sdServer/auth/v1/token -I 2>/dev/null | grep -i "x-auth-token" |cut -f 2 -d":")
if [[ -z $token ]]; then
  echo "Error: unable to obtain token, check the connection and username and password. "
  echo "Debug: getting token results in:"
  curl -k -u $sdUser:$sdPasswd https://$sdServer/auth/v1/token
  exit 1
fi
####
# remove trailing CR and NL from token
####
token=$(echo $token | tr -d '\r\n')


###
# check if tag $tagName exists and if not, then create it
echo "Info: checking if tag $tagName exists."
tagExist=""
tagExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/policyengine/v1/tags/$tagName 2>>/dev/null | grep -o '"tag": "[^"]*' | grep -o '[^"]*$')
# echo "DEBUG: tagExist=$tagExist"
if [[ ! -z $tagExist ]]; then
  echo "Info: tag $tagName exists."
else
  echo "Info: tag $tagName does not exist, creating this tag."
  echo "{\"tag\": \""$tagName"\", \"type\": \"Open\"}" > $tmpFile
  tagExist=""
  tagExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/policyengine/v1/tags -d@$tmpFile -X POST -H "Content-Type: application/json" 2>>/dev/null | grep "Tag $tagName added")
  
  if [[ ! -z $tagExist ]]; then
    echo "Info: tag $tagName created."
  else
    echo "ERROR: failed to create tag $tagName."
    exit 1
  fi
fi


###
# create AUTOTAG Policy for the provided file names
echo "Info: creating policy to tag the files"

# create policy filter, only applies to files where state is migrtd
pFilter="path like $pName and filename like $fName and state like 'migrtd' $collString"
# echo "DEBUG: policy filter=$pFilter"

# check if policy exists
tagExist=""
tagExist=$(curl -k  -H "Authorization: Bearer ${token}" https://$sdServer/policyengine/v1/policies/$polName 2>>/dev/null | grep -o '"pol_id": "[^"]*' | grep -o '[^"]*$')
if [[ ! -z $tagExist ]]; then
  # if policy exists, then update the filter and perhaps the tag value
  echo "Info: Policy $polName exists, updating the filter"
  echo "{\
  \"pol_id\": \"$polName\", \
  \"pol_filter\": \"$pFilter\", \
  \"pol_state\": \"$polState\", \
  \"action_params\": { \"tags\": {\"$tagName\": \"$tagValue\"} }, \
  \"schedule\": \"NOW\" \
  }" > $tmpFile
#  echo "DEBUG: $(cat $tmpFile)"

  # update policy
  tagExist=""
  tagExist=$(curl -k  -H "Authorization: Bearer ${token}" https://$sdServer/policyengine/v1/policies/$polName -d@$tmpFile -X PUT -H "Content-Type: application/json" 2>>/dev/null | grep "Policy '$polName' updated")
  if [[ ! -z $tagExist ]]; then
    echo "Info: Policy $polName updated."
  else
    echo "ERROR: failed to update policy $polName."
    exit 1
  fi
    
else
  # if policy does not exist, then create it
  echo "Info: creating policy $polName"
  # create policy
  echo "{\
  \"pol_id\": \"$polName\", \
  \"pol_filter\": \"$pFilter\", \
  \"action_id\": \"AUTOTAG\", \
  \"action_params\": { \"tags\": {\"$tagName\": \"$tagValue\"} }, \
  \"pol_state\": \"$polState\", \
  \"schedule\": \"NOW\" \
  }" > $tmpFile
#  echo "DEBUG: $(cat $tmpFile)"

  # create policy
  tagExist=""
  tagExist=$(curl -k  -H "Authorization: Bearer ${token}" https://$sdServer/policyengine/v1/policies -d@$tmpFile -X POST -H "Content-Type: application/json" 2>>/dev/null | grep "Policy '$polName' added")
  if [[ ! -z $tagExist ]]; then
    echo "Info: Policy $polName created."
  else
    echo "ERROR: failed to create policy $polName."
    exit 1
  fi
fi

# remove the temp file
rm -f $tmpFile


exit 0


