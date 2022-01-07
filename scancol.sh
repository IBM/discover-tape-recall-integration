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
#   scancol.sh 
#
# Purpose:
#   updates a collection by scanning the data source, running the collection tagging policy and running the anti-tag policy
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
# temp file for policy json
tmpFile=./json.tmp

# sleep time while waiting for connection scan to complete. Total time = sleepTime * maxSleeps
sleepTime=1
maxSleeps=100

# policy state for the policy that removes the tags, can be Active or Inactive
polState=Active


#=====================================================================

# syntax function
syntax ()
{
  echo
  echo "Syntax:     scancol.sh connection-name collection-name"
  echo "  Parameter: "
  echo "    connection-name: name of the data source connection associated with the collection"
  echo "    collection-name: name of the collection to run the policy for"
  echo
}

#=====================================================================
# Main
#=====================================================================

# check arguments
if (( $# != 2 )); then
  echo "Error: invalid number of arguments"
  syntax
  exit 1
fi

# assign collection name
connName=$1
collName=$2

# obtain token
echo "Info: obtaining token for $sdUser@$sdServer"
token=""
token=$(echo `curl -k -u $sdUser:$sdPasswd https://$sdServer/auth/v1/token -I 2>/dev/null | grep X-Auth-Token |cut -f 2 -d":"`) 
if [[ -z $token ]]; then
  echo "Error: unable to obtain token, check the connection and username and password. "
  exit 1
fi

echo "--------------------------------------------------------------------------------------"

# check that data source exist and scan it
echo "Info: checking and scanning data source connection $connName"
itemExist=""
itemExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/connmgr/v1/connections/$connName 2>>/dev/null | grep -o '"name": "[^"]*' | grep -o '[^"]*$')
# echo "DEBUG: $itemExist"
if [[ -z $itemExist ]]; then
  echo "ERROR: Data source connection $connName does not exist."
  exit 1
else
  echo "Info: Data source connection $connName exists, scanning it."
  itemExist=""
  itemExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/connmgr/v1/scan/$connName -X POST -H "Content-type: application/json" 2>>/dev/null )
  if [[ "$itemExist" != "null" ]]; then
    echo "ERROR: failed to scan connection $connName, reason: $itemExist"
    exit 1
  else
    # check scan progress
    echo "Info: Monitoring scan run."
    itemExist=""
    run=1
    while [[ "$itemExist" != "Complete" && $run != $maxSleeps ]]; do
      sleep $sleepTime
      itemExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/connmgr/v1/scan/$connName 2>>/dev/null | grep -o '"status": "[^"]*' | grep -o '[^"]*$')
      echo "DEBUG: $run status: $itemExist"
      (( run = run +1 ))
    done
  fi
fi

echo "--------------------------------------------------------------------------------------"

# check if collection policy exist and run it. If this policy does not exist, this is not a problem. 
echo "Info: checking if collection policy exists."
collPolicy=$collName"_tagpolicy"
itemExist=""
itemExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/policyengine/v1/policies/$collPolicy 2>>/dev/null | grep -o '"pol_id": "[^"]*' | grep -o '[^"]*$')
# echo "DEBUG: $itemExist"
if [[ -z $itemExist ]]; then
  echo "Warning: Collection policy $collPolicy does not exist, proceeding with next step."
else
  echo "Info: Collection policy $collPolicy exists, starting it."
  itemExist=""
  itemExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/policyengine/v1/policies/$collPolicy/start -X POST 2>>/dev/null)
  if [[ "$itemExist" != "Accepted" ]]; then
    echo "ERROR: failed to start policy $collPolicy, reason: $itemExist"
    exit 1
  else
    echo "Info: Collection policy $collPolicy started, monitoring it"
    itemExist=""
    run=1
    while [[ "$itemExist" != "complete" && $run != $maxSleeps ]]; do
      sleep $sleepTime
      itemExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/policyengine/v1/policies/$collPolicy/status 2>>/dev/null  | grep -o '"status": "[^"]*' | grep -o '[^"]*$')
      echo "DEBUG: $run status: $itemExist"
      (( run = run +1 ))
    done
    if [[ "$itemExist" != "complete" || $run == $maxSleeps ]]; then
      echo "Error: Colletion policy  $collPolicy did not complete in time, exiting (status: $itemExist, loop count: $run)"
      exit 1
    fi
  fi
fi

echo "--------------------------------------------------------------------------------------"

# check if anti-tagging policy exists and run it
echo "Info: checking if policy to remove tag $tagName exists."
polName=$tagName"Not-policy"
pFilter=""
itemExist=""
itemExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/policyengine/v1/policies/$polName 2>>/dev/null | grep -o '"pol_id": "[^"]*' | grep -o '[^"]*$')
# echo "DEBUG: $itemExist"
if [[ -z $itemExist ]]; then
  echo "Info: policy $tagPolicy does not exist, creating one"
  # create policy filter to identify all records that have the recall-tag
  pFilter="collection in ('$collName') and $tagName='true' and state not like 'migrtd'"
#  echo "DEBUG: policy filter=$pFilter"

  # create policy json
  echo "{\
  \"pol_id\": \"$polName\", \
  \"pol_filter\": \"$pFilter\", \
  \"action_id\": \"AUTOTAG\", \
  \"action_params\": { \"tags\": {\"$tagName\": \"false\"} }, \
  \"pol_state\": \"$polState\", \
  \"schedule\": \"NOW\" \
  }" > $tmpFile
#  echo "DEBUG: $(cat $tmpFile)"

  # create policy, this will implicitely start the policy
  itemExist=""
  itemExist=$(curl -k  -H "Authorization: Bearer ${token}" https://$sdServer/policyengine/v1/policies -d@$tmpFile -X POST -H "Content-Type: application/json" 2>>/dev/null | grep "Policy '$polName' added")
  if [[ ! -z $itemExist ]]; then
    echo "Info: Policy $polName created, monitoring it."
  else
    echo "ERROR: failed to create policy $polName."
    exit 1
  fi
else
  # policy exists already, starting the anti-tagging policy
  echo "Info: Starting policy $polName to remove the tag $tagName."
  itemExist=""
  itemExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/policyengine/v1/policies/$polName/start -X POST 2>>/dev/null)
  if [[ "$itemExist" != "Accepted" ]]; then
    echo "ERROR: failed to start policy $polName, reason: $itemExist"
    exit 1
  else
    echo "Info: policy $polName started, monitoring it."
  fi  
fi
# monitoring the policy run
itemExist=""
run=1
while [[ "$itemExist" != "complete" && $run != $maxSleeps ]]; do
  sleep $sleepTime
  itemExist=$(curl -H "Authorization: Bearer ${token}" -k https://$sdServer/policyengine/v1/policies/$polName/status 2>>/dev/null  | grep -o '"status": "[^"]*' | grep -o '[^"]*$')
  echo "DEBUG: $run status: $itemExist"
  (( run = run +1 ))
done

if [[ "$itemExist" != "complete" || $run == $maxSleeps ]]; then
  echo "Error: Policy $polName did not complete in time, exiting (status: $itemExist, loop count: $run)"
  exit 1
fi


exit 0