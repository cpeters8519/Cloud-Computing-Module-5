# Module 05 Autograder
import boto3
import json
import requests
import hashlib
import sys
import datetime
import os.path
import time
from tqdm import tqdm
import mysql.connector
from bs4 import BeautifulSoup
import re

# Assignment grand total
grandtotal = 0
totalPoints = 10
assessmentName = "module-05-assessment"
snapshotname                     = "coursera-snapshot"
correctNumberOfDBAcrossSubnets   = 3
correctNumOfDBSubnetGroups       = 1
correctNumberOfSecrets           = 2
correctNumberOfRolePolicies      = 4
correctNumberOfLts               = 1
correctNumberOfSnsTopics         = 1
correctNumberOfTargetGroups      = 1
correctNumberOfAutoScalingGroups = 1
correctNumberOfELBs              = 1
correctNumberOfEBS               = 3
correctNumberOfRDSSnapshots      = 1
correctNumberOfRDSInstances      = 1
correctNumberOfVpcs              = 2
correctNumberOfS3Buckets         = 2
correctNumberOfSGs               = 1
correctNumberOfInternetGateways  = 1
correctNumberOfRouteTables       = 1
correctNumberOfDHCPOptions       = 1
correctNumberOfObjectsInFinishedBucket = 2
tag = "module-05"
ec2tag = "backend"

# Function to print out current points progress
def currentPoints():
  print("Current Points: " + str(grandtotal) + " out of " + str(totalPoints) + ".")

# Documentation Links
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2.html
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/elbv2.html
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/autoscaling.html
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/rds.html

##############################################################################
# 10 tasks to cover
##############################################################################
# Check that there are two images in the finished bucket
#	Check that the number of images in the Raw bucket is less than the number in the Finished bucket
#	Have at more than one message on the Queue- (Messages > 1)
#	Check RDS instance for values in the Finished URL (presigned value) column
#	Check RDS instance has removed RAWURL values upon image editing completion
#	Confirm that the SQS Queue exists
#	Confirm that the SQS Queue visibility is 90 seconds and the visibility_timeout_seconds is 180 in the main.tf
#	Check for 4th EC2 instance tagged – Type: backend
#	Check for the presence of an iam_instance_policy attached to the EC2 instance tagged – Type: backend
#	Check that EC2 instance has an iam_role_policy named: sqs_fullaccess_policy and is attached to the IAM Role and grants the EC2 entity SQS full access.


clientec2 = boto3.client('ec2')
clientelbv2 = boto3.client('elbv2')
clientasg = boto3.client('autoscaling')
clients3 = boto3.client('s3')
clientrds = boto3.client('rds')
clientiam = boto3.client('iam')
clientsns = boto3.client('sns')
clientsqs = boto3.client('sqs')
clientsm = boto3.client('secretsmanager')

# SQS get Queue URL and COunt Messages
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/sqs/client/list_queues.html
responseSQSQueueList = clientsqs.list_queues()

# EC2 describe images
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_images.html
responseEC2AMI=clientec2.describe_images(    
  Filters=[
        {
            'Name': 'tag:Name',
            'Values': [
                tag,
            ]
        },
    ],
)
responseEC2IAMProfile=clientec2.describe_instances(    
  Filters=[ {
            'Name': 'tag:Type',
            'Values': [
                ec2tag,
            ]
        },
    ],
)
# Describe security groups
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_security_groups.html
responsesg = clientec2.describe_security_groups(
    Filters=[
        {
            'Name': 'tag:Name',
            'Values': [
                tag,
            ]
        },
    ],
)
# List Secrets
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/secretsmanager.html
responsesm = clientsm.list_secrets( Filters=[ { 'Key': 'tag-value','Values': [tag] }] )

# Describe DB Snapshots
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/rds/client/describe_db_snapshots.html

responserdssnapshot = clientrds.describe_db_snapshots()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/sns/client/list_topics.html

responsesns = clientsns.list_topics()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/iam/client/list_role_policies.html

responseiam = clientiam.list_role_policies(
     RoleName='project_role' 
)

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_vpcs.html

responseVPC = clientec2.describe_vpcs()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_subnets.html

responseSubnets = clientec2.describe_subnets(
    Filters=[
        {
            'Name': 'tag:Name',
            'Values': [
                tag,
            ]
        },
    ],
)

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_route_tables.html

responseRouteTables = clientec2.describe_route_tables(
    Filters=[
        {
            'Name': 'tag:Name',
            'Values': [
            tag,
            ]
        },
    ],
)

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_dhcp_options.html

