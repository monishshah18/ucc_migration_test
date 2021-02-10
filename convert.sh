#! /bin/bash
#Splunk_TA_New_Relic

# Did the user specify the directory?   If not , get it now
if [ $# -eq 0 ]
  then
    read -p 'Enter the directory for the AOB TA (in this folder): ' AOB_TA_DIR
  else
    AOB_TA_DIR="$1"
fi

### Check if the directory exists, if not, exit ###
if [ ! -d "$AOB_TA_DIR" ] 
then
    echo "Directory /$AOB_TA_DIR DOES NOT exists." 
    exit 9999 # die with error code 9999
fi

#remove any traiing / from the dir name
AOB_TA_DIR=${1%/}
AOB_TA_DIR_lowercase=$(echo "$AOB_TA_DIR" | tr '[:upper:]' '[:lower:]')

# create a 'package' directory and move all files from the existing TA into it
if [ -d ./package ]
then
    echo removing existing ./package directory
    rm -rf ./package
fi

echo Creating a new ./pakcage directory for your new ucc-based TA 
mkdir package
cp -r ./$AOB_TA_DIR/ ./package

#copy the existing globalConfig.json file to the root directory
cp ./package/appserver/static/js/build/globalConfig.json .

# ucc-based TA's will require teh splunktaucclib library to be included in the build.  Add it here.
mkdir ./package/lib
echo splunktaucclib==4.0.7 > ./package/lib/requirements.txt

# identify any additional imported libraries and add them to the requirements.txt file 
cat ./package/bin/input_module_*.py | grep import | grep -Ev '(import os|import sys|import time|import datetime|import json, re)' | sed -n 's/.*import //p' | xargs -L1 | sort | uniq >>./package/lib/requirements.txt

# create a new python file for each Input in the bin directory
cd ./package/bin
for OUTPUT in $(ls input_module_*.py | xargs -L1 | awk -F"input_module_" '{print $2}')
do
    echo Processing input named:   $OUTPUT
    # get the scheme generated by AOB (from MOD_INPUT_NAME.py)
    SCHEME=$(sed -n '/^    def get_scheme(self):/,/^        return scheme/p' $OUTPUT)

    # update the constructor from AOB to ucc
    SCHEME=$(echo "$SCHEME" | sed 's/scheme = super(ModInputnew_relic_account_input, self).get_scheme()/scheme = smi.Scheme("MY_TA_SCHEME")/g')
    #echo "$SCHEME"

    # get the validate_input code generated by AOB & indent it to match the validate_input() in the template (input_module_MOD_INPUT_NAME.py)
    VALIDATION=$(sed -n '/^    """Implement your own validation logic to validate/,/^def/p' input_module_$OUTPUT | sed 's/\(.*\)/   \1/')
    #VALIDATION="    def validate_input(self, definition):"$' \n'"$VALIDATION"      # add the new method definition 
    VALIDATION=$(echo "$VALIDATION" | sed 's/.*helper./#fixme please &/g')    # if this uses helper...  flag it to be fixed
    #echo "$VALIDATION"


    # get the collect_events code generated by AOB & indent it to match the stream_events() in the template (input_module_MOD_INPUT_NAME.py)
    STREAM_EVENTS=$(sed -n '/^    """Implement your data collection logic here/,//p' input_module_$OUTPUT | sed 's/\(.*\)/   \1/')

    # update the stream_events code (ucc does not have the helper or logger objects)
    STREAM_EVENTS=$(echo "$STREAM_EVENTS" | sed 's/helper.get_arg/input_items.get/g')
    STREAM_EVENTS=$(echo "$STREAM_EVENTS" | sed 's/helper.get_input_stanza_names()/input_name/g')
    STREAM_EVENTS=$(echo "$STREAM_EVENTS" | sed 's/helper.log_/logger./g')
    STREAM_EVENTS=$(echo "$STREAM_EVENTS" | sed 's/.*helper./#fixme please &/g')
    #echo "$STREAM_EVENTS"


    # Merge the scheme from AOB into the template
    new_input_source=$(< ../../ucc_mod_input_template.py)
    new_input_source=${new_input_source//SCHEME_LOCATION/"$SCHEME"}

    # Merge the validate_input code from AOB into the template
    new_input_source=${new_input_source//VALIDATION_LOCATION/"$VALIDATION"}

    # Merge the stream_events code from AOB into the template
    new_input_source=${new_input_source//STREAM_EVENTS_LOCATION/"$STREAM_EVENTS"}

    # Overwrite out the mod input source code file with this new code
    echo "$new_input_source" > $OUTPUT
    echo Done.   
done

# OK, let's get back to the main directory
cd ../..

echo
echo Cleaning Up... Removing files that are no longer needed
# remove AOB files and other things that will be automatically recreated with ucc-gen
rm ./package/default/addon_builder.conf 
rm ./package/default/*_settings.conf
rm ./package/metadata/local.meta 2> /dev/null
rm ./package/README.txt 2> /dev/null
rm ./package/bin/*.pyc 2> /dev/null
rm ./package/bin/__pycache__ 2> /dev/null
rm ./package/bin/input_module_*.py 
rm ./package/bin/${AOB_TA_DIR}_rh*.py 

rm -rf ./package/locale
rm -rf ./package/default/data
rm -rf ./package/README
rm -rf ./package/appserver
rm -rf ./package/bin/${AOB_TA_DIR_lowercase}
rm -rf ./package/bin/${AOB_TA_DIR_lowercase}_declare.py

echo Finished.
echo 

echo ##########  Items still missing    ########
echo 1. Does the new TA respect the proxy settings?
echo 2. Need to replace helper functions -- send_http_request, new_event, get_output_index, etc.
echo 3. What to do with checkpointing?
echo
echo
