#!/bin/bash

set -e

BUCKET_NAME=test-cvast-potree
POTREE_WWW=/var/www/potree
POINTCLOUD_OUTPUT_FOLDER=${POTREE_WWW}/resources/pointclouds
POINTCLOUD_INPUT_FOLDER=${POINTCLOUD_INPUT_FOLDER}
IS_S3_FILE=False
S3_POINTCLOUD_INPUT_FOLDER=s3://${BUCKET_NAME}/pointcloud_input_folder

HELP_TEXT="
	Arguments:

	runserver: Runs Potree in Nginx. 
		No further expected commands.

	convert: Converts provided file into Potree format. 
		Further required commands: 
			-f or --file <file name>: input pointcloud file
		Further optional commands:
			-s3 or --s3: File is stored in AWS S3 bucket: ${S3_POINTCLOUD_INPUT_FOLDER}
			-n or --generate-page <page name>: Generates a ready to use web page with the given name.
			-o or --overwrite: overwrites existing pointcloud with same output name (-n or --name)
			--aabb \"<coordinates>\": Bounding cube as \"minX minY minZ maxX maxY maxZ\". If not provided it is automatically computed

	download_pointclouds: Synchronizes pointclouds stored in ${BUCKET_NAME} to local storage
		No further expected commands.

	upload_pointclouds: Synchronizes pointclouds stored in local storage to ${BUCKET_NAME}
		No further expected commands.

	-h or --help: Display help text

	Environment variables required:
		AWS_ACCESS_KEY_ID: The AWS Access Key ID of your AWS account
		AWS_SECRET_ACCESS_KEY: The AWS Secret Access Key of your AWS account
		AWS_DEFAULT_REGION: The AWS region in which your S3 bucket resides.
"

display_help() {
	echo "${HELP_TEXT}"
}


runserver() {
	echo "Running NginX server..."
	exec service nginx start
}

convert_file() {
	# Copy file from S3 bucket
	if [[ ${IS_S3_FILE} == True ]]; then
		copy_input_file_from_s3
	fi
	
	# Convert the file
	if [[ ! -z ${INPUT_FILE} ]] && [[ ! -z ${OUTPUT_NAME} ]]; then
		PotreeConverter "${POINTCLOUD_INPUT_FOLDER}/${INPUT_FILE}" -o ${POTREE_WWW} -p "${OUTPUT_NAME}" ${OVERWRITE} ${BOUNDING_BOX_OPTION} "${BOUNDING_BOX_ARGUMENTS}"
	else
		echo "Todo: conversion without additional parameters"
	fi
	
	# Post-processing / cleanup / upload pointcloud
	copy_frontend_files
	delete_obsolete_files
	upload_pointcloud
}

download_pointclouds() {
	echo "Syncing s3 bucket ${BUCKET_NAME} to local pointcloud folder..."
	aws s3 sync s3://${BUCKET_NAME} /var/www/potree/resources/pointclouds
}

upload_pointcloud() {
	aws s3 sync ${POINTCLOUD_OUTPUT_FOLDER} s3://${BUCKET_NAME}
}

copy_input_file_from_s3() {
	echo "Copying  ${S3_POINTCLOUD_INPUT_FOLDER}/${INPUT_FILE} to local pointcloud folder (${POINTCLOUD_INPUT_FOLDER}/${INPUT_FILE})..."
	aws s3 cp "${S3_POINTCLOUD_INPUT_FOLDER}/${INPUT_FILE}" "${POINTCLOUD_INPUT_FOLDER}/${INPUT_FILE}"
}

copy_frontend_files() {
	mv ${POTREE_WWW}/examples/${OUTPUT_NAME}.html ${POTREE_WWW}/pages/${OUTPUT_NAME}.html
	mv ${POTREE_WWW}/examples/${OUTPUT_NAME}.js ${POTREE_WWW}/pages/${OUTPUT_NAME}.js
}

delete_obsolete_files() {
	rm -rf ${POTREE_WWW}/examples/css 
	rm -rf ${POTREE_WWW}/examples/js
}



 # Script parameters 

# Use -gt 1 to consume two arguments per pass in the loop (e.g. each
# argument has a corresponding value to go with it).
# Use -gt 0 to consume one or more arguments per pass in the loop (e.g.
# some arguments don't have a corresponding value to go with it, such as --help ).

# If no arguments are supplied, assume the server needs to be run
if [[ $#  -eq 0 ]]; then
	RUN_SERVER=True
fi

# Else, process arguments
while [[ $# -gt 0 ]]
do
	key="$1"

	case ${key} in
		convert)
			echo "Command provided: convert. This may take a while..."
			CONVERT_FILE=True
			# No further option/value expected, this is a single command, so no 'shift'
		;;
		runserver)
			RUN_SERVER=True
			# No further option/value expected, this is a single command, so no 'shift'
		;;
		download_pointclouds)
			echo "Command provided: download_pointclouds. This may take a while..."
			DOWNLOAD_POINTCLOUDS=True
		;;
		upload_pointclouds)
			echo "Command provided: upload_pointclouds. This may take a while..."
			UPLOAD_POINTCLOUDS=True
		;;		
		-f|--file)
			INPUT_FILE="$2"
			shift; # next argument
		;;
		-s3|--s3)
			IS_S3_FILE=True
		;;
		-p|--generate-page)
			OUTPUT_NAME="$2"
			shift # next argument
		;;
		-o|--overwrite)
			# Remains empty if not set:
			OVERWRITE="--overwrite"
			# No further option/value expected, this is a single command, so no 'shift'
		;;
		--aabb)
			# Remains empty if not set:
			BOUNDING_BOX_OPTION="--aabb "
			BOUNDING_BOX_ARGUMENTS=$2
			shift # next argument
		;;
		bash)
			if [[ -z "$2" ]]; then
				bash
			else
				bash -c "${@:2}"
			fi
			exit 0
		;;	
		-h|--help)
			display_help
			exit 0
		;;
		*)
			echo "Unknown option: ${key}"
			display_help
			exit 1
		;;
	esac
	shift # next argument or value
done


# Global variables (parsed through Docker run command)
if [[ -z ${AWS_ACCESS_KEY_ID} ]]; then
	echo "Environment variable AWS_ACCESS_KEY_ID not specified, exiting..."
	exit 1
fi

if [[ -z ${AWS_SECRET_ACCESS_KEY} ]]; then
	echo "Environment variable AWS_SECRET_ACCESS_KEY not specified, exiting..."
	exit 1
fi

if [[ -z ${AWS_DEFAULT_REGION} ]]; then
	echo "Environment variable AWS_DEFAULT_REGION not specified, exiting..."
	exit 1
fi
	
	
if [[ ${RUN_SERVER} == True ]]; then
	runserver
elif [[ ${CONVERT_FILE} == True ]]; then
	convert_file
	exit 0
elif [[ ${DOWNLOAD_POINTCLOUDS} == True ]]; then
	download_pointclouds
	exit 0
elif [[ ${UPLOAD_POINTCLOUDS} == True ]]; then
	upload_pointcloud
	exit 0
fi