responseDHCP = clientec2.describe_dhcp_options(
    Filters=[
        {
            'Name': 'tag:Name',
            'Values': [
            tag,
            ]
        },
    ],
)

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_security_groups.html
responseSG = clientec2.describe_security_groups(
    Filters=[
        {
            'Name': 'tag:Name',
            'Values': [
                tag,
            ]
        },
    ],
)

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_internet_gateways.html
responseIG = clientec2.describe_internet_gateways(
  Filters=[
        {
            'Name': 'tag:Name',
            'Values': [
                tag,
            ]
        },
    ],
)
# hello from will
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_subnets.html
responseSubnets = clientec2.describe_subnets(
  Filters=[
        {
            'Name': 'tag:Name',
            'Values': [
                tag,
            ]
        },
    ],
)

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_route_tables.html
responseRT = clientec2.describe_route_tables(
  Filters=[
        {
            'Name': 'tag:Name',
            'Values': [
                tag,
            ]
        },
    ],
)

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_dhcp_options.html
responseDhcpOptions = clientec2.describe_dhcp_options(
  Filters=[
        {
            'Name': 'tag:Name',
            'Values': [
                tag,
            ]
        },
    ],
)

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_instances.html
responseEC2 = clientec2.describe_instances(
 Filters=[
     {
         'Name': 'instance-state-name',
         'Values':['running']
     }
],
) # End of function

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3/client/list_buckets.html
# Get a Dict of all bucket names
responseS3 = clients3.list_buckets()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/elbv2/client/describe_load_balancers.html
responseELB = clientelbv2.describe_load_balancers()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/elbv2/client/describe_target_groups.html
responseTG = clientelbv2.describe_target_groups()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/autoscaling/client/describe_auto_scaling_groups.html
responseasg = clientasg.describe_auto_scaling_groups()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/autoscaling/client/describe_auto_scaling_instances.html
responseasgi = clientasg.describe_auto_scaling_instances()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/autoscaling/client/describe_auto_scaling_groups.html
responseasg = clientasg.describe_auto_scaling_groups()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/describe_launch_templates.html
responselt = clientec2.describe_launch_templates()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/rds/client/describe_db_instances.html
responselistinstances = clientrds.describe_db_instances()

# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/rds/client/describe_db_subnet_groups.html
responsedbsubnet = clientrds.describe_db_subnet_groups()

##############################################################################
print('*' * 79)
print("Begin tests for " + tag + " Assessment...")
##############################################################################

##############################################################################
# Check that there are at least two images in the finished bucket...
# Named: vegeta.jpg and knuth.jpg
##############################################################################
print('*' * 79)
print("Check that there are at least two images in the finished bucket...") 
print("Named: vegeta.jpg and knuth.jpg...")

knuth = False
vegeta = False

for n in range(0,len(responseS3['Buckets'])):
  if "finished" in responseS3['Buckets'][n]['Name']:
    BUCKET_NAME = responseS3['Buckets'][n]['Name']

responseS3Object = clients3.list_objects(
  Bucket=BUCKET_NAME 
  )

print("List Object Key Names found in the finished bucket...")
try:
  if len(responseS3Object['Contents']) >= correctNumberOfObjectsInFinishedBucket:
    for n in range(0,len(responseS3Object['Contents'])):
      print(str(responseS3Object['Contents'][n]['Key']))
      if "vegeta.jpg" in responseS3Object['Contents'][n]['Key']:
        vegeta = True
        print('Image vegeta.jpg found in Finished Bucket...')
      if "knuth.jpg" in responseS3Object['Contents'][n]['Key']:
        knuth = True
        print('Image knuth.jpg found in Finished Bucket...')
    
    if vegeta == True and knuth == True:
      grandtotal += 1
      currentPoints()
    else:
      currentPoints()

  else:
    print("The number of the images in your Finished bucket is below " + correctNumberOfObjectsInFinishedBucket + "...")
    print("Make sure you have gone to the ELB URL and uploaded the required number of images to the functioning application...")
    currentPoints()
except:
  print("No objects found in the finished bucket -- try to upload one image to your app...")
  currentPoints()
  #exit(0)

print('*' * 79)
print("\r")
##############################################################################
# Check that the number of images in the Raw bucket is less than the number
# in the Finished bucket
##############################################################################
print('*' * 79)
print("Testing to make sure the application is processing your RAW images to finished...")
print("Collecting bucket names...")
rawBucketImagesPresent = True
finishedBucketImagesPresent = True

