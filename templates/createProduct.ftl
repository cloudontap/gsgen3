[#ftl]
[#-- Standard inputs --]
[#assign blueprintObject = blueprint?eval]
[#assign credentialsObject = credentials?eval]
[#assign appSettingsObject = appsettings?eval]
[#assign stackOutputsObject = stackOutputs?eval]

[#-- High level objects --]
[#assign tenantObject = blueprintObject.Tenant]
[#assign accountObject = blueprintObject.Account]
[#assign productObject = blueprintObject.Product]
[#assign sharedComponentsPresent = (blueprintObject.Solution.SharedComponents)?? ]
[#if sharedComponentsPresent]
    [#assign sharedComponents = blueprintObject.Solution.sharedComponents]
[/#if]
    
[#-- Reference data --]
[#assign regions = blueprintObject.Regions]

[#-- Reference Objects --]
[#assign regionObject = regions[region]]
[#assign accountRegionObject = regions[accountRegion]]
[#assign productRegionObject = regions[productRegion]]

[#-- Key ids/names --]
[#assign tenantId = tenantObject.Id]
[#assign accountId = accountObject.Id]
[#assign productId = productObject.Id]
[#assign productName = productObject.Name]
[#assign regionId = regionObject.Id]
[#assign accountRegionId = accountRegionObject.Id]
[#assign productRegionId = productRegionObject.Id]

[#-- Domains --]
[#assign productDomainStem = productObject.Domain.Stem]
[#assign productDomainBehaviour = (productObject.Domain.ProductBehaviour)!""]
[#switch productDomainBehaviour]
    [#case "includeProduct"]
        [#assign productDomain = productName + "." + productDomainStem]
        [#assign productDomainQualifier = ""]
        [#break]
    [#case "naked"]
        [#assign productDomain = productDomainStem]
        [#assign productDomainQualifier = ""]
        [#break]
    [#default]
        [#assign productDomain = productDomainStem]
        [#assign productDomainQualifier = "-" + productName]
        [#break]
[/#switch]

[#-- Get stack output --]
[#function getKey key]
    [#list stackOutputsObject as pair]
        [#if pair.OutputKey==key]
            [#return pair.OutputValue]
        [/#if]
    [/#list]
[/#function]

[#-- Product --]
[#assign snsEnabled = false]
[#assign rotateKeys = (productObject.RotateKeys)!true]

{
    "AWSTemplateFormatVersion" : "2010-09-09",
    "Resources" : { 
        [#-- Key for product --]
        "cmk" : {
            "Type" : "AWS::KMS::Key",
            "Properties" : {
                "Description" : "${productName}",
                "Enabled" : true,
                "EnableKeyRotation" : ${(rotateKeys)?string("true","false")},
                "KeyPolicy" : {
                    "Version": "2012-10-17",
                    "Statement": [ 
                        {
                            "Effect": "Allow",
                            "Principal": { 
                                "AWS": { 
                                    "Fn::Join": [
                                        "", 
                                        [
                                            "arn:aws:iam::",
                                            { "Ref" : "AWS::AccountId" },
                                            ":root"
                                        ]
                                    ]
                                }
                            },
                            "Action": [ "kms:*" ],
                            "Resource": "*"
                        }
                    ]
                }
            }
        }
        [#-- SNS for product --]
        [#if snsEnabled]
            ,"snsXalerts" : {
                "Type": "AWS::SNS::Topic",
                "Properties" : {
                    "DisplayName" : "${(productName + "-alerts")[0..9]}",
                    "TopicName" : "${productName}-alerts",
                    "Subscription" : [
                        {
                            "Endpoint" : "alerts@${productDomain}", 
                            "Protocol" : "email"
                        }
                    ]
                }
            } 
       [/#if]
       [#-- Shared product level resources if we are in the product region --]
        [#if (regionId == productRegionId)]
            [#if sharedComponentsPresent]
                [#list sharedComponents as component] 
                    [#if component.S3??]
                        [#assign s3 = component.S3]
                        ,"s3X${component.Id}" : {
                            "Type" : "AWS::S3::Bucket",
                            "Properties" : {
                                [#if s3.Name??]
                                    "BucketName" : "${s3.Name}${productDomainQualifier}.${productDomain}",
                                [#else]
                                    "BucketName" : "${component.Name}${productDomainQualifier}.${productDomain}",
                                [/#if]
                                "Tags" : [ 
                                    { "Key" : "cot:product", "Value" : "${productId}" },
                                    { "Key" : "cot:category", "Value" : "${categoryId}" }
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
                    [/#if]
                [/#list]
            [/#if]
        [/#if]
    },
    
    "Outputs" : {
        "cmkXproductXcmk" : {
            "Value" : { "Ref" : "cmk" }
        }
        [#if snsEnabled]
            ,"snsXproductXalertsX${regionId?replace("-","")}" : {
                "Value" : { "Ref" : "snsXalerts" }
            }
        [/#if]
        [#if (regionId == productRegionId)]
            ,"domainXproductXdomain" : {
                "Value" : "${productDomain}"
            }
            ,"domainXproductXqualifier" : {
                "Value" : "${productDomainQualifier}"
            }
            [#if sharedComponentsPresent]
                [#list sharedComponents as component] 
                    [#if component.S3??]
                        ,"s3XproductX${component.Id}" : {
                            "Value" : { "Ref" : "s3X${component.Id}" }
                        }
                    [/#if]
                [/#list]
            [/#if]
        [/#if]
    }
}
