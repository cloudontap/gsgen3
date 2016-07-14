[#ftl]
[#-- Standard inputs --]
[#assign blueprintObject = blueprint?eval]
[#assign credentialsObject = credentials?eval]
[#assign configurationObject = configuration?eval]
[#assign stackOutputsObject = stackOutputs?eval]
[#assign masterDataObject = masterData?eval]
[#-- High level objects --]
[#assign organisationObject = blueprintObject.Organisation]
[#assign accountObject = blueprintObject.Account]
[#assign projectObject = blueprintObject.Project]
[#assign solutionObject = blueprintObject.Solution]
[#-- Reference data --]
[#assign regions = masterDataObject.Regions]
[#assign categories = masterDataObject.Categories]
[#-- Reference Objects --]
[#assign regionObject = regions[region]]
[#assign projectRegionObject = regions[projectRegion]]
[#assign categoryObject = categories["alm"]]
[#-- Key values --]
[#assign organisationId = organisationObject.Id]
[#assign accountId = accountObject.Id]
[#assign accountName = accountObject.Name]
[#assign projectId = projectObject.Id]
[#assign projectName = projectObject.Name]
[#assign projectRegionId = projectRegionObject.Id]
[#assign projectDomainStem = (projectObject.Domain.Stem)!"gosource.com.au"]
[#assign projectDomainBehaviour = (projectObject.Domain.ProjectBehaviour)!""]
[#switch projectDomainBehaviour]
	[#case "naked"]
		[#assign projectDomain = projectDomainStem]
		[#break]
	[#case "includeProjectId"]
	[#default]
		[#assign projectDomain = projectId + "." + projectDomainStem]
[/#switch]
[#assign regionId = regionObject.Id]
[#assign categoryId = categoryObject.Id]
[#assign snsEnabled = false]
{
	"AWSTemplateFormatVersion" : "2010-09-09",
	"Resources" : { 
	    [#assign count = 0]
		[#-- SNS for project --]
		[#if snsEnabled]
            "snsXalerts" : {
                "Type": "AWS::SNS::Topic",
                "Properties" : {
                    "DisplayName" : "${(projectName + "-alerts")[0..9]}",
                    "TopicName" : "${projectName}-alerts",
                    "Subscription" : [
                        {
                            "Endpoint" : "alerts@${projectDomain}", 
                            "Protocol" : "email"
                        }
                    ]
                }
            } 
            [#assign count = count + 1]
		[/#if]
		[#-- Shared project level resources if we are in the project region --]
		[#if (regionId == projectRegionId)]
			[#if solutionObject.SharedComponents??]
				[#list solutionObject.SharedComponents as component] 
					[#if component.S3??]
						[#assign s3 = component.S3]
						[#if count > 0],[/#if]"s3X${component.Id}" : {
							"Type" : "AWS::S3::Bucket",
							"Properties" : {
								[#if s3.Name??]
									"BucketName" : "${s3.Name}.${projectDomain}",
								[#else]
									"BucketName" : "${component.Name}.${projectDomain}",
								[/#if]
								"Tags" : [ 
									{ "Key" : "gs:project", "Value" : "${projectId}" },
									{ "Key" : "gs:category", "Value" : "${categoryId}" }
								]
                                [#if s3.Lifecycle??]
                                    ,"LifecycleConfiguration" : {
                                        "Rules" : [
                                            {
                                                "Id" : "default",
                                                [#if s3.Lifecycle.Expiration??]
                                                   "ExpirationInDays" : ${s3.Lifecycle.Expiration},
                                                [/#if]
                                                "Status" : "Enabled"
                                            }
                                        ]
                                    }
                                [/#if]
							}
						}
						[#assign count = count + 1]
					[/#if]
				[/#list]
			[/#if]			
		[/#if]
	},

	"Outputs" : {
	    [#assign count = 0]
		[#if snsEnabled]
		    "snsXprojectXalertsX${regionId?replace("-","")}" : {
			    "Value" : { "Ref" : "snsXalerts" }
			}
            [#assign count = count + 1]
		[/#if]
		[#if (regionId == projectRegionId)]
			[#if count > 0],[/#if]"domainXprojectXdomain" : {
				"Value" : "${projectDomain}"
			}
			[#if solutionObject.SharedComponents??]
				[#list solutionObject.SharedComponents as component] 
					[#if component.S3??]
						,"s3XprojectX${component.Id}" : {
							"Value" : { "Ref" : "s3X${component.Id}" }
						}
					[/#if]
				[/#list]
			[/#if]			
		[/#if]
	}
}