for n in range(0,len(responseS3['Buckets'])):
    if "raw" in responseS3['Buckets'][n]['Name']:
        RAW_BUCKET_NAME = responseS3['Buckets'][n]['Name']
    if "finished" in responseS3['Buckets'][n]['Name']:
        FINISHED_BUCKET_NAME = responseS3['Buckets'][n]['Name']

print("Collecting Object Keys contained in the Raw and Finished buckets...")
#https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3/client/list_objects.html
#OBJECT_NAME = responseS3Object['Contents'][0]['Key']
print("Listing Raw Bucket objects...")
responseS3ObjectFin = clients3.list_objects(
    Bucket=FINISHED_BUCKET_NAME 
)
print("Listing Finished Bucket objects...")
responseS3ObjectRaw = clients3.list_objects(
    Bucket=RAW_BUCKET_NAME
)
try:
  responseS3ObjectRaw['Contents']
  print("You have: " + str(len(responseS3ObjectRaw['Contents'])) + " object(s) in your RAW bucket...")
except:
  print("RAW bucket contained 0 Objects, perhaps go back the the Web App and upload 3 or 4 images...") 
  rawBucketImagesPresent = False

try:
  responseS3ObjectFin['Contents']
  print("You have: " + str(len(responseS3ObjectFin['Contents'])) + " object(s) in your Finished bucket...")
except:
  print("FINISHED bucket contained 0 Objects, perhaps wait 8 or 16 minutes and let the application process your images...")
  finishedBucketImagesPresent = False
                                                                              
if rawBucketImagesPresent is True and finishedBucketImagesPresent is True and len(responseS3ObjectRaw['Contents']) <= len(responseS3ObjectFin['Contents']):
  print("Your application is working as you have more objects listed in your RAW bucket then in your Finished bucket...")
  grandtotal += 1
  currentPoints()
else:
  print("You have an incorrect balance of Objects in your Raw and Finished bucket...")
  print("Double check that you have gone through and uploaded 4 or 5 images for processing")
  print("to your web application and give it time to process each posted image...")
  currentPoints()
print('*' * 79)
print("\r")
##############################################################################
# Checking that you have at more than one message on the Queue- (Messages > 1)
##############################################################################
print('*' * 79)
print("Checking that you have one or more message on the Queue - (Messages >= 1)...")
messagesInQueue = False
queueURL = responseSQSQueueList['QueueUrls'][0]
# Retrieve an SQS Message
# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/sqs/client/receive_message.html
responseRetrieveMessage = clientsqs.receive_message(
    QueueUrl=queueURL,
    VisibilityTimeout=15
)

# Check to see if the queue is empty using the try/except block
try:
  responseRetrieveMessage['Messages']
  messagesInQueue = True
except:
  print("No messages found on the queue -- try to upload one image to your app...")


if messagesInQueue == True:
  print("You have messages in your SQS Queue...")
  grandtotal += 1
  currentPoints()
else:
  print("No messages were found in your SQS Queue...")
  print("You may need to go back and upload a few additional images to your application...")
  currentPoints()

print('*' * 79)
print("\r")
##############################################################################
# Check RDS instance for values in the Finished URL (presigned value) column
##############################################################################
print('*' * 79)
print("Check RDS instance for values in the Finished URL (presigned value) column...")
# https://www.crummy.com/software/BeautifulSoup/bs4/doc/

HTTP = 'http://'
ELBURL = responseELB['LoadBalancers'][0]['DNSName']
ELBPATH = "/db"
# Retrieve contents 
url = HTTP + ELBURL + ELBPATH  # Replace with your desired URL
response = requests.get(url)
soup = BeautifulSoup(response.content, 'html.parser')
tables = soup.find_all('table')

print("Found: " + str(len(soup.find_all(string=re.compile("null")))) + " unprocessed records...")
print("Found: " + str(len(soup.find_all(string=re.compile("https://s3")))) + " processed records...")

for i, table in enumerate(tables):
  print(f"Table {i+1}:")
  for row in table.find_all('tr'):
      cells = row.find_all(['td', 'th'])
      cell_text = [cell.get_text(strip=True) for cell in cells]
      print('\t'.join(cell_text))

if len(soup.find_all(string=re.compile("https://s3"))) > len(soup.find_all(string=re.compile("null"))):
  print("")
  print("You have the correct number of processed records compared to unprocessed records...")
  grandtotal += 1
  currentPoints()
elif len(soup.find_all(string=re.compile("https://s3"))) == len(soup.find_all(string=re.compile("null"))):
  print("")
  print("You have the same number of processed records compared to unprocessed records...")
  currentPoints()
else:
  print("")
  print("You have more unprocessed records than processed records...")
  print("Go back to your ELB URL: " + ELBURL + "...")
  print("Upload a few images and wait for your system to process them and try to run the test again...")
  currentPoints()
  
print('*' * 79)
print("\r")
##############################################################################
# Checking if RDS instance has removed the original RAWURL values upon 
# image editing completion
##############################################################################
print('*' * 79)
print("Checking if RDS instance has removed the original RAWURL values upon ") 
print("image editing completion... ")

# https://www.crummy.com/software/BeautifulSoup/bs4/doc/

HTTP = 'http://'
ELBURL = responseELB['LoadBalancers'][0]['DNSName']
ELBPATH = "/db"
# Retrieve contents 
url = HTTP + ELBURL + ELBPATH  # Replace with your desired URL
response = requests.get(url)
soup = BeautifulSoup(response.content, 'html.parser')
tables = soup.find_all('table')

print("Found: " + str(len(soup.find_all(string=re.compile("done")))) + " records indicating that RAW image(s) have been processed...")

if len(soup.find_all(string=re.compile("done"))) >= 1:
  print("You have 1 or more RAW image has been processed and the RAWURL field has been updated to say 'done'...")
  grandtotal += 1
  currentPoints()
else:
  print("Make sure you have gone back to the app.py and added the section that will")
  print("update the RAWS3URL to say 'done'...")
  currentPoints()
  
print('*' * 79)
print("\r")
##############################################################################
# Checking to confirm that the SQS Queue exists
##############################################################################
print('*' * 79)
print("Checking to confirm that the SQS Queue exists...")

queueURL = responseSQSQueueList['QueueUrls'][0]

try:
  print("You have one Queue and its URL is: " + str(responseSQSQueueList['QueueUrls'][0]) + "...")
  grandtotal += 1
  currentPoints()
except:
  print("You have no SQS Queues, double check your main.tf file to make sure you have created one...")
  currentPoints()

print('*' * 79)
print("\r")
##############################################################################
# Testing that the SQS Queue visibility_timeout_seconds is 180 
# and Default delay is 90 seconds
##############################################################################
print('*' * 79)
print("Testing that the SQS Queue visibility_timeout_seconds is 180 seconds...")
print("and Default delay is 90 seconds...")
visibilityTimeout = False
defaultDelay = False

responseSQSAttributes = clientsqs.get_queue_attributes(
     QueueUrl=queueURL,
     AttributeNames=['VisibilityTimeout', "DelaySeconds"] 
)

try: 
  print("The stated attributes of your SQS queue are... ")
  print("VisibilityTimeout: " + responseSQSAttributes['Attributes']['VisibilityTimeout'])
  print("Default Delivery Delay is: " + responseSQSAttributes['Attributes']['DelaySeconds'])
except:
  print("There is no SQS queue to get attributes from, check your main.tf to make sure you have created an SQS queue")
  print("with the proper attributes set...")
  currentPoints()


if responseSQSAttributes['Attributes']['VisibilityTimeout'] == "180":
  print("Your VisibilityTimeout is set correctly to 180 seconds...")
  visibilityTimeout = True
else:
  print("Your VisibilityTimeout is set incorrectly, check the main.tf to see if you have set the attribute correctly...")

if responseSQSAttributes['Attributes']['DelaySeconds'] == "90":
  print("Your Default Delivery Delay is set correctly to 90 seconds...")
  defaultDelay = True
else:
  print("Your Default Delay is set incorrectly, check the main.tf to see if you have set the attribute correctly...")

if visibilityTimeout is True and defaultDelay is True:
  grandtotal += 1
  currentPoints()
else:
  currentPoints()

print('*' * 79)
print("\r")
##############################################################################
# Check for 4th EC2 instance tagged – Type: backend
##############################################################################
print('*' * 79)
print("Testing to see the 4th EC2 instance tagged: " + ec2tag + "...")

try:
  print("There is one EC2 instance tagged: " + ec2tag + "...")
  print("instance-id: " + str(responseEC2IAMProfile['Reservations'][0]['Instances'][0]['InstanceId']))
  grandtotal += 1
  currentPoints()
except:
  print("There are no EC2 instances tagged: " + ec2tag + "...")
  print("Perhaps look at the main.tf aws_ec2_instance and check that the proper additional tag was added Type: backed ")
  print("Case matters!!!")
  currentPoints()

print('*' * 79)
print("\r")
##############################################################################
# Check for the presence of an iam_instance_policy attached to the 
# EC2 instance tagged – Type: backend
# ##############################################################################
print('*' * 79)
print("Check for the presence of an iam_instance_policy attached to the")
print("EC2 instance tagged: " + ec2tag + "...")

profile_count = 0

print("These are the ARNs of your attached IAM Instance Profiles...")
for n in range(0,len(responseEC2IAMProfile['Reservations'])):
  print("IAM Profile ARN of: " + responseEC2IAMProfile['Reservations'][n]['Instances'][0]['IamInstanceProfile']['Arn'])
  print("For instanceID: " + str(responseEC2IAMProfile['Reservations'][n]['Instances'][0]['InstanceId']))
  if responseEC2IAMProfile['Reservations'][n]['Instances'][0]['IamInstanceProfile']['Arn'] != "":
    profile_count += 1

if len(responseEC2IAMProfile['Reservations']) == profile_count:
  print("Well done! You have an IAM Instance profile per instance... ")
  grandtotal += 1
  currentPoints()
else:
  print("You have an incorrect number of IAM Instance Profiles...") 
  print("These are the ARNs of your attached IAM Instance Profiles...")
  for n in range(0,len(responseEC2IAMProfile['Reservations'])):
    print(str(responseEC2IAMProfile['Reservations'][n]['Instances'][0]['IamInstanceProfile']['Arn']) + " for instanceID: " + str(responseEC2IAMProfile['Reservations'][n]['Instances'][0]['InstanceId']))      
  
  print("Perhaps double check that you added an IAM Instance Profile Value to your Launch Template in the main.tf...")
  print("Or you may need to run terraform destroy to clean up a previous lab...")
  currentPoints()

print('*' * 79)
print("\r")
##############################################################################
# Check that EC2 instance has an iam_role_policy named: sqs_fullaccess_policy 
# and is attached to the IAM Role and grants the EC2 entity SQS full access.
##############################################################################
print('*' * 79)
print("Check that EC2 instance has an iam_role_policy named: sqs_fullaccess_policy") 
print("and is attached to the IAM Role and grants the EC2 entity SQS full access.")

responseIAMRolePolicies = clientiam.list_role_policies(RoleName="project_role")
policyPresent = False

try:
  print("Printing IAM Role Policies attached to the IAM Role: project_role...")
  for n in range(0,len(responseIAMRolePolicies['PolicyNames'])):
    print("IAM Policy attached to IAM Role: " + responseIAMRolePolicies['PolicyNames'][n])
    if responseIAMRolePolicies['PolicyNames'][n] == "sqs_fullaccess_policy":
      print("The IAM Role Policy: sqs_fullaccess_policy is present...")
      policyPresent = True

  if policyPresent == False:
    print("The IAM Role Policy: sqs_fullaccess_policy is not present...")  

except:
  print("No IAM Role policies that match the required: sqs_fullaccess_policy attached to the IAM Role...")
  print("Perhaps look back in the main.tf and at the structure of the additional IAM Role Policies...")
  print("Watch out that it is spelled: sqs_fullaccess_policy...")  

if policyPresent == True:
  grandtotal += 1
  currentPoints()
else:
  currentPoints()

print('*' * 79)
print("\r")
##############################################################################
# Print out the grandtotal and the grade values to result.txt
##############################################################################
print('*' * 79)
print("Your result is: " + str(grandtotal) + " out of " + str(totalPoints) + " points.")
print("You can retry any items that need adjustment and retest...")

# Write results to a text file for import to the grade system
# https://www.geeksforgeeks.org/sha-in-python/
f = open('module-05-results.txt', 'w', encoding="utf-8")

# Gather sha256 of module-name and grandtotal
# https://stackoverflow.com/questions/70498432/how-to-hash-a-string-in-python
# Create datetime timestamp
dt='{:%Y%m%d%H%M%S}'.format(datetime.datetime.now())
resultToHash=(assessmentName + str(grandtotal/totalPoints) + dt)
h = hashlib.new('sha256')
h.update(resultToHash.encode())

resultsdict = {
  'Name': assessmentName,
  'gtotal' : grandtotal/totalPoints,
  'datetime': dt,
  'sha': h.hexdigest() 
}

listToHash=[assessmentName,grandtotal,dt,h.hexdigest()]
print("Writing assessment grade to text file...")
json.dump(resultsdict,f)
print("Write successful! Ready to submit your Assessment...")
print("You should now see a module-05-results.txt file has been generated on your CLI...")
print("Submit this to Coursera as your deliverable...")
f.close
print('*' * 79)
print("\r")